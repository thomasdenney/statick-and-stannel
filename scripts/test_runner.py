#!/usr/local/bin/python3
import sys

exit_code = 0;

for line in sys.stdin:
    if line.startswith("ERROR: "):
        sys.stdout.write("\033[;31mERROR: \033[0;0m{}".format(line[len("ERROR: "):]))
        exit_code = 1
    else:
        sys.stdout.write(line)

sys.exit(exit_code)
