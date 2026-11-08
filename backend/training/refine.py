"""Small follow-up run after observed failures, under the combined $20 pilot cap."""
import argparse,asyncio,hashlib,json,math,os,random
from datetime import datetime,timezone
from dotenv import load_dotenv
import tinker
from run import ROOT,RATES_CHECKED_ON,Budget,prepare,evaluate,rows
MODEL='thinkingmachines/Inkling-Small'
RATES={'train':1.73,'prefill':0.58,'sample':1.44}
ORIGINAL_RATES={'train':5.61,'prefill':1.87,'sample':4.68}
from tinker_cookbook.renderers import get_renderer
from tinker_cookbook.tokenizer_utils import get_tokenizer

def reconcile(run):
 """Release unused evaluation reservation only when complete token receipts exist.
 Keep the 2x price allowance and charge every input token at the uncached rate.
 Training reservations and missing/error response reservations are never reduced.
 """
 path=run/'budget.json';budget=Budget.resume(path)
 prices=json.loads((run/'plan.json').read_text()).get('rates',ORIGINAL_RATES) if (run/'plan.json').exists() else ORIGINAL_RATES
 for entry in budget.entries:
  if entry['kind']!='evaluation' or 'initial_reserved_usd' in entry:continue
  for filename in ([entry['response_file']] if entry.get('response_file') else ['baseline.json','finetuned.json','rehearsal.json','fresh.json','baseline-final.json','final.json']):
   file=run/filename
   if not file.exists():continue
   response=next((r for r in json.loads(file.read_text()) if r['id']==entry['case'] and r.get('data',{}).get('model')==entry['model']),None)
   if not response:continue
   usage=response['data'].get('usage',{})
   fields=['input_tokens','cache_creation_input_tokens','cache_read_input_tokens','output_tokens']
   if not all(isinstance(usage.get(k),int) and usage[k]>=0 for k in fields):continue
   input_tokens=sum(usage[k] for k in fields[:3]);output_tokens=usage['output_tokens']
   if input_tokens<=0:continue
   cost=2*(input_tokens*prices['prefill']+output_tokens*prices['sample'])/1e6
   if cost>entry['reserved_usd']:raise RuntimeError('Receipt exceeded request reservation')
   entry['initial_reserved_usd']=entry['reserved_usd'];entry['reserved_usd']=cost
   entry['receipt_tokens']={'input':input_tokens,'output':output_tokens};break
 budget.reserved=sum(e['reserved_usd'] for e in budget.entries)
 path.write_text(json.dumps({'cap_usd':budget.cap,'reserved_usd':budget.reserved,'entries':budget.entries},indent=2))
 return budget.reserved

async def main(execute):
 if RATES_CHECKED_ON!=datetime.now(timezone.utc).date().isoformat():raise ValueError('Recheck rates and credit on a later day')
 parent=ROOT/'runs/workout-v1-pipelined-20261108'
 previous=[ROOT/'runs/workout-v1-20261108',parent]
 train=rows('train')+rows('corrections');renderer=get_renderer('tml_v0',get_tokenizer(MODEL));data=prepare(renderer,train)
 total_tokens=sum(d.model_input.length for d in data)*2
 # Reconciliation uses recorded receipts, not an assumption that reserved money was unspent.
 prior=sum(reconcile(p) for p in previous)
 cap=20-prior
 estimate=2*total_tokens*RATES['train']/1e6+46*2*(16000*RATES['prefill']+6000*RATES['sample'])/1e6
 plan={'model':MODEL,'rates':RATES,'examples':len(data),'training_tokens':total_tokens,'estimated_training_usd':total_tokens*RATES['train']/1e6,'prior_reservation_usd':prior,'run_cap_usd':cap,'run_reservation_usd':estimate,'combined_pilot_cap_usd':20}
 print(json.dumps(plan,indent=2),flush=True)
 if estimate>cap:raise ValueError('Follow-up does not fit remaining pilot allowance')
 if not execute:return
 out=ROOT/'runs/workout-small-v2-20261108';out.mkdir(exist_ok=False)
 load_dotenv(ROOT.parent/'.env');budget=Budget(out/'budget.json',cap)
 (out/'plan.json').write_text(json.dumps({**plan,'balance_date':'2026-11-08','dataset_sha256':hashlib.sha256(((ROOT/'train.jsonl').read_bytes()+(ROOT/'corrections.jsonl').read_bytes())).hexdigest()},indent=2))
 for name in ['train.jsonl','corrections.jsonl','eval.jsonl','rehearsal.jsonl']:(out/name).write_bytes((ROOT/name).read_bytes())
 baseline=await evaluate(MODEL,'baseline',rows('eval'),budget,out,rates=RATES)
 service=tinker.ServiceClient(display_name='LiftRank workout specialist v2',user_metadata={'combined_pilot_cap_usd':'20','data':'synthetic only'})
 success=False
 try:
  client=await service.create_lora_training_client(base_model=MODEL,rank=16,seed=91,train_unembed=False)
  for epoch in range(2):
   order=list(range(len(data)));random.Random(91+epoch).shuffle(order)
   for offset in range(0,len(order),8):
    batch=[data[i] for i in order[offset:offset+8]];tokens=sum(d.model_input.length for d in batch)
    budget.reserve('training',2*tokens*RATES['train']/1e6,tokens=tokens,epoch=epoch+1,batch=offset//8+1)
    forward=client.forward_backward(batch,loss_fn='cross_entropy');step=client.optim_step(tinker.AdamParams(learning_rate=1e-4))
    result=await forward;await step
    print(json.dumps({'epoch':epoch+1,'batch':offset//8+1,'loss':result.metrics.get('loss:sum'),'reserved_usd':budget.reserved}),flush=True)
  state=await client.save_state('workout-v2',ttl_seconds=604800)
  (out/'training-state.json').write_text(json.dumps({'path':state.path}))
  saved=await client.save_weights_for_sampler('workout-v2',ttl_seconds=604800,user_metadata={'synthetic':'true','focus':'cardio and latest-user-message boundaries'})
  (out/'checkpoint.json').write_text(json.dumps({'model':saved.path,'console':saved.get_console_url(),'ttl_seconds':604800},indent=2))
  main_score=await evaluate(saved.path,'finetuned',rows('eval'),budget,out,rates=RATES)
  rehearsal=await evaluate(saved.path,'rehearsal',rows('rehearsal'),budget,out,ROOT/'rehearsal.jsonl',rates=RATES)
  eligible=main_score['passed']==20 and rehearsal['passed']==6
  (out/'decision.json').write_text(json.dumps({'eligible_for_app_rehearsal':eligible,'baseline':baseline['passed'],'primary':main_score['passed'],'rehearsal':rehearsal['passed'],'total':26},indent=2))
  print('Eligible for app rehearsal:',eligible,flush=True);success=True
 finally:await service.close('success' if success else 'errored',detail='Bounded refinement finished')
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--execute',action='store_true');asyncio.run(main(p.parse_args().execute))
