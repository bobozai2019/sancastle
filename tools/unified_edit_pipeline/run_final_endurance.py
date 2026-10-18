"""Long observer timeout only; product timing/capacities remain unchanged."""
import run_display as runner
runner.CASES={'endurance':('unified_edit_final_endurance_probe.gd','main',True)}
runner.EXTRA_PINS=['tools/unified_edit_pipeline/run_final_endurance.py','tests/integration/unified_edit_final_endurance_probe.gd']
original_run=runner.subprocess.run
def long_observer(command,*args,**kwargs):
    command=list(command)
    command[command.index('--quit-after')+1]='144000'
    kwargs['timeout']=2400
    return original_run(command,*args,**kwargs)
runner.subprocess.run=long_observer
if __name__=='__main__':runner.main()
