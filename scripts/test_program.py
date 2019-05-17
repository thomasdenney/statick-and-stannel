#!/usr/bin/env python3

import send_utils
import argparse, sys
from pathlib import Path

_, _, _, default_cells = send_utils.defaults()

parser = argparse.ArgumentParser(description="Test programs in the simulator and on FGPA")
parser.add_argument("-p", "--port", default=None, help="The port the FPGA is on. Leave blank for auto.")
parser.add_argument("-b", "--baudrate", default=115200, type=int, help="Baud rate (Hz)")
parser.add_argument("-t", "--timeout", default=2.0, type=float, help="Max timeout (s) for response")
parser.add_argument("-c", "--cells", default=default_cells, type=int, help="Number of cells (default is {})".format(default_cells))
parser.add_argument("path", default=None, nargs='?', type=str, help="The source for the test file")
args = parser.parse_args()

if not args.port:
    args.port = send_utils.auto_path()

if not Path(args.port).exists():
    print("[DEBUG]\t\t{} is not a known path".format(args.port))
    sys.exit(1)

sim_res = send_utils.simulate(args.path, args.cells)
stack = send_utils.expected_stacks(args.path)

# Only check as many cells as there are *provided* stacks
exit_code = 0
for i in range(len(stack)):
    if not sim_res.check_stack(i, stack[i]):
        exit_code = 1

binary = send_utils.compile(args.path)
res = send_utils.send_program_bytes(binary, args.port, args.baudrate, args.timeout, args.cells)

if res.memory_cells != sim_res.memory_cells:
    exit_code = 1
sys.exit(exit_code)
