#!/bin/bash

if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
    echo "Usage: $0 <auditor-address> <input-file> <output-file>"
    exit 1
fi

AUDITOR=$1
INPUT_FILE=$2
OUTPUT_FILE=$3

if [ ! -f "$INPUT_FILE" ]; then
    printf "\e[31mError: Input file '$INPUT_FILE' not found\e[0m\n"
    exit 1
fi

while IFS= read -r BYTECODE_HASH || [ -n "$BYTECODE_HASH" ]; do
    if [ -n "$BYTECODE_HASH" ]; then
        echo "Processing hash: $BYTECODE_HASH"
        if ./script/validate.sh "$BYTECODE_HASH"; then
            read -p "Enter report URL for this hash: " REPORT_URL </dev/tty
            ./script/sign.sh "$BYTECODE_HASH" "$AUDITOR" "$REPORT_URL" >> "$OUTPUT_FILE"
        fi
        echo
    fi
done < "$INPUT_FILE"
