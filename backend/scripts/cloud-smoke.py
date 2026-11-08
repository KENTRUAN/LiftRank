"""Opt-in rehearsal against the configured development backend (uses live quotas).

Run from the repository root: python3 backend/scripts/cloud-smoke.py [--ai]
Requires ignored SocialConfig.plist and gcloud login for test-data cleanup.
Tokens and provider keys remain in memory and are never printed.
"""
import argparse
import hashlib
import json
import pathlib
import plistlib
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--ai', action='store_true', help='Also run one avatar and two companion requests')
parser.add_argument('--trainer', action='store_true', help='Validate live trainer todo edits and a seven-day schedule')
parser.add_argument('--generic-unconfigured', action='store_true', help='Verify generic AI fails clearly without a separate key')
args = parser.parse_args()
root = pathlib.Path(__file__).resolve().parents[2]
with (root / 'LiftRank/Resources/SocialConfig.plist').open('rb') as handle:
    config = plistlib.load(handle)
assert config['PROJECT_ID'] == 'liftrank-514018', 'Rehearsal is restricted to the development project.'
admin_token = subprocess.run(['gcloud', 'auth', 'print-access-token'], check=True, capture_output=True, text=True).stdout.strip()
base = config['API_URL'].rstrip('/')
database = config['DATABASE_URL'].rstrip('/')
guests = []
assets = []


def request(url, body=None, token=None, method=None, expected=200):
    headers = {'Content-Type': 'application/json'}
    if token:
        headers['Authorization'] = 'Bearer ' + token
    req = urllib.request.Request(url, data=json.dumps(body).encode() if body is not None else None,
                                 headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=170) as response:
            status, raw = response.status, response.read()
    except urllib.error.HTTPError as error:
        status, raw = error.code, error.read()
    value = json.loads(raw) if raw else None
    # Do not include URL, request/response bodies or credentials in failures.
    assert status == expected, f'Expected HTTP {expected}, received {status}'
    return value


def api(guest, path, body=None, expected=200):
    return request(base + '/' + path, {} if body is None else body, guest['idToken'], expected=expected)


def db(path, guest=None, body=None, method=None, expected=200):
    url = database + '/' + path + '.json'
    if guest:
        url += '?auth=' + urllib.parse.quote(guest['idToken'], safe='')
    return request(url, body, None if guest else admin_token, method, expected)


try:
    assert request(base + '/health')['status'] == 'ok'
    request(base + '/rooms/join', {}, expected=401)
    for name in ['QA Jordan', 'QA Taylor', 'QA Observer']:
        guest = request('https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=' + config['API_KEY'], {'returnSecureToken': True})
        guests.append(guest)
        api(guest, 'profile', {'name': name, 'gsr': 500, 'interests': 'Bench press and strength'})
    a, b, c = guests
    api(a, 'friends/' + b['localId'] + '/request', expected=403)
    db('profiles/' + b['localId'], a, expected=401)
    first = api(a, 'rooms/join', {'roomId': 'demo-gym'})
    second = api(b, 'rooms/join', {'roomId': 'demo-gym'})
    assert (first['spawnX'], first['spawnY']) != (second['spawnX'], second['spawnY'])
    for guest, lease in [(a, first), (b, second)]:
        db('world/rooms/demo-gym/presence/' + guest['localId'], guest, {
            'uid': guest['localId'], 'sessionId': lease['sessionId'], 'x': lease['spawnX'], 'y': lease['spawnY'],
            'station': 'lounge', 'status': 'Ready', 'openToChat': True, 'updatedAt': {'.sv': 'timestamp'},
        }, 'PUT')
    presence = db('world/rooms/demo-gym/presence', b)
    assert a['localId'] in presence and b['localId'] in presence
    api(a, 'equipment/bench/claim')
    db('world/rooms/demo-gym/presence/' + a['localId'], a,
       {'x': 3, 'y': 5, 'station': 'bench', 'status': 'Training', 'updatedAt': {'.sv': 'timestamp'}}, 'PATCH')
    assert db('world/rooms/demo-gym/presence/' + a['localId'], b)['station'] == 'bench'
    db('world/rooms/demo-gym/presence', c, expected=401)
    print('PASS: authenticated rooms, shared movement/stations, outsider access denied', flush=True)

    api(a, 'friends/' + b['localId'] + '/request')
    accepted = api(b, 'friends/' + a['localId'] + '/accept')
    chat = accepted['conversationId']
    for sender, recipient in [(a, b), (b, a)]:
        api(sender, 'messages/private/' + recipient['localId'], {'id': str(uuid.uuid4()), 'text': 'Cloud rehearsal hello'})
    assert len(db('social/chats/' + chat + '/messages', b)) == 2
    db('social/chats/' + chat, c, expected=401)
    api(a, 'messages/room/demo-gym', {'id': 'qa-' + a['localId'], 'text': 'Cloud rehearsal room message'})
    print('PASS: friendship acceptance, bidirectional private chat, third-user privacy, room chat', flush=True)

    api(b, 'equipment/bench/claim', expected=409)
    api(b, 'equipment/bench/request', {'mode': 'workIn'})
    api(a, 'equipment/bench/accept', {'targetID': b['localId']})
    equipment = db('world/rooms/demo-gym/equipment/bench', b)
    assert set(equipment['members']) == {a['localId'], b['localId']}
    api(b, 'equipment/bench/release')
    api(b, 'equipment/cardio/claim')
    third = api(c, 'rooms/join', {'roomId': 'demo-gym'})
    db('world/rooms/demo-gym/presence/' + c['localId'], c, {
        'uid': c['localId'], 'sessionId': third['sessionId'], 'x': third['spawnX'], 'y': third['spawnY'],
        'station': 'lounge', 'status': 'Ready', 'visibility': 'public', 'updatedAt': {'.sv': 'timestamp'},
    }, 'PUT')
    api(c, 'equipment/cardio/request', {'mode': 'workIn'}, expected=409)
    api(c, 'profile', {'name': 'QA Observer', 'visibility': 'anonymous'})
    hidden = api(c, 'rooms/join', {'roomId': 'demo-gym'})
    assert hidden['publicID'].startswith('anon-') and hidden['publicID'] != c['localId']
    db('world/rooms/demo-gym/presence/' + hidden['publicID'], c, {
        'uid': hidden['publicID'], 'sessionId': hidden['sessionId'], 'x': hidden['spawnX'], 'y': hidden['spawnY'],
        'station': 'lounge', 'status': 'Ready', 'visibility': 'anonymous', 'updatedAt': {'.sv': 'timestamp'},
    }, 'PUT')
    assert db('world/rooms/demo-gym/presence/' + c['localId'], a) is None
    db('profiles/' + c['localId'], a, expected=401)
    api(c, 'friends/' + a['localId'] + '/request', expected=403)
    api(a, 'friends/' + c['localId'] + '/request', expected=403)
    print('PASS: accepted work-in, exclusive cardio, anonymous alias, hidden profile and denied connections', flush=True)

    if args.trainer:
        catalog = [{'key': 'bench_press', 'name': 'Bench press', 'cardio': False}, {'key': 'running', 'name': 'Running', 'cardio': True}, {'key': 'deadlift', 'name': 'Deadlift', 'cardio': False}, {'key': 'pullup', 'name': 'Pull-Up', 'cardio': False}]
        context = {'localDate': '2026-11-07', 'catalog': catalog, 'activeWorkout': {'activity': 'Strength', 'completed': [{'exerciseKey': 'bench_press', 'sets': 1}], 'remaining': []}, 'schedule': [], 'goals': 'Strength'}
        reply = api(a, 'trainer', {**context, 'messages': [{'role': 'user', 'text': 'Add exactly two remaining sets of bench press, 8 reps, 90 seconds rest to my current workout todos. Keep my already recorded set.'}]})
        assert len(reply['todos']) == 1 and reply['todos'][0]['exerciseKey'] == 'bench_press' and reply['todos'][0]['sets'] == 2
        reply = api(a, 'trainer', {**context, 'messages': [{'role': 'user', 'text': 'Create a seven-day schedule starting today, including rest days. Use only bench press and running. Do not change my current workout todos.'}]})
        assert len(reply['schedule']) == 7 and {day['dayOffset'] for day in reply['schedule']} == set(range(7)) and reply['todos'] is None
        for prompt, exercise in [('add deadlift', 'deadlift'), ('add pull up', 'pullup')]:
            result = api(a, 'trainer', {**context, 'messages': [{'role': 'user', 'text': prompt}]})
            assert exercise in {item['exerciseKey'] for item in result['todos']}
            old = context['activeWorkout']['remaining']
            for item in old:
                assert item in result['todos'], 'Unrelated todos changed'
            context['activeWorkout']['remaining'] = result['todos']
        print('PASS: live trainer creates requested todos, preserves the list, handles short additions and schedules seven days', flush=True)

    gyms = api(a, 'gyms/search', {'query': 'gyms in New York'})['gyms']
    assert gyms
    gym = gyms[0]
    now = int(time.time() * 1000)
    location = {'latitude': gym['latitude'], 'longitude': gym['longitude'], 'accuracy': 20, 'timestamp': now}
    for point, status in [(None, 400), ({**location, 'accuracy': 101}, 400),
                          ({**location, 'timestamp': now - 61000}, 400),
                          ({**location, 'latitude': 0, 'longitude': 0}, 403)]:
        api(a, 'rooms/join', {'placeID': gym['placeID'], 'location': point}, expected=status)
    print('PASS: live Places search; missing, inaccurate, stale and distant check-ins denied', flush=True)

    if args.generic_unconfigured:
        api(a, 'companion', {'messages': [{'role': 'user', 'text': 'Introduce me'}], 'targetID': b['localId']}, expected=503)
        api(a, 'avatars/generate', {'prompt': 'Game character'}, expected=503)
        assert len(db('social/chats/' + chat + '/messages', b)) == 2
        print('PASS: missing general AI key gives explicit errors and leaves messaging usable', flush=True)

    if args.ai:
        reply = api(a, 'companion', {'messages': [{'role': 'user', 'text': 'What sets and reps are planned for me today?'}],
                                   'workout': 'Bench press: 3 sets of 8 reps', 'station': 'bench'})['reply']
        assert '3' in reply and '8' in reply
        draft = api(a, 'companion', {'messages': [{'role': 'user', 'text': 'Help me introduce myself'}], 'targetID': b['localId']})['reply']
        assert draft and len(db('social/chats/' + chat + '/messages', b)) == 2
        print('PASS: live trainer uses workout context; introduction remains an unsent draft', flush=True)
        preview = api(a, 'avatars/generate', {'prompt': 'Friendly illustrated adult gym character, short purple hair'})
        approved = api(a, 'avatars/approve', {'image': preview})
        assets.append(approved['assetPath'])
        assert db('profiles/' + a['localId'], b)['avatar']['assetPath'] == approved['assetPath']
        api(a, 'avatars/generate', {'prompt': 'test', 'selfie': {'mimeType': 'image/png', 'data': 'invalid'}}, expected=400)
        assert db('profiles/' + a['localId'], b)['avatar']['assetPath'] == approved['assetPath']
        print('PASS: live generated avatar approval is shared; failed generation preserves it', flush=True)

    api(b, 'friends/' + a['localId'] + '/block')
    api(a, 'messages/private/' + b['localId'], {'id': str(uuid.uuid4()), 'text': 'blocked'}, expected=403)
    api(a, 'friends/' + b['localId'] + '/request', expected=403)
    db('social/chats/' + chat, a, expected=401)
    replacement = api(a, 'rooms/join', {'roomId': 'demo-gym'})
    api(a, 'rooms/renew', {'sessionId': first['sessionId']}, expected=403)
    api(a, 'rooms/leave', {'sessionId': first['sessionId']})
    assert api(a, 'rooms/renew', {'sessionId': replacement['sessionId']})['sessionId'] == replacement['sessionId']
    api(a, 'rooms/leave', {'sessionId': replacement['sessionId']})
    api(b, 'rooms/leave', {'sessionId': second['sessionId']})
    print('PASS: blocking, room replacement and session-safe cleanup', flush=True)
finally:
    # Remove only records created by this rehearsal; retain project quota usage.
    for guest in guests:
        uid = guest['localId']
        lease = db('world/memberships/' + uid)
        if lease:
            api(guest, 'rooms/leave', {'sessionId': lease['sessionId']})
        for path in ['profiles/' + uid, 'world/memberships/' + uid, 'world/rooms/demo-gym/presence/' + uid,
                     'social/friends/' + uid, 'social/blocks/' + uid, 'roomMessages/demo-gym/qa-' + uid]:
            db(path, method='DELETE')
    for a in guests:
        for b in guests:
            if a['localId'] < b['localId']:
                chat = hashlib.sha256(('\0'.join(sorted([a['localId'], b['localId']]))).encode()).hexdigest()
                db('social/chats/' + chat, method='DELETE')
    for path in assets:
        request('https://storage.googleapis.com/storage/v1/b/' + config['STORAGE_BUCKET'] + '/o/' + urllib.parse.quote(path, safe=''),
                token=admin_token, method='DELETE', expected=204)
    for guest in guests:
        request('https://identitytoolkit.googleapis.com/v1/accounts:delete?key=' + config['API_KEY'], {'idToken': guest['idToken']})
    print('Rehearsal accounts and generated assets cleaned up.', flush=True)
