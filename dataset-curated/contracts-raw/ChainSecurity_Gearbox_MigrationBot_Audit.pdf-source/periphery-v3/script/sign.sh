#!/bin/bash

if [ -z "$1" -o -z "$2" -o -z "$3" ]; then
    echo "Usage: $0 <bytecode-hash> <auditor> <report-url>"
    exit 1
fi

BCR=0x1cE2B1BE96a082b1b1539F80d5D8f82Ec06a0f9A
BYTECODE_HASH=$1
AUDITOR=$2
REPORT_URL=$3

cat > typed_data.json << EOF
{
    "types": {
        "EIP712Domain": [
            { "name": "name", "type": "string" },
            { "name": "version", "type": "string" },
            { "name": "chainId", "type": "uint256" },
            { "name": "verifyingContract", "type": "address" }
        ],
        "AuditReport": [
            { "name": "bytecodeHash", "type": "bytes32" },
            { "name": "auditor", "type": "address" },
            { "name": "reportUrl", "type": "string" }
        ]
    },
    "primaryType": "AuditReport",
    "domain": {
        "name": "BYTECODE_REPOSITORY",
        "version": "310",
        "chainId": 1,
        "verifyingContract": "$BCR"
    },
    "message": {
        "bytecodeHash": "$BYTECODE_HASH",
        "auditor": "$AUDITOR",
        "reportUrl": "$REPORT_URL"
    }
}
EOF

SIGNATURE=$(cast wallet sign --data --from-file typed_data.json --ledger)
rm typed_data.json

echo "$BYTECODE_HASH,$AUDITOR,$REPORT_URL,$SIGNATURE"
