#!/usr/bin/env python3

import send_utils
import argparse, sys
from pathlib import Path

_, _, _, default_cells = send_utils.defaults()

parser = argparse.ArgumentParser(description="Test programs in the simulator and on FGPA")
parser.add_argument("-c", "--cells", default=default_cells, type=int, help="Number of cells (default is {})".format(default_cells))
parser.add_argument("path", default=None, nargs='?', type=str, help="The source for the test file")
args = parser.parse_args()

sim_res = send_utils.simulate(args.path, args.cells)
stack = send_utils.expected_stacks(args.path)

print("{},{}".format(sim_res.cycles, sim_res.size))

# Only check as many cells as there are *provided* stacks
exit_code = 0
for i in range(len(stack)):
    if not sim_res.check_stack(i, stack[i]):
        exit_code = 1
sys.exit(exit_code)
