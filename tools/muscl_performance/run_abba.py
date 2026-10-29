"""Run independent serial ABBA processes; no evolving in-process recorder swaps."""
import argparse
from pathlib import Path
from baseline import run
from baseline import configure
from context import add_arguments

parser=argparse.ArgumentParser(description=__doc__)
add_arguments(parser)
parser.add_argument('--a',type=Path,required=True)
parser.add_argument('--b',type=Path,required=True)
parser.add_argument('--prefix',required=True)
parser.add_argument('--mode',choices=('scene','cost','flat','input-cost'),default='scene')
parser.add_argument('--case',choices=('wave','shovel'))
parser.add_argument('--scene')
parser.add_argument('--duration',type=float)
parser.add_argument('--telemetry',action='store_true')
parser.add_argument('--engine',type=Path,default=Path('D:/game/steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe'))
args=parser.parse_args()
configure(args)
extra=[]
if args.case:extra.append('--case='+args.case)
if args.scene:extra.append('--scene='+args.scene)
if args.duration is not None:extra.append('--duration='+str(args.duration))
for name,source in [('a1',args.a),('b1',args.b),('b2',args.b),('a2',args.a)]:
    run(args.engine,args.prefix+'_'+args.mode+'_'+name,args.mode,source.resolve(),extra_args=extra,telemetry=args.telemetry)
