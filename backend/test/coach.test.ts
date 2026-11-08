import test from 'node:test';
import assert from 'node:assert/strict';
import { coachReply } from '../src/coach.js';
import { expandTrainingProgram } from '../src/trainingProgram.js';

const item = (exerciseKey: string) => ({ exerciseKey, sets: 3, repsLow: 8, repsHigh: 12, restSeconds: 90 });
const context = { language: 'zh_CN', localDate: '2026-11-08', catalog: ['pullup', 'squat', 'bench_press'].map(key => ({ key, name: key, cardio: false })),
  activeWorkout: { allowsTodoEditing: true, remaining: [item('pullup')], completed: [{ exerciseKey: 'pullup', sets: 1 }] }, schedule: [] };
const turns = (text: string) => [{ role: 'user', text }];
const action = (workoutInstruction: string | null, schedule: object[] = []) => Response.json({ content: [{ type: 'tool_use', name: 'prepare_training_changes', input: { reply: '已为你准备训练安排。', workoutInstruction, schedule } }] });
function setup(t: any) {
  const fetch = globalThis.fetch, env = { ...process.env };
  process.env.TINKER_API_KEY = 'test-only'; process.env.TINKER_COACH_MODEL = 'thinkingmachines/Inkling';
  process.env.TINKER_TRAINER_MODEL = 'tinker://test/sampler_weights/editor'; process.env.TINKER_REQUIRE_FINE_TUNED = 'true';
  delete process.env.TINKER_COACH_EFFORT;
  t.after(() => { globalThis.fetch = fetch; process.env = env; });
}
test('ordinary coaching uses full model and plain text without forced workout edits', async t => {
  setup(t); let charges = 0;
  globalThis.fetch = async (_url, init) => {
    const body = JSON.parse(String(init?.body));
    assert.equal(body.model, 'thinkingmachines/Inkling'); assert.equal(body.tool_choice.type, 'auto');
    assert.equal(body.thinking, undefined); assert.equal(body.output_config.effort, 'medium');
    return Response.json({ content: [{ type: 'thinking', thinking: 'private reasoning' }, { type: 'text', text: '可以，先告诉我你想改善哪方面的训练。' }] });
  };
  const result = await coachReply(turns('你好'), context, async () => { charges++; });
  assert.equal(result.reply, '可以，先告诉我你想改善哪方面的训练。');
  assert.equal(result.todos, null); assert.deepEqual(result.schedule, []); assert.equal(charges, 1);
});
test('four-week planning stays on full model, keeps active pullups unchanged, and preserves distinct days', async t => {
  setup(t); let calls = 0;
  const before = structuredClone(context);
  const schedule = Array.from({ length: 28 }, (_, dayOffset) => ({ dayOffset, title: `第${dayOffset + 1}天`, remove: false,
    items: dayOffset % 2 ? [] : [item(['squat', 'bench_press', 'pullup'][dayOffset % 3]!)] }));
  globalThis.fetch = async (_url, init) => {
    calls++; const body = JSON.parse(String(init?.body)); assert.equal(body.model, 'thinkingmachines/Inkling');
    assert.match(body.system, /NOT a template to copy/); assert.match(body.system, /language of the latest user message/);
    return action(null, schedule);
  };
  const result = await coachReply(turns('帮我制定一个四周的力量训练日程，保持我当前的训练不变。'), context, async () => {});
  assert.deepEqual(result.schedule, schedule); assert.equal(result.todos, null); assert.equal(calls, 1); assert.deepEqual(context, before);
});
test('only current-list changes invoke fine-tuned editor and keep the full coach language', async t => {
  setup(t); let calls = 0, charges = 0;
  globalThis.fetch = async (_url, init) => {
    const body = JSON.parse(String(init?.body)); calls++;
    if (calls === 1) return action('添加三组深蹲，保留其他待做组数。');
    assert.equal(body.model, process.env.TINKER_TRAINER_MODEL);
    assert.equal(body.messages[0].content, '添加三组深蹲，保留其他待做组数。');
    return Response.json({ content: [{ type: 'tool_use', name: 'reply_to_lifter', input: {
      reply: 'Here is the requested plan for the app to validate', todoAction: 'replace', todos: [item('pullup'), item('squat')], schedule: [],
    } }] });
  };
  const result = await coachReply(turns('帮我加深蹲'), context, async () => { charges++; });
  assert.equal(charges, 2); assert.equal(result.reply, '已为你准备训练安排。'); assert.equal(result.todos?.length, 2);
});
test('compact programs preserve full sessions and fill only the requested weeks', async t => {
  setup(t);
  globalThis.fetch = async () => Response.json({ content: [{ type: 'tool_use', name: 'prepare_training_changes', input: {
    reply: '两周计划', workoutInstruction: null, schedule: [], program: {
      startDayOffset: 14, weeks: 2, restDayTitle: '休息日',
      sessions: [0, 2, 4].map(dayOfWeek => ({ dayOfWeek, title: '全身', items: [item('squat'), item('bench_press'), item('pullup')] })),
      progression: [{ weekOffset: 0, setsDelta: 0, repsDelta: 0 }, { weekOffset: 1, setsDelta: -1, repsDelta: 1 }],
    },
  } }] });
  const result = await coachReply(turns('Plan weeks three and four'), context, async () => {});
  assert.equal(result.schedule.length, 14); assert.equal(result.schedule.filter((d: any) => !d.items.length).length, 8);
  assert.deepEqual(result.schedule.map((d: any) => d.dayOffset), Array.from({ length: 14 }, (_, i) => 14 + i));
  assert.equal(result.schedule[7].items.length, 3); assert.equal(result.schedule[7].items[0].sets, 2);
  assert.equal(result.schedule[7].items[0].repsLow, 9); assert.equal(result.todos, null);
});
test('invalid compact programs never leak a partially validated plan', async t => {
  setup(t); let calls = 0;
  globalThis.fetch = async () => { calls++; return Response.json({ content: [{ type: 'tool_use', name: 'prepare_training_changes', input: {
    reply: 'Bad program', workoutInstruction: null, program: { startDayOffset: 25, weeks: 2, restDayTitle: 'Rest', sessions: [], progression: [] }, schedule: [],
  } }] }); };
  await assert.rejects(coachReply(turns('Plan'), context, async () => {}), /could not prepare/); assert.equal(calls, 2);
});
test('program validation rejects duplicated days, incomplete progression, unknown exercises and invalid expanded sets', () => {
  const program = { startDayOffset: 0, weeks: 2, restDayTitle: 'Rest',
    sessions: [{ dayOfWeek: 0, title: 'Strength', items: [item('squat')] }],
    progression: [{ weekOffset: 0, setsDelta: 0, repsDelta: 0 }, { weekOffset: 1, setsDelta: 0, repsDelta: 1 }] };
  const catalog = new Set(['squat']);
  const invalid = [
    { ...program, sessions: [...program.sessions, ...program.sessions] },
    { ...program, progression: [program.progression[0], program.progression[0]] },
    { ...program, progression: [program.progression[0]] },
    { ...program, sessions: [{ ...program.sessions[0], items: [item('invented')] }] },
    { ...program, sessions: [{ ...program.sessions[0], items: [{ ...item('squat'), sets: 1 }] }], progression: [program.progression[0], { weekOffset: 1, setsDelta: -2, repsDelta: 0 }] },
  ];
  for (const value of invalid) assert.throws(() => expandTrainingProgram(value, catalog));
});
test('specialist cannot overwrite the requested schedule or return a partial mixed edit', async t => {
  setup(t); let calls = 0;
  globalThis.fetch = async () => {
    calls++; if (calls === 1) return action('Add squat');
    return Response.json({ content: [{ type: 'tool_use', name: 'reply_to_lifter', input: {
      reply: 'Changed', todoAction: 'replace', todos: [item('squat')], schedule: [{ dayOffset: 0, title: 'Unexpected', remove: false, items: [] }],
    } }] });
  };
  await assert.rejects(coachReply(turns('Add squat'), context, async () => {}), /couldn’t safely apply/);
  assert.equal(calls, 3);
});
test('read-only greetings have no tools and reject any provider edit', async t => {
  setup(t); let calls = 0;
  globalThis.fetch = async (_url, init) => {
    calls++; const body = JSON.parse(String(init?.body)); assert.equal(body.tools, undefined);
    return action('Add squat');
  };
  await assert.rejects(coachReply(turns('Welcome'), context, async () => {}, true), /could not prepare/);
  assert.equal(calls, 2);
});
test('cardio and absent sessions never invoke current-workout editor', async t => {
  setup(t); let calls = 0;
  globalThis.fetch = async (_url, init) => {
    calls++; assert.equal(JSON.parse(String(init?.body)).model, 'thinkingmachines/Inkling'); return action('Add squat');
  };
  for (const activeWorkout of [null, { allowsTodoEditing: false }]) {
    await assert.rejects(coachReply(turns('Add squat'), { ...context, activeWorkout }, async () => {}), /could not prepare/);
  }
  assert.equal(calls, 4);
});
test('quota rejection and provider outage do not invoke another model', async t => {
  setup(t); let calls = 0;
  globalThis.fetch = async () => { calls++; return new Response('', { status: 503 }); };
  await assert.rejects(coachReply(turns('Hi'), context, async () => { throw Error('Quota reached'); }), /Quota/);
  assert.equal(calls, 0);
  await assert.rejects(coachReply(turns('Hi'), context, async () => {}), /external service/); assert.equal(calls, 1);
});
test('tool syntax printed as chat is repaired, never shown as a false successful plan', async t => {
  setup(t); let calls = 0;
  globalThis.fetch = async (_url, init) => {
    calls++; if (calls === 1) return Response.json({ content: [{ type: 'text', text: 'prepare_training_changes{"program":{}}' }] });
    const body = JSON.parse(String(init?.body)); assert.equal(body.tool_choice.name, 'prepare_training_changes');
    return action(null, [{ dayOffset: 0, title: '训练', remove: false, items: [item('squat')] }]);
  };
  const result = await coachReply(turns('安排今天'), context, async () => {});
  assert.equal(calls, 2); assert.equal(result.schedule.length, 1); assert.doesNotMatch(result.reply, /prepare_training_changes/);
});
