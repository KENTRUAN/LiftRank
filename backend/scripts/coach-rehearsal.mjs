// Opt-in paid inference against synthetic data. No training or real workout mutation.
// From the repo root: node --env-file=backend/.env backend/scripts/coach-rehearsal.mjs
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import { coachReply } from '../dist/coach.js';
const source = readFileSync(new URL('../../LiftRank/Data/ExerciseSeed.swift', import.meta.url), 'utf8');
const catalog = [...source.matchAll(/add\("([^"]+)", "[^"]+", "([^"]+)"/g)].map(m => ({ key: m[1], name: m[2], cardio: ['running', 'cycling', 'walking', 'rowing', 'stair_climb'].includes(m[1]) }));
const pullup = { exerciseKey: 'pullup', sets: 3, repsLow: 6, repsHigh: 8, restSeconds: 120 };
const context = { catalog, localDate: '2026-11-08', language: 'zh_CN', goals: 'General strength',
  activeWorkout: { activity: 'Strength', allowsTodoEditing: true, remaining: [pullup], completed: [{ exerciseKey: 'pullup', sets: 1 }] },
  schedule: [{ date: '2026-11-08', title: '引体向上', items: [pullup] }] };
let attempts = 0;
// At most five provider calls: <$1.75 conservative reservation at checked Inkling
// rates ($1.87/M input, $4.68/M output), a 64K context and <=12K output tokens.
const planOnly = process.env.LIFTRANK_REHEARSAL_PLAN_ONLY === '1';
const charge = async () => { assert.ok(attempts < (planOnly ? 2 : 5), 'Rehearsal call budget exhausted'); attempts++; };
const report = [];
const question = '帮我制定一个四周的力量训练日程，保持我当前的训练不变。';
const original = structuredClone(context);
const plan = await coachReply([{ role: 'user', text: question }], context, charge);
if (process.env.LIFTRANK_REHEARSAL_REPORT) writeFileSync(process.env.LIFTRANK_REHEARSAL_REPORT, JSON.stringify([{ name: 'Chinese four-week plan', result: plan }], null, 2));
assert.equal(plan.todos, null); assert.deepEqual(context, original);
assert.equal(plan.schedule.length, 28);
assert.equal(new Set(plan.schedule.map(d => d.dayOffset)).size, 28);
const keys = new Set(plan.schedule.flatMap(d => d.items.map(i => i.exerciseKey)));
assert.ok(keys.size >= 6, 'Multi-week program repeats too few exercises');
assert.ok(plan.schedule.some(d => d.items.length === 0), 'Program needs recovery days');
assert.ok(plan.schedule.filter(d => d.items.length).every(d => d.items.length >= 4), 'Strength sessions should contain a full workout, not a single exercise');
for (let week = 0; week < 4; week++) {
  assert.equal(plan.schedule.filter(d => Math.floor(d.dayOffset / 7) === week && d.items.length).length, 3, 'Default program should match three sessions per week');
}
assert.doesNotMatch(plan.reply, /请确认是否保存/, 'An explicit planning request does not need another confirmation');
assert.ok([...keys].some(k => /squat|leg_press|lunge/.test(k)), 'Missing lower-body training');
assert.ok([...keys].some(k => /bench|pushup|ohp/.test(k)), 'Missing push training');
assert.ok([...keys].some(k => /pullup|row|pulldown/.test(k)), 'Missing pull training');
assert.match(plan.reply, /[\u3400-\u9fff]/);
assert.doesNotMatch(plan.reply, /Here is|requested plan|app to validate/i);
assert.ok(plan.schedule.every(d => /[\u3400-\u9fff]/.test(d.title)), 'Plan titles should match Chinese request');
report.push({ name: 'Chinese four-week plan with existing pullups', result: plan, distinctExercises: keys.size });
console.log(`PASS: Chinese 28-day plan, ${keys.size} exercises, recovery days, active workout unchanged`);
if (!planOnly) {
const chat = await coachReply([{ role: 'user', text: '我今天已经做了什么？只回答，不要修改训练。' }], context, charge);
assert.equal(chat.todos, null); assert.deepEqual(chat.schedule, []); assert.match(chat.reply, /引体|pull.?up/i);
report.push({ name: 'Read-only Chinese workout question', result: chat });
console.log('PASS: natural Chinese answer without workout/schedule changes');
const edit = await coachReply([{ role: 'user', text: '添加两组深蹲，每组8次，休息90秒，保留已有的引体向上。' }], context, charge);
assert.deepEqual(edit.schedule, []);
assert.deepEqual(edit.todos.find(i => i.exerciseKey === 'pullup'), pullup);
assert.deepEqual(edit.todos.find(i => i.exerciseKey === 'squat'), { exerciseKey: 'squat', sets: 2, repsLow: 8, repsHigh: 8, restSeconds: 90 });
assert.match(edit.reply, /[\u3400-\u9fff]/); assert.doesNotMatch(edit.reply, /Here is|app to validate/i);
report.push({ name: 'Focused edit routed to specialist', result: edit });
console.log(`PASS: fine-tuned edit preserves existing todos; ${attempts} provider calls total`);
}
if (process.env.LIFTRANK_REHEARSAL_REPORT) writeFileSync(process.env.LIFTRANK_REHEARSAL_REPORT, JSON.stringify(report, null, 2));
