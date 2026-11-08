// Additional frozen cases using the iOS context shape and conversation history.
import { readFileSync, writeFileSync } from 'node:fs';
import { trainerRequest } from '../dist/providers.js';
const source=readFileSync(new URL('eval.jsonl',import.meta.url),'utf8').trim().split('\n').map(JSON.parse);
function from(id,newID){const c=structuredClone(source.find(x=>x.id===id));c.id=newID;if(c.context.activeWorkout)c.context.activeWorkout.allowsTodoEditing=true;return c;}
const deadlift=from('short-deadlift','history-deadlift');
deadlift.messages=[{role:'user',text:'Plan my squats first.'},{role:'assistant',text:'The remaining squats are ready. Recorded sets are locked.'},{role:'user',text:'add deadlift'}];
const pullup=from('short-pullup','history-pullup');
pullup.messages=[{role:'user',text:'Please add my deadlift sets.'},{role:'assistant',text:'Your remaining deadlifts are ready. Recorded sets are locked.'},{role:'user',text:'add pull up'}];
const cardio=from('cardio-boundary','ios-cardio-flag');
cardio.context.activeWorkout={activity:'Running',allowsTodoEditing:false,remaining:[],completed:[]};
cardio.messages=[{role:'user',text:'add deadlift'}];
const remaining=from('completed-only','ios-completed-counts');
remaining.context.activeWorkout.completed.push({exerciseKey:'deadlift',sets:0});
const greeting=from('greeting','history-no-edit');
greeting.context.activeWorkout.remaining=structuredClone(pullup.context.activeWorkout.remaining);
greeting.messages=[{role:'user',text:'Add deadlift.'},{role:'assistant',text:'Your remaining deadlifts are ready.'},{role:'user',text:'Thanks, just say hello and keep my plan as it is.'}];
const noSession=from('no-session','today-chinese');
noSession.messages=[{role:'user',text:'我还没有开始训练。今天安排引体向上2组，每组6次，休息60秒。'}];
const cases=[deadlift,pullup,cardio,remaining,greeting,noSession];
for(const c of cases)c.request=trainerRequest(c.messages,c.context);
writeFileSync(new URL('rehearsal.jsonl',import.meta.url),cases.map(c=>JSON.stringify(c)).join('\n')+'\n');
console.log(`Prepared ${cases.length} additional rehearsal cases.`);
