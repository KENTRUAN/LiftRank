import test from 'node:test';
import assert from 'node:assert/strict';
import { companionReply, generateAvatar, trainerPlanReply, trainerModel } from '../src/providers.js';
import { validatedTrainerReply } from '../src/trainer.js';
const context = { catalog: [{ key: 'deadlift', name: 'Deadlift', cardio: false }], activeWorkout: { remaining: [] } };
const turns = [{ role: 'user', text: 'add deadlift' }];
const checkpoint = 'tinker://test-run:train:0/sampler_weights/workout-v1';
function setup(t: any) {
  const originalFetch = globalThis.fetch;
  const env = { ...process.env };
  for (const key of ['TINKER_API_KEY','TINKER_MODEL','TINKER_TRAINER_MODEL','TINKER_REQUIRE_FINE_TUNED','GEMINI_API_KEY','GENERAL_AI_MODEL','AVATAR_MODEL']) delete process.env[key];
  t.after(() => { globalThis.fetch = originalFetch; process.env = env; });
}
test('workout edits use configured Tinker checkpoint with the named tool and no general AI key', async t => {
  setup(t); process.env.TINKER_API_KEY = 'test-training-key'; process.env.TINKER_TRAINER_MODEL = checkpoint;
  process.env.TINKER_REQUIRE_FINE_TUNED = 'true'; process.env.TINKER_MODEL = 'legacy-model';
  const output = { reply: 'Plan', todoAction: 'replace', todos: [{ exerciseKey: 'deadlift', sets: 3, repsLow: 8, repsHigh: 12, restSeconds: 90 }], schedule: [] };
  globalThis.fetch = async (url, init) => {
    assert.equal(new URL(String(url)).hostname, 'tinker.thinkingmachines.dev');
    const headers = new Headers(init?.headers); assert.equal(headers.get('x-api-key'),'test-training-key'); assert.equal(headers.get('x-goog-api-key'),null);
    const body = JSON.parse(String(init?.body)); assert.equal(body.model,checkpoint); assert.equal(body.tool_choice.name,'reply_to_lifter');
    assert.match(body.system,/Never mark sets complete/);
    return Response.json({ content: [{ type: 'tool_use', name: 'reply_to_lifter', input: output }] });
  };
  assert.deepEqual(await trainerPlanReply(turns,context),output);
});
test('fine-tuned requirement fails closed; legacy base model remains an explicit migration option', async t => {
  setup(t); process.env.TINKER_MODEL = 'legacy-model'; assert.equal(trainerModel(),'legacy-model');
  process.env.TINKER_REQUIRE_FINE_TUNED = 'true'; assert.throws(trainerModel,/trained workout model/);
  process.env.TINKER_TRAINER_MODEL = 'tinker://run/weights/checkpoint'; assert.throws(trainerModel,/trained workout model/);
  process.env.TINKER_TRAINER_MODEL = checkpoint; assert.equal(trainerModel(),checkpoint);
});
test('social drafts use Gemini and include only shared profile fields', async t => {
  setup(t); process.env.GEMINI_API_KEY = 'test-general-key'; process.env.TINKER_API_KEY = 'test-training-key';
  process.env.GENERAL_AI_MODEL = 'configured-text-model';
  globalThis.fetch = async (url,init) => {
    assert.equal(String(url),'https://generativelanguage.googleapis.com/v1beta/models/configured-text-model:generateContent');
    const headers=new Headers(init?.headers);assert.equal(headers.get('x-goog-api-key'),'test-general-key');assert.equal(headers.get('x-api-key'),null);
    const body=JSON.parse(String(init?.body)); const data=JSON.parse(body.contents[0].parts[0].text);
    assert.deepEqual(data,{name:'Lifter',interests:['lifting'],otherMember:{name:'Peer',interests:['running']}});
    assert.doesNotMatch(String(init?.body),/PRIVATE_DATA/);
    return Response.json({candidates:[{content:{parts:[{text:'Hi, nice to meet you!'}]}}]});
  };
  const reply=await companionReply([{role:'user',text:'PRIVATE_DATA'}],{name:'Lifter',interests:['lifting'],workout:'PRIVATE_DATA',weight:'PRIVATE_DATA',otherMember:{name:'Peer',interests:['running'],history:'PRIVATE_DATA'}},true);
  assert.equal(reply,'Hi, nice to meet you!');
});
test('missing generic key never uses Tinker or a cloud service account for images or drafts', async t => {
  setup(t);process.env.TINKER_API_KEY='test-training-key';process.env.GOOGLE_CLOUD_PROJECT='test-project';
  let calls=0;globalThis.fetch=async()=>{calls++;throw Error('Unexpected request');};
  await assert.rejects(companionReply(turns,{},true),/separate Gemini API key/);
  await assert.rejects(generateAvatar('Game head'),/Preset avatars still work/);
  assert.equal(calls,0);
});
test('avatar preview uses separate Gemini key; generation failure returns no replacement appearance', async t => {
  setup(t);process.env.GEMINI_API_KEY='test-general-key';process.env.AVATAR_MODEL='configured-image-model';
  const bytes=Buffer.concat([Buffer.from([137,80,78,71,13,10,26,10]),Buffer.alloc(40)]);
  const selfie={data:bytes.toString('base64'),mimeType:'image/png'};
  globalThis.fetch=async(url,init)=>{
    assert.match(String(url),/generativelanguage.googleapis.com.*configured-image-model/);
    assert.equal(new Headers(init?.headers).get('x-goog-api-key'),'test-general-key');
    assert.deepEqual(JSON.parse(String(init?.body)).contents[0].parts[1].inlineData,selfie);
    return Response.json({candidates:[{content:{parts:[{inlineData:selfie}]}}]});
  };
  assert.deepEqual(await generateAvatar('friendly',selfie),selfie);
  let attempts=0;globalThis.fetch=async()=>{attempts++;return new Response('',{status:503});};
  await assert.rejects(generateAvatar('friendly'),/external service/);assert.equal(attempts,1);
});
test('trainer outage does not fall back to generic AI', async t => {
  setup(t);process.env.TINKER_API_KEY='test-training-key';process.env.GEMINI_API_KEY='test-general-key';
  let calls=0;globalThis.fetch=async(url)=>{calls++;assert.equal(new URL(String(url)).hostname,'tinker.thinkingmachines.dev');return new Response('',{status:429});};
  await assert.rejects(trainerPlanReply(turns,context),/Provider is busy/);assert.equal(calls,1);
});
test('missing required tool output gets one charged repair preserving history and latest intent', async t => {
  setup(t); process.env.TINKER_API_KEY = 'test-training-key';
  const messages = [{ role: 'user', text: 'Add deadlift' }, { role: 'assistant', text: 'Updated the remaining list.' },
    { role: 'user', text: 'Hello, do not change anything.' }];
  let calls = 0, charges = 0;
  globalThis.fetch = async (_url, init) => {
    const body = JSON.parse(String(init?.body)); calls++;
    if (calls === 1) {
      assert.equal(body.messages.length, 3);
      return Response.json({ error: { type: 'invalid_request_error', message: 'model returned no tool call when tool_choice required one' } }, { status: 422 });
    }
    assert.deepEqual(body.messages, [{ role: 'user', content: messages[2].text }]);
    assert.match(body.system, /conversationHistory/); assert.match(body.system, /Updated the remaining list/);
    assert.equal(body.tool_choice.name, 'reply_to_lifter');
    return Response.json({ content: [{ type: 'tool_use', name: 'reply_to_lifter', input: { reply: 'Hello!', todoAction: 'keep', todos: null, schedule: [] } }] });
  };
  const reply = await validatedTrainerReply(new Set(['deadlift']), repair => trainerPlanReply(messages, context, repair), async () => { charges++; });
  assert.deepEqual(reply, { reply: 'Hello!', todos: null, schedule: [] });
  assert.equal(calls, 2); assert.equal(charges, 2);
});
test('unrelated provider 422 errors are not retried as model-format errors', async t => {
  setup(t); process.env.TINKER_API_KEY = 'test-training-key';
  let calls = 0;
  globalThis.fetch = async () => { calls++; return Response.json({ error: { type: 'invalid_request_error', message: 'Unsupported model configuration' } }, { status: 422 }); };
  await assert.rejects(validatedTrainerReply(new Set(['deadlift']), repair => trainerPlanReply(turns, context, repair), async () => {}), /external service/);
  assert.equal(calls, 1);
});
