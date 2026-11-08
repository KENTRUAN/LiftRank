import { readFileSync,writeFileSync } from 'node:fs';
import { trainerRequest } from '../dist/providers.js';
import { cleanTrainerReply } from '../dist/trainer.js';
const original=readFileSync(new URL('train.jsonl',import.meta.url),'utf8').trim().split('\n').map(JSON.parse);
const base=structuredClone(original[0].context);
const item={exerciseKey:'deadlift',sets:2,repsLow:6,repsHigh:6,restSeconds:90};
const keep={reply:'I can help with training guidance. Your current workout list stays unchanged.',todoAction:'keep',todos:null,schedule:[]};
const result=[];
function add(id,messages,context,target){
 cleanTrainerReply(target,new Set(context.catalog.map(x=>x.key)));
 result.push({id,messages,context,target,request:trainerRequest(messages,context)});
}
const names=['Deadlift','Pull-Up','Bench Press','Squat'];
for(const activity of ['Running','Walking','Cycling','Rowing','Elliptical']){
 for(const name of names){
  const c={...base,activeWorkout:{activity,allowsTodoEditing:false,remaining:[],completed:[]}};
  add(`cardio-${activity}-${name}`,[{role:'user',text:`Put ${name} on the exercise list for this session.`}],c,{...keep,reply:'This cardio session uses its timer. Strength sets need a separate strength session; I will leave this session unchanged.'});
 }
}
const replies=['Thanks coach.','Good morning, no edits please.','Just tell me I can take a break.','What is on my remaining list?','Say hi without making changes.','谢谢，先不要改训练。','Explain what resting between sets does.','Leave everything exactly as it is.'];
for(const [i,text] of replies.entries())for(const n of [0,1]){
 const c={...base,activeWorkout:{activity:'Traditional strength training',allowsTodoEditing:true,remaining:[{...item,sets:2+n}],completed:[{exerciseKey:'bench_press',sets:2}]}};
 const messages=[{role:'user',text:'Add deadlifts to my list.'},{role:'assistant',text:'The remaining deadlift sets are ready for you. Recorded sets are locked.'},{role:'user',text}];
 add(`history-${i}-${n}`,messages,c,{...keep,reply:i===3?'Your remaining list has deadlifts. No changes are requested.':'Happy to help with your workout. I will keep your list unchanged.'});
}
for(const activity of ['Running','Cycling','Rowing','Walking']){
 const c={...base,activeWorkout:{activity,allowsTodoEditing:false,remaining:[],completed:[]}};
 add(`cardio-future-${activity}`,[{role:'user',text:'Keep this cardio session unchanged and plan 2 sets of deadlifts, 6 reps and 90s rest for tomorrow.'}],c,{...keep,reply:'Here is a separate plan for tomorrow.',schedule:[{dayOffset:1,title:'Strength',remove:false,items:[item]}]});
}
// Replay varied successful edits to reduce forgetting. No held-out prompts or responses are training labels.
for(const c of original.filter((_,i)=>i%8===0).slice(0,20))result.push(c);
writeFileSync(new URL('corrections.jsonl',import.meta.url),result.map(x=>JSON.stringify(x)).join('\n')+'\n');
writeFileSync(new URL('specialist.jsonl',import.meta.url),original.concat(result).map(x=>JSON.stringify(x)).join('\n')+'\n');
console.log(`Prepared ${result.length} correction/replay examples; ${original.length+result.length} specialist rows.`);
