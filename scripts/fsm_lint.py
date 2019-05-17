#!/usr/bin/env python3
import re, sys

status = 0
messages = []

def err(src, line_no, msg):
    global status
    global messages
    status = 1
    messages.append((src, line_no, "\033[;31mERROR:\033[0;0m {}:{}: {}".format(src, line_no+1, msg)))

def warn(src, line_no, msg):
    global status
    global messages
    status = 1
    messages.append((src, line_no, "\033[;33mWARNING:\033[0;0m {}:{}: {}".format(src, line_no+1, msg)))

# This linter is not especially complex and only based on a simple convention that I've been using:
# a register named "r..." should only be updated via <= in an @always (posedge clk) block and a
# register named "w..." should be treated as a wire and only updated via = in an @always (*) block.
# This linter should be used in conjunction with Verilator, which will verify assignments are done
# correctly; this linter just checks names. It also doesn't bother doing any advanced parsing; it
# literally just assumes that the @always (*) block is at the end of the module, which itself is at
# the end of the file.
def lint_file(src):
    with open(src, "r") as f:
        wires = set()
        wires_assigned_always = set()
        wire_pattern = re.compile('(reg|wire)[\\s]+((\\[|\\]|-|:|[A-z0-9])*[\\s]+)?(w([A-Z][A-z0-9]+))')
        assign_pattern = re.compile('((r|w)([A-Z][A-z0-9]+))[\\s]+?(<=|=)')
        clock_pattern = re.compile("always @\\(posedge clk\\)")
        always_pattern = re.compile("always @\\(\\*\\)")
        in_clk_block = False
        in_always_block = False
        for line_no, line in enumerate(f):
            m = wire_pattern.match(line.strip())
            m2 = assign_pattern.match(line.strip())
            in_clk_block = in_clk_block or (clock_pattern.match(line.strip()) is not None)
            in_always_block = in_always_block or (always_pattern.match(line.strip()) is not None)
            if line.strip().startswith("case"):
                # I only care about assignments that are always made
                break
            if m is not None:
                wire_name = m.group(4)
                if m.group(1) == "wire":
                    err(src, line_no, "{} is declared as a wire, not a register".format(wire_name))
                wires.add((wire_name, line_no))
            elif m2 is not None:
                wire_name = m2.group(1)
                if m2.group(2) == "r" and m2.group(4) != "<=":
                    err(src, line_no, "{} is not assigned with <=".format(wire_name))
                elif m2.group(2) == "w" and m2.group(4) != "=":
                    err(src, line_no, "{} is not assigned with =".format(wire_name))

                if m2.group(2) == "w" and not in_always_block:
                    err(src, line_no, "Assignment of {} outside of @always(*)".format(wire_name))
                elif m2.group(2) == "w" and in_always_block:
                    wires_assigned_always.add(wire_name)
                elif m2.group(2) == "r" and in_always_block:
                    err(src, line_no, "Assignment of {} in @always(*)".format(wire_name))

        for (wire, line_no) in wires:
            if wire not in wires_assigned_always:
                warn(src, line_no, "{} is not always assigned at the beginning of the always @(*) block".format(wire))

for src in sys.argv[1:]:
    lint_file(src)

for (src, line_no, line) in sorted(messages):
    print(line)

sys.exit(status)
