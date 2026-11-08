import { readFileSync } from 'node:fs';
import { cleanTrainerReply } from '../dist/trainer.js';
const results=JSON.parse(readFileSync(process.argv[2],'utf8'));
const cases=readFileSync(process.argv[3] || new URL('eval.jsonl',import.meta.url),'utf8').trim().split('\n').map(JSON.parse);
const same=(a,b)=>JSON.stringify(a)===JSON.stringify(b);
const days=x=>x.map(d=>({dayOffset:d.dayOffset,remove:d.remove,items:d.items})).sort((a,b)=>a.dayOffset-b.dayOffset);
const summary=[];
for(const c of cases){
 const response=results.find(r=>r.id===c.id);
 try{
  if(!response?.data || response.data.stop_reason==='max_tokens') throw Error(response?.error||'No complete response');
  const call=response.data.content?.find(x=>x.type==='tool_use'&&x.name==='reply_to_lifter');
  if(!call) throw Error('Missing named tool call');
  const r=cleanTrainerReply(call.input,new Set(c.context.catalog.map(x=>x.key)));
  const expected=cleanTrainerReply(c.target,new Set(c.context.catalog.map(x=>x.key)));
  const rule=c.expectation;
  if(rule.exact && (!same(r.todos,expected.todos)||!same(days(r.schedule),days(expected.schedule)))) throw Error('Incorrect edits');
  if(rule.contains && !same((r.todos||[]).map(t=>t.exerciseKey).sort(),[...rule.contains].sort())) throw Error('Missing or unexpected exercise');
  for(const item of rule.preserve||[])if(!same(r.todos?.find(t=>t.exerciseKey===item.exerciseKey),item))throw Error('Changed unrelated remaining sets');
  if(rule.days && !same(r.schedule.map(d=>d.dayOffset),rule.days))throw Error('Unexpected schedule edit');
  if(rule.scheduled){
    if(r.todos!==null||r.schedule.length!==rule.scheduled.length)throw Error('Unexpected active or scheduled edits');
    for(const expected of rule.scheduled){
      const day=r.schedule.find(d=>d.dayOffset===expected.offset);
      if(!day||day.remove||!same(day.items.map(i=>i.exerciseKey).sort(),[...expected.keys].sort()))throw Error('Incorrect scheduled exercises');
    }
  }
  if(rule.replyIncludes&&!r.reply.toLowerCase().includes(rule.replyIncludes))throw Error('Workout context not used');
  for(const pattern of rule.replyMatches||[])if(!new RegExp(pattern,'i').test(r.reply))throw Error('Supplied workout facts not used');
  summary.push({id:c.id,pass:true});
 }catch(error){summary.push({id:c.id,pass:false,reason:error.message});}
}
console.log(JSON.stringify({passed:summary.filter(x=>x.pass).length,total:summary.length,cases:summary},null,2));
