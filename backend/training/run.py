"""Bounded synthetic SFT pilot. No paid requests without --execute and a verified balance."""
import argparse, asyncio, hashlib, json, math, os, random, subprocess
from datetime import datetime, timezone
from pathlib import Path
import httpx
from dotenv import load_dotenv
import tinker
from tinker_cookbook.renderers import get_renderer
from tinker_cookbook.tokenizer_utils import get_tokenizer
from tinker_cookbook.supervised.common import datum_from_model_input_weights
ROOT=Path(__file__).resolve().parent
MODEL='thinkingmachines/Inkling'
# Official models.json checked 2026-11-07; USD per 1M tokens. Recheck before a later run.
RATES={'train':5.61,'prefill':1.87,'sample':4.68}
RATES_CHECKED_ON='2026-11-08'
PRICEBOOK={MODEL:RATES,'thinkingmachines/Inkling-Small':{'train':1.73,'prefill':0.58,'sample':1.44}}
URL='https://tinker.thinkingmachines.dev/services/tinker-prod/anthropic/api/v1/messages'
def rows(name):return [json.loads(x) for x in (ROOT/f'{name}.jsonl').read_text().splitlines() if x.strip()]
def prefix(renderer,row):
 q=row['request']; t=q['tools'][0]
 return renderer.create_conversation_prefix_with_tools([{'name':t['name'],'description':t['description'],'parameters':t['input_schema']}],q['system'])+q['messages']
def prepare(renderer,train):
 data=[]
 for row in train:
  messages=prefix(renderer,row)+[{'role':'assistant','content':'','tool_calls':[{'id':'call_plan','type':'function','function':{'name':'reply_to_lifter','arguments':json.dumps(row['target'],ensure_ascii=False)}}]}]
  model_input,weights=renderer.build_supervised_example(messages,effort=0)
  if model_input.length>16000 or weights.sum().item()<=0:raise ValueError('Invalid or oversized training example')
  data.append(datum_from_model_input_weights(model_input,weights,max_length=None))
 return data
class Budget:
 def __init__(self,path,cap):self.path=path;self.cap=cap;self.reserved=0.;self.entries=[]
 @classmethod
 def resume(cls,path):
  saved=json.loads(path.read_text());budget=cls(path,saved['cap_usd'])
  budget.reserved=saved['reserved_usd'];budget.entries=saved['entries']
  if not 0<=budget.reserved<=budget.cap<=20 or not math.isclose(sum(x['reserved_usd'] for x in budget.entries),budget.reserved):
   raise ValueError('Invalid pilot budget ledger')
  return budget
 def reserve(self,kind,usd,**detail):
  if not math.isfinite(usd) or usd<0 or self.reserved+usd>self.cap:raise RuntimeError('Pilot budget reached before submitting request')
  self.reserved+=usd;self.entries.append({'kind':kind,'reserved_usd':usd,**detail})
  self.path.write_text(json.dumps({'cap_usd':self.cap,'reserved_usd':self.reserved,'entries':self.entries},indent=2))
async def evaluate(model,tag,cases,budget,out,score_cases=ROOT/'eval.jsonl',rates=RATES):
 results=[];semaphore=asyncio.Semaphore(2)
 async with httpx.AsyncClient(timeout=90,follow_redirects=False) as client:
  async def one(row):
   async with semaphore:
    q={**row['request'],'model':model}
    # 16k input token allowance (rendered preflight below), max 6k output, 2x margin.
    budget.reserve('evaluation',2*(16000*rates['prefill']+6000*rates['sample'])/1e6,case=row['id'],model=model,response_file=f'{tag}.json')
    try:
     response=await client.post(URL,headers={'x-api-key':os.environ['TINKER_API_KEY'],'anthropic-version':'2023-06-01'},json=q)
     if response.status_code!=200: result={'id':row['id'],'error':f'Provider HTTP {response.status_code}'}
     else: result={'id':row['id'],'data':response.json()}
    except (httpx.HTTPError,ValueError) as exc: result={'id':row['id'],'error':type(exc).__name__}
    results.append(result);(out/f'{tag}.json').write_text(json.dumps(results,indent=2));print(f'{tag}: {row["id"]} received',flush=True)
  await asyncio.gather(*(one(row) for row in cases))
 score=subprocess.check_output(['node',str(ROOT/'score.mjs'),str(out/f'{tag}.json'),str(score_cases)],text=True)
 (out/f'{tag}-score.json').write_text(score);print(score,flush=True)
 return json.loads(score)
async def main(args):
 if not math.isfinite(args.budget) or not 0<args.budget<=20:raise ValueError('This pilot is limited to $20')
 model=args.model;rates=PRICEBOOK[model]
 renderer=get_renderer('tml_v0',get_tokenizer(model));train=rows(args.dataset)
 cases=rows('eval')+rows('rehearsal')+rows('fresh');data=prepare(renderer,train)
 for row in cases:
  if renderer.build_generation_prompt(prefix(renderer,row),effort=0).length>15000:raise ValueError('Evaluation input exceeds reserved token allowance')
 tokens=sum(d.model_input.length for d in data)*args.epochs
 reserved=2*tokens*rates['train']/1e6+len(cases)*2*2*(16000*rates['prefill']+6000*rates['sample'])/1e6
 plan={'model':model,'dataset':args.dataset,'seed':args.seed,'epochs':args.epochs,'examples':len(data),'evaluation_cases':len(cases),'training_tokens':tokens,'estimated_training_usd':tokens*rates['train']/1e6,'worst_case_reservation_usd':reserved,'rates':rates,'checkpoint_ttl_seconds':604800}
 print(json.dumps(plan,indent=2),flush=True)
 if reserved>args.budget:raise ValueError('Preflight exceeds pilot cap')
 if not args.execute:return
 if RATES_CHECKED_ON!=datetime.now(timezone.utc).date().isoformat():raise ValueError('Recheck official rates and update RATES_CHECKED_ON before another paid run')
 if args.verified_balance is None or not math.isfinite(args.verified_balance) or args.budget>min(120,args.verified_balance-1):raise ValueError('Verify current credit balance; keep at least $1 in reserve')
 if args.balance_date!=datetime.now(timezone.utc).date().isoformat():raise ValueError('Balance must be checked on the current UTC date')
 load_dotenv(ROOT.parent/'.env')
 if not os.environ.get('TINKER_API_KEY'):raise ValueError('Missing TINKER_API_KEY')
 out=ROOT/'runs'/args.run
 out.mkdir(parents=True,exist_ok=False) # Never accidentally repeat a paid run in place.
 (out/'plan.json').write_text(json.dumps({**plan,'dataset_sha256':hashlib.sha256((ROOT/f'{args.dataset}.jsonl').read_bytes()).hexdigest(),'verified_balance':args.verified_balance,'balance_date':args.balance_date},indent=2))
 budget=Budget(out/'budget.json',args.budget)
 casefile=out/'evaluation-cases.jsonl';casefile.write_text('\n'.join(json.dumps(c) for c in cases)+'\n')
 (out/'training-examples.jsonl').write_bytes((ROOT/f'{args.dataset}.jsonl').read_bytes())
 base_score=await evaluate(model,'baseline',cases,budget,out,casefile,rates=rates)
 service=tinker.ServiceClient(display_name=f'LiftRank workout pilot {args.run}',user_metadata={'purpose':'synthetic workout edits','pilot_cap_usd':str(args.budget)})
 success=False
 try:
  client=await service.create_lora_training_client(base_model=model,rank=16,seed=args.seed,train_unembed=False)
  for epoch in range(args.epochs):
   order=list(range(len(data)));random.Random(args.seed+epoch).shuffle(order)
   for start in range(0,len(order),8):
    batch=[data[i] for i in order[start:start+8]]
    count=sum(d.model_input.length for d in batch)
    budget.reserve('training',2*count*rates['train']/1e6,epoch=epoch+1,batch=start//8+1,tokens=count)
    # Queue both before waiting so the scheduler can use one clock cycle.
    forward=client.forward_backward(batch,loss_fn='cross_entropy')
    optimize=client.optim_step(tinker.AdamParams(learning_rate=1e-4))
    result=await forward
    await optimize
    print(json.dumps({'epoch':epoch+1,'batch':start//8+1,'metrics':result.metrics,'reserved_usd':budget.reserved}),flush=True)
  state=await client.save_state('workout-v1',ttl_seconds=604800)
  (out/'training-state.json').write_text(json.dumps({'path':state.path}))
  saved=await client.save_weights_for_sampler('workout-v1',ttl_seconds=604800,user_metadata={'purpose':'workout tool edits','synthetic':'true'})
  (out/'checkpoint.json').write_text(json.dumps({'model':saved.path,'console':saved.get_console_url(),'ttl_seconds':604800},indent=2))
  print('Saved checkpoint:',saved.path,flush=True)
  fine_score=await evaluate(saved.path,'finetuned',cases,budget,out,casefile,rates=rates)
  passed=all(x['pass'] for x in fine_score['cases']) and fine_score['passed']>=base_score['passed']
  (out/'decision.json').write_text(json.dumps({'eligible_for_app_rehearsal':passed,'baseline':base_score['passed'],'finetuned':fine_score['passed'],'total':fine_score['total'],'not_a_clinical_or_coaching_quality_evaluation':True},indent=2))
  print('Eligible for app rehearsal:',passed,flush=True);success=True
 finally:await service.close('success' if success else 'errored',detail='LiftRank bounded pilot finished')
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--execute',action='store_true');p.add_argument('--model',choices=list(PRICEBOOK),default='thinkingmachines/Inkling-Small');p.add_argument('--dataset',choices=['train','specialist'],default='specialist');p.add_argument('--seed',type=int,default=91);p.add_argument('--budget',type=float,default=20);p.add_argument('--verified-balance',type=float);p.add_argument('--balance-date');p.add_argument('--epochs',type=int,choices=[1,2],default=2);p.add_argument('--run',default=datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ'))
 asyncio.run(main(p.parse_args()))
