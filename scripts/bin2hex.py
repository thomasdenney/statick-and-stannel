#!/usr/local/bin/python3
import sys

with open(sys.argv[1], "rb") as f:
    data = f.read()
    state = 0
    for b in data:
        sys.stdout.write("{:02x}".format(b))
        if state == 1:
            sys.stdout.write("\n")
        state = (state + 1) % 2
    for i in range(len(data), 512):
        sys.stdout.write("{:02x}".format(i % 256))
        if state == 1:
            sys.stdout.write("\n")
        state = (state + 1) % 2