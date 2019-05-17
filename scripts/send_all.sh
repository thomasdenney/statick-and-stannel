#!/bin/sh
for i in ../programs/*.txt
do
    if [[ $i != *"untested"* ]]; then
        echo $i;
        ../scripts/send_bytes.py -lv bins/`basename "${i/txt/bin}"`;
        cat $i;
    fi
done
