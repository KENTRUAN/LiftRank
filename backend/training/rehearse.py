"""Run additional iOS-shaped checks, sharing the completed pilot's remaining budget."""
import argparse,asyncio,json
from datetime import datetime,timezone
from pathlib import Path
from dotenv import load_dotenv
from run import ROOT,Budget,evaluate,RATES_CHECKED_ON
async def main(name):
 out=ROOT/'runs'/name
 if RATES_CHECKED_ON!=datetime.now(timezone.utc).date().isoformat():raise ValueError('Recheck current rates before paid evaluation')
 if json.loads((out/'plan.json').read_text())['balance_date']!=datetime.now(timezone.utc).date().isoformat():raise ValueError('Recheck available credit before evaluating on a later day')
 if (out/'rehearsal.json').exists():raise ValueError('Rehearsal already submitted; do not rerun silently')
 if not json.loads((out/'decision.json').read_text())['eligible_for_app_rehearsal']:raise ValueError('Candidate failed the initial benchmark')
 checkpoint=json.loads((out/'checkpoint.json').read_text())['model']
 load_dotenv(ROOT.parent/'.env')
 cases=[json.loads(x) for x in (ROOT/'rehearsal.jsonl').read_text().splitlines()]
 budget=Budget.resume(out/'budget.json')
 result=await evaluate(checkpoint,'rehearsal',cases,budget,out,ROOT/'rehearsal.jsonl')
 if result['passed']!=result['total']:raise RuntimeError('Do not promote this candidate: app-context rehearsal failed')
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('run');asyncio.run(main(p.parse_args().run))
