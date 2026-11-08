import { APIError, text } from './core.js';
import { cleanTrainerReply, trainerResponseSchema } from './trainer.js';

export function trainingProgramSchema(keys: string[]) {
  const integer = (minimum: number, maximum: number) => ({ type: 'integer', minimum, maximum });
  const items = trainerResponseSchema(keys).properties.schedule.items.properties.items;
  return { anyOf: [{ type: 'null' }, { type: 'object', additionalProperties: false,
    properties: {
      startDayOffset: integer(0, 27), weeks: integer(1, 4), restDayTitle: { type: 'string', minLength: 1, maxLength: 100 },
      sessions: { type: 'array', minItems: 1, maxItems: 7, items: { type: 'object', additionalProperties: false,
        properties: { dayOfWeek: integer(0, 6), title: { type: 'string', minLength: 1, maxLength: 100 }, items: { ...items, minItems: 1 } }, required: ['dayOfWeek', 'title', 'items'] } },
      progression: { type: 'array', minItems: 1, maxItems: 4, items: { type: 'object', additionalProperties: false,
        properties: { weekOffset: integer(0, 3), setsDelta: integer(-2, 2), repsDelta: integer(-5, 5) }, required: ['weekOffset', 'setsDelta', 'repsDelta'] } },
    }, required: ['startDayOffset', 'weeks', 'restDayTitle', 'sessions', 'progression'] }] };
}

/** Expand AI-designed sessions consistently; never silently shorten later weeks. */
export function expandTrainingProgram(program: any, catalog: Set<string>) {
  const fail = (): never => { throw new APIError(502, 'Return a complete valid program with unique session days and one progression entry per week.'); };
  const int = (value: any, low: number, high: number) => Number.isInteger(value) && value >= low && value <= high;
  if (!program || !int(program.startDayOffset, 0, 27) || !int(program.weeks, 1, 4) || program.startDayOffset + program.weeks * 7 > 28 ||
      !Array.isArray(program.sessions) || !program.sessions.length || program.sessions.length > 7 ||
      !Array.isArray(program.progression) || program.progression.length !== program.weeks) fail();
  const rest = text(program.restDayTitle, 100);
  const sessions = new Map<number, any>(), progression = new Map<number, any>();
  for (const session of program.sessions) {
    if (!session || !int(session.dayOfWeek, 0, 6) || sessions.has(session.dayOfWeek) || !Array.isArray(session.items) || !session.items.length) fail();
    const valid = cleanTrainerReply({ reply: 'Session', todoAction: 'keep', todos: null,
      schedule: [{ dayOffset: session.dayOfWeek, title: session.title, remove: false, items: session.items }] }, catalog).schedule[0];
    sessions.set(session.dayOfWeek, valid);
  }
  for (const step of program.progression) {
    if (!step || !int(step.weekOffset, 0, program.weeks - 1) || progression.has(step.weekOffset) || !int(step.setsDelta, -2, 2) || !int(step.repsDelta, -5, 5)) fail();
    progression.set(step.weekOffset, step);
  }
  const schedule = Array.from({ length: program.weeks * 7 }, (_, index) => {
    const session = sessions.get(index % 7), step = progression.get(Math.floor(index / 7))!;
    return { dayOffset: program.startDayOffset + index, title: session?.title ?? rest, remove: false,
      items: (session?.items ?? []).map((item: any) => ({ ...item,
        sets: item.sets + step.setsDelta, repsLow: item.repsLow + step.repsDelta, repsHigh: item.repsHigh + step.repsDelta })) };
  });
  return cleanTrainerReply({ reply: 'Program', todoAction: 'keep', todos: null, schedule }, catalog).schedule;
}
