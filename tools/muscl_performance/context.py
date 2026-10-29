"""Explicit task destinations shared by measurement entry points."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]


def add_arguments(parser):
    parser.add_argument('--task-root', type=Path, default=Path('task/muscl_performance_round2'))
    parser.add_argument('--temp-root', type=Path, default=Path('test_output/muscl_performance_round2'))
    parser.add_argument('--baseline-id',help='New immutable baseline epoch; preserves existing archive/reference')


def baseline_paths(args, task):
    epoch = getattr(args,'baseline_id',None)
    if epoch is not None and not re.fullmatch(r'[a-z0-9_]+',epoch):
        raise ValueError('baseline-id must contain only lowercase letters, digits and underscores')
    suffix = '_' + epoch if epoch else ''
    return task/'验收'/('baseline'+suffix), task/('reference'+suffix)


def resolve(args):
    def absolute(path):
        return (ROOT / path).resolve() if not path.is_absolute() else path.resolve()
    return absolute(args.task_root), absolute(args.temp_root)
