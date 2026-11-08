// Opt-in live provider checks using synthetic workout data, never personal records.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { trainerPlanReply } from '../dist/providers.js';
import { validatedTrainerReply } from '../dist/trainer.js';
const source = readFileSync(new URL('../../LiftRank/Data/ExerciseSeed.swift', import.meta.url), 'utf8');
const catalog = [...source.matchAll(/add\("([^"]+)", "[^"]+", "([^"]+)"/g)].map(m => ({ key: m[1], name: m[2], cardio: ['running', 'cycling', 'walking', 'rowing', 'stair_climb'].includes(m[1]) }));
const context = { catalog, localDate: '2026-11-07', activeWorkout: { activity: 'Traditional strength training', remaining: [], completed: [{ exerciseKey: 'bench_press', sets: 2 }] }, schedule: [], goals: 'General fitness' };
const cases = [
 ['ordinary greeting', 'Hi, what can you help me with?', r => assert.equal(r.todos, null)],
 ['workout question', 'What have I already completed today? Please just tell me.', r => { assert.equal(r.todos, null); assert.equal(r.schedule.length, 0); assert.match(r.reply, /2|two/i); }],
 ['add todos', 'Add exactly 2 remaining sets of bench press, 8 reps with 90 seconds rest to my current todos.', r => { assert.equal(r.todos[0].sets, 2); assert.equal(r.todos[0].exerciseKey, 'bench_press'); }],
 ['delete todos', 'Remove all remaining todos from my current workout. Keep completed sets.', r => assert.deepEqual(r.todos, [])],
 ['Chinese weekly plan', '请帮我安排从今天开始的完整七天训练计划，包括休息日。不要修改当前训练。', r => { assert.equal(r.schedule.length, 7); assert.equal(r.todos, null); }],
];
for (const [name, prompt, verify] of cases) {
 let attempts = 0;
 const result = await validatedTrainerReply(new Set(catalog.map(e => e.key)), repair => trainerPlanReply([{ role: 'user', text: prompt }], context, repair), async () => { attempts++; });
 verify(result); if (result.todos !== null) context.activeWorkout.remaining = result.todos; console.log(`PASS: ${name} (${attempts} attempt(s))`);
}
