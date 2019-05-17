#!/usr/bin/env python3
import argparse, io, re, serial, struct, sys
import send_utils
from pathlib import Path
from os import listdir
from time import sleep

def highlight_string(result: send_utils.Result, cell: int) -> str:
    output = ""
    i = 0
    sp = result.sp(cell)
    for i in range(0, 512):
        col = None
        if i >= sp * 2 and i < sp * 2 + 6:
            col = "\033[32m" # green
        if col is not None:
            output += col
        output += "{:02X}".format(result.memory_cells[cell][i])
        if col is not None:
            output += "\033[0;0m"
        if i != 512 - 1:
            output += ":"
    return output

default_address_bits, default_data_bits, default_cores, default_cells = send_utils.defaults()

parser = argparse.ArgumentParser(description="Deploy assembled binaries to the FPGA")
parser.add_argument("-p", "--port", default=None, help="The port the FPGA is on. Leave blank for auto.")
parser.add_argument("-b", "--baudrate", default=115200, type=int, help="Baud rate (Hz)")
parser.add_argument("-t", "--timeout", default=2.0, type=float, help="Max timeout (s) for response")
parser.add_argument("-r", "--addressBits", default=default_address_bits, type=int, help="Number of bits used for addresses (default is {})".format(default_address_bits))
parser.add_argument("-d", "--dataBits", default=default_data_bits, type=int, help="Number of bits per word (default is {})".format(default_data_bits))
parser.add_argument("-l", "--highlight", action="store_true", help="Highlights the top of stack and program counter")
parser.add_argument("-m", "--memory", action="store_true", help="Checks the memory test")
parser.add_argument("-c", "--cells", default=default_cells, type=int, help="Number of cells to expect (default is {})".format(default_cells))
parser.add_argument("path", default=None, nargs='?', type=str, help="The binary file to deploy to the FPGA")
args = parser.parse_args()

if not args.port:
    args.port = send_utils.auto_path()
if not Path(args.port).exists():
    print("[DEBUG]\t\t{} is not a known path".format(args.port))
    sys.exit(1)

print("[PORT]\t\t{}".format(args.port))
print("[BAUDRATE]\t{} Hz".format(args.baudrate))
print("[TIMEOUT]\t{} s".format(args.timeout))

if args.path is None:
    bs = []
else:
    bs = send_utils.file_bytes(args.path)

ramBytes = 2 ** args.addressBits * args.dataBits // 8

print("[RAM]\t\tWill use {} bit addresses, {} bit words for a total of {} bytes".format(args.addressBits, args.dataBits, ramBytes))

if len(bs) > ramBytes:
    print("[ERROR]\tProgram size {} exceeds maximum allowed size of {}", len(bs), ramBytes)
    sys.exit(1)

NOP = 0x5e
original_length = len(bs)
if len(bs) % 2 == 1:
    bs.append(NOP)

result = send_utils.send_program_bytes(bs, args.port, args.baudrate, args.timeout, args.cells)

for cell in range(0, args.cells):
    if args.highlight:
        strToPrint = highlight_string(result, cell)
    else:
        strToPrint = send_utils.byte_string(result.memory_cells[cell])
    print("[CELL {}]\t{}".format(cell, strToPrint))
