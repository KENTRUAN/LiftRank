import json, tempfile, unittest
from pathlib import Path
from run import Budget
from refine import reconcile
class BudgetTests(unittest.TestCase):
 def test_reserves_before_work_and_rejects_over_cap(self):
  with tempfile.TemporaryDirectory() as d:
   b=Budget(Path(d)/'budget.json',2)
   b.reserve('training',1.25)
   with self.assertRaises(RuntimeError):b.reserve('evaluation',.76)
   self.assertEqual(b.reserved,1.25)
   self.assertEqual(json.loads(b.path.read_text())['reserved_usd'],1.25)
   b.reserve('evaluation',.75)
   self.assertEqual(b.reserved,2)
   restored=Budget.resume(b.path)
   with self.assertRaises(RuntimeError):restored.reserve('evaluation',.01)
   self.assertEqual(restored.reserved,2)
 def test_invalid_amounts_do_not_change_budget(self):
  with tempfile.TemporaryDirectory() as d:
   b=Budget(Path(d)/'budget.json',2)
   for value in [-1,float('nan'),float('inf')]:
    with self.assertRaises(RuntimeError):b.reserve('training',value)
   self.assertEqual(b.reserved,0)
 def test_receipt_reconciliation_keeps_unknown_training_and_error_reservations(self):
  with tempfile.TemporaryDirectory() as d:
   folder=Path(d);b=Budget(folder/'budget.json',20)
   b.reserve('evaluation',.116,case='complete',model='thinkingmachines/Inkling')
   b.reserve('evaluation',.116,case='failed',model='thinkingmachines/Inkling')
   b.reserve('training',.3,tokens=100)
   receipt={'id':'complete','data':{'model':'thinkingmachines/Inkling','usage':{'input_tokens':10,'cache_creation_input_tokens':20,'cache_read_input_tokens':300,'output_tokens':40}}}
   (folder/'baseline.json').write_text(json.dumps([receipt,{'id':'failed','error':'Timeout'}]))
   total=reconcile(folder)
   expected=.116+.3+2*(330*1.87+40*4.68)/1e6
   self.assertAlmostEqual(total,expected)
   self.assertAlmostEqual(reconcile(folder),expected)
if __name__=='__main__':unittest.main()
