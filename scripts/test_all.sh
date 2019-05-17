#!/bin/sh

FILES=$(ls -1 ../programs | grep ".txt" | grep -v "untested")
SUCCESS=0
FAIL=0

while read -r FILE; do
    ../scripts/test_program.py ../programs/$FILE
    if [ $? -eq 0 ]; then
        echo "✅ $FILE"
        SUCCESS=$((SUCCESS+1))
    else
        FAIL=$((FAIL+1))
        echo "❌ $FILE:"
    fi
done <<< "$FILES"
echo "Success = $SUCCESS, Fail = $FAIL"
if [ $FAIL -gt 0 ]; then
    exit 1
fi
