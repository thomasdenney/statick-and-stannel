#!/usr/local/bin/python3
import random
for i in range(0, 256):
  print("{:04X}".format(random.randint(0, 2 ** 16)))