import asyncio,json
from datetime import datetime,timezone
from dotenv import load_dotenv
from run import ROOT,RATES_CHECKED_ON,Budget,evaluate,rows
from refine import RATES
async def main():
 if RATES_CHECKED_ON!=datetime.now(timezone.utc).date().isoformat():raise ValueError('Recheck current rates and balance')
 out=ROOT/'runs/workout-small-v2-20261108'
 if not json.loads((out/'decision.json').read_text())['eligible_for_app_rehearsal']:raise ValueError('Initial candidate checks failed')
 if (out/'fresh.json').exists():raise ValueError('Fresh checks already submitted')
 load_dotenv(ROOT.parent/'.env');budget=Budget.resume(out/'budget.json')
 model=json.loads((out/'checkpoint.json').read_text())['model']
 result=await evaluate(model,'fresh',rows('fresh'),budget,out,ROOT/'fresh.jsonl',rates=RATES)
 if result['passed']!=result['total']:raise RuntimeError('Fresh checks failed; do not promote')
if __name__=='__main__':asyncio.run(main())
