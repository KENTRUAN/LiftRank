"""Final regression after clarifying the short-command default policy; never trains."""
import argparse,asyncio,json,re
from datetime import datetime,timezone
from dotenv import load_dotenv
from run import ROOT,RATES_CHECKED_ON,Budget,evaluate,rows
from refine import MODEL,RATES,reconcile
async def main(tag):
 if not re.fullmatch(r"[a-z0-9-]+",tag):raise ValueError("Invalid run tag")
 if RATES_CHECKED_ON!=datetime.now(timezone.utc).date().isoformat():raise ValueError('Recheck current rates and balance')
 out=ROOT/'runs/workout-small-v2-20261108'
 if (out/f'{tag}.json').exists():raise ValueError('Final checks already submitted')
 reconcile(out);budget=Budget.resume(out/'budget.json');load_dotenv(ROOT.parent/'.env')
 cases=rows('eval')+rows('rehearsal')+rows('fresh')
 casefile=out/f'{tag}-cases.jsonl';casefile.write_text('\n'.join(json.dumps(c) for c in cases)+'\n')
 model=json.loads((out/'checkpoint.json').read_text())['model']
 baseline=await evaluate(MODEL,f'baseline-{tag}',rows('eval'),budget,out,rates=RATES)
 result=await evaluate(model,tag,cases,budget,out,casefile,rates=RATES)
 (out/f'{tag}-decision.json').write_text(json.dumps({'eligible_for_app_rehearsal':result['passed']==33,'final':result['passed'],'total':33,'same_prompt_baseline':baseline['passed'],'baseline_total':20},indent=2))
 if result['passed']!=33:raise RuntimeError('Do not promote: final checks failed')
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--tag',default='final');asyncio.run(main(p.parse_args().tag))
