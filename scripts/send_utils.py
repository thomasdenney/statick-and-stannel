# Library for running programs locally using the Verilog simulator and deploying
# them to the device (and checking their results). Requires Python >=3.7 for
# type annotations.

from dataclasses import dataclass
from os import listdir
from typing import List
import os, random, re, serial, subprocess, sys, tempfile

def file_bytes(file_name: str) -> bytearray:
    contents = []
    with open(file_name, "rb") as f:
        b = f.read(1)
        while b:
            contents.append(ord(b))
            b = f.read(1)
    return bytearray(contents)

def randomised_data() -> bytearray:
    res = []
    for i in range(0, 512):
        res.append(random.randint(0, 255))
    return bytearray(res)

def join_with_randomised_data(bs: bytearray, rbs: bytearray) -> bytearray:
    while len(bs) != 512:
        bs.append(rbs[len(bs)])
    return bs

def compile(src: str) -> bytearray:
    with tempfile.NamedTemporaryFile() as f:
        compile_res = subprocess.call(["../statick-tools/target/debug/as", "-o", f.name, src])
        if compile_res == 0:
            bs = file_bytes(f.name)
            if len(bs) % 2 == 1:
                bs.append(0x5e) # NOP
            return bs
        else:
            return None

def diff_string(bs, original):
    output = ""
    ndiff = 0
    for i in range(0, min(len(bs), len(original))):
        if bs[i] != original[i]:
            output += "\033[;1m"
            output += "{:02x}".format(bs[i])
            output += "\033[0;0m"
            ndiff += 1
        else:
            output += "{:02x}".format(bs[i])
        if i < min(len(bs), len(original)) - 1:
            output += ":"
    if len(bs) > len(original):
        ndiff += len(bs) - len(original)
        for i in range(len(original), len(bs)):
            output += ":{:02x}".format(bs[i])
    if ndiff > 0:
        output += " ({} bytes different)".format(ndiff)
    return output

@dataclass
class Result:
    memory_cells: List[bytearray]
    cycles: int
    size: int

    def sp(self, cell: int) -> int:
        sp = int(self.memory_cells[cell][0])
        if sp == 0:
            sp = 256
        return sp

    def stack_len(self, cell: int) -> int:
        if self.sp(cell) == 0:
            return 0
        return 256 - self.sp(cell)

    def stack_as_list(self, cell: int) -> List[int]:
        s = []
        for i in range(self.stack_len(cell)):
            s.append(self.stack_peek(cell, i))
        return s

    def stack_peek(self, cell: int, i: int) -> int:
        return (self.memory_cells[cell][(self.sp(cell) + i) * 2] << 8) + self.memory_cells[cell][(self.sp(cell) + i) * 2 + 1]

    def check_stack(self, cell: int, expected: List[int]) -> bool:
        actual = self.stack_as_list(cell)
        if actual != expected:
            print("[STACK {}] Expected {} != Actual {}".format(cell, expected, actual))
            return False
        return True

def simulate(src: str, cells: int = 20):
    bs = compile(src) # Guaranteed to have an even length
    with tempfile.NamedTemporaryFile() as f:
        with open(f.name, "w") as hex_file:
            k = 0
            for i in range(0, len(bs), 2):
                hex_file.write("{:02x}{:02x}\n".format(bs[i], bs[i + 1]))
                k += 1
            while k != 256:
                hex_file.write("xxxx\n")
                k += 1

        d = os.getcwd()
        os.chdir("../stannel")
        cmd = ["make", "-B", "TEST_FILE=" + f.name, "Processor_tb.vcd"]
        res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        output = res.stdout.decode('utf-8')
        os.chdir(d)
        output = output.strip()
        lines = output.splitlines()

        cycles = 0
        cycle_re = re.compile('^Cycles: ([0-9]+)$')
        for line in lines:
            m = cycle_re.match(line)
            if m is not None:
                cycles = int(m.group(1))


        memory_cells = []

        for cell in range(-cells, 0):
            memory_cell = []
            for word in lines[cell].split(":"):
                memory_cell.append(int(word[0:2], 16))
                memory_cell.append(int(word[2:4], 16))
            memory_cells.append(bytearray(memory_cell))
        return Result(memory_cells, cycles, len(bs))


def byte_string(bs: bytearray) -> str:
    return ":".join("{:02x}".format(x) for x in bs)

def auto_path():
    p = re.compile('^cu\\.usbserial(.*?)$')
    matches = [f for f in listdir("/dev/") if p.match(f)]
    matches.sort()
    # This function is conservative; it will only try to find a single match
    if len(matches) > 0:
        return "/dev/" + matches[-1]
    else:
        print("Failed to find a matching path, please reconnect FPGA")
        sys.exit(1)

def read_bytes(ser, k):
    return bytearray(ser.read(k))

def read_int(ser, n=2):
    return int.from_bytes(read_bytes(ser, n), byteorder='big', signed=False)

def send_program_bytes(bs: bytearray, port: str, baudrate: int, timeout: float, cells: int = 20) -> Result:
    with serial.Serial(port, baudrate=baudrate, timeout=timeout) as ser:
        last_address = (len(bs) - 1) // 2
        ser.write(bytearray([ last_address ]))
        ser.write(bs)
        ser.flush()

        memory_cells = []

        for i in range(cells):
            memory_cell = read_bytes(ser, 512)
            memory_cells.append(memory_cell)

        return Result(memory_cells, 0, len(bs))

def expected_stacks(src: str) -> List[int]:
    stacks = []
    with open(src, "r") as f:
        p = re.compile("# Expect:[\\s]*(([0-9]+\\s?)*)")
        for line in f:
            m = p.search(line)
            if m is not None:
                stacks.append([int(x) for x in m.group(1).split()])
    return stacks

def defaults(defaults_path: str = "../stannel/defaults.vh") -> (int, int, int, int):
    default_address_bits = None
    default_data_bits = None
    default_cores = 1
    default_cells = 16
    p_addr = re.compile("ADDRESS_BITS ([0-9]+)")
    p_data = re.compile("DATA_BITS ([0-9]+)")
    p_cores = re.compile("^`define MULTI_CORE ([0-9]+)")
    p_cells = re.compile("^`define CELL_COUNT ([0-9]+)")
    with open(defaults_path, "r") as f:
        for line in f:
            m = p_addr.search(line.strip())
            if m is not None:
                default_address_bits = int(m.group(1))
            m = p_data.search(line.strip())
            if m is not None:
                default_data_bits = int(m.group(1))
            m = p_cores.search(line.strip())
            if m is not None:
                default_cores = int(m.group(1))
            m = p_cells.search(line.strip())
            if m is not None:
                default_cells = int(m.group(1))

    if default_address_bits is None:
        print("[ERROR]\tFailed to read default ADDRESS_BITS from {}".format(defaults_path))
        sys.exit(1)
    if default_data_bits is None:
        print("[ERROR]\tFailed to read default DATA_BITS from {}".format(defaults_path))
        sys.exit(1)

    return (default_address_bits, default_data_bits, default_cores, default_cells)
