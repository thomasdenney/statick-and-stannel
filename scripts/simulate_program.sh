#!/bin/sh

TEMP1=$(mktemp)
TEMP2=$(mktemp)
AS="../statick-tools/target/debug/as"
$AS -o $TEMP1 $1
xxd -g 4 -p $TEMP1 | sed -E -e "s/..../& /g" | tr ' ' '\n' | sed -E -e "s/^[0-9][0-9]$/&5e/g" > $TEMP2
cat $TEMP2
cd ../stannel
make -B TEST_FILE=$TEMP2 Processor_tb.vcd
