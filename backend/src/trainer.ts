import { APIError, text } from './core.js';
export type TrainerItem = { exerciseKey: string; sets: number; repsLow: number; repsHigh: number; restSeconds: number };
export function trainerResponseSchema(keys: string[]) {
  const integer = (minimum: number, maximum: number) => ({ type: 'integer', minimum, maximum });
  const item = { type: 'object', additionalProperties: false,
    properties: { exerciseKey: (keys.length ? { type: 'string', enum: keys } : { type: 'string' }), sets: integer(1, 10), repsLow: integer(1, 1440), repsHigh: integer(1, 1440), restSeconds: integer(0, 600) },
    required: ['exerciseKey', 'sets', 'repsLow', 'repsHigh', 'restSeconds'] };
  return { type: 'object', additionalProperties: false,
    properties: { reply: { type: 'string', minLength: 1, maxLength: 5000 }, todoAction: { type: 'string', enum: ['keep', 'replace', 'clear'] },
      todos: { anyOf: [{ type: 'null' }, { type: 'array', maxItems: 20, items: item }] },
      schedule: { type: 'array', maxItems: 28, items: { type: 'object', additionalProperties: false,
        properties: { dayOffset: integer(0, 27), title: { type: 'string', minLength: 1, maxLength: 100 }, remove: { type: 'boolean' }, items: { type: 'array', maxItems: 20, items: item } },
        required: ['dayOffset', 'title', 'remove', 'items'] } } }, required: ['reply', 'todoAction', 'todos', 'schedule'] };
}
function invalid(detail: string): never { throw new APIError(502, `Trainer response: ${detail}. No changes were applied.`); }
export function cleanTrainerReply(raw: string | unknown, catalog: Set<string>) {
  let result: any = raw;
  if (typeof raw === 'string') {
    try { result = JSON.parse(raw.replace(/^\s*```(?:json)?\s*/, '').replace(/\s*```\s*$/, '')); }
    catch { invalid('invalid JSON'); }
  }
  if (!result || typeof result !== 'object' || Array.isArray(result)) invalid('expected an object');
  const number = (value: unknown, min: number, max: number, field: string) => {
    // Numeric strings are a transport-format variation, not a reason to reject a valid plan.
    const n = typeof value === 'string' && /^\d+(?:\.0+)?$/.test(value.trim()) ? Number(value) : value;
    if (typeof n !== 'number' || !Number.isInteger(n) || n < min || n > max) invalid(`${field} must be an integer from ${min} to ${max}`);
    return n as number;
  };
  const items = (rawItems: any): TrainerItem[] => {
    if (!Array.isArray(rawItems) || rawItems.length > 20) invalid('expected at most 20 exercises');
    const seen = new Set<string>();
    return rawItems.map((item: any) => {
      if (!item || typeof item !== 'object' || !catalog.has(item.exerciseKey) || seen.has(item.exerciseKey)) invalid('unavailable or duplicate exercise key');
      seen.add(item.exerciseKey);
      const low = number(item.repsLow, 1, 1440, 'repsLow');
      return { exerciseKey: item.exerciseKey, sets: number(item.sets, 1, 10, 'sets'), repsLow: low,
        repsHigh: number(item.repsHigh ?? low, low, 1440, 'repsHigh'), restSeconds: number(item.restSeconds, 0, 600, 'restSeconds') };
    });
  };
  if (result.schedule != null && (!Array.isArray(result.schedule) || result.schedule.length > 28)) invalid('expected at most 28 schedule days');
  const schedule = (result.schedule ?? []).map((day: any) => {
    if (!day || typeof day !== 'object') invalid('invalid schedule day');
    return { dayOffset: number(day.dayOffset, 0, 27, 'dayOffset'), title: text(day.title || 'Training', 100),
      remove: day.remove === true, items: day.remove === true ? [] : items(day.items ?? []) };
  });
  if (new Set(schedule.map((d: any) => d.dayOffset)).size !== schedule.length) invalid('duplicate schedule days');
  if (typeof result.reply !== 'string' || !result.reply.trim()) invalid('missing reply');
  if (result.todoAction != null && !['keep', 'replace', 'clear'].includes(result.todoAction)) invalid('invalid todo action');
  if (result.todoAction === 'replace' && !Array.isArray(result.todos)) invalid('replace requires the remaining exercise list');
  if (['keep', 'clear'].includes(result.todoAction) && Array.isArray(result.todos) && result.todos.length) invalid('todo action contradicts supplied exercises');
  const todos = result.todoAction === 'clear' ? [] : result.todoAction === 'keep' || result.todos == null ? null : items(result.todos);
  return { reply: text(result.reply, 5000), todos, schedule };
}

/** At most two attempts; no raw prompts/responses are persisted or logged. */
export async function validatedTrainerReply(catalog: Set<string>, generate: (repair?: string) => Promise<unknown>, charge: () => Promise<void>, policy?: { allowsTodoEditing: boolean }) {
  let repair: string | undefined;
  for (let attempt = 0; attempt < 2; attempt++) {
    await charge();
    const raw = await generate(repair);
    try {
      const result = cleanTrainerReply(raw, catalog);
      if (policy?.allowsTodoEditing === false && result.todos !== null) {
        invalid('this session cannot edit current-workout todos; use todoAction=keep and todos=null, with only explicitly requested schedule edits');
      }
      return result;
    }
    catch (error) {
      if (!(error instanceof APIError)) throw error;
      repair = error.message;
    }
  }
  throw new APIError(502, 'I couldn’t safely apply that plan. Your workout is unchanged. Please try a smaller change.');
}
