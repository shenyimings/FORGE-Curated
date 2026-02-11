#!/bin/bash

if [ -z "$1" ]; then
    echo "Usage: $0 <bytecode-hash>"
    exit 1
fi

BCR=0x1cE2B1BE96a082b1b1539F80d5D8f82Ec06a0f9A
BYTECODE_HASH=$1

content=$(curl -s "https://permissionless.gearbox.foundation/bytecode/hash/$BYTECODE_HASH")

json_block=$(echo "$content" | tr -d '\\' | grep -o '"bytecode":{"bytecodeHash":"[^}]*}')
if [ -z "$json_block" ]; then
    printf "\e[31mError: Bytecode not found!\e[0m\n"
    exit 1
fi

CONTRACT_TYPE=$(echo "$json_block" | grep -o '"contractType":"[^"]*"' | cut -d'"' -f4)
echo "Contract type: $(cast parse-bytes32-string $CONTRACT_TYPE)"

VERSION=$(echo "$json_block" | grep -o '"version":[0-9]*' | cut -d':' -f2)
echo "Version: $VERSION"

SOURCE_URL=$(echo "$json_block" | grep -o '"source":"[^"]*"' | cut -d'"' -f4)
echo "Source URL: $SOURCE_URL"

AUTHOR=$(echo "$json_block" | grep -o '"author":"[^"]*"' | cut -d'"' -f4)
echo "Author: $AUTHOR"

INIT_CODE=$(echo "$content" | grep -o '<code class="grid text-white whitespace-pre-wrap break-all">0x[^<]*' | head -n1 | sed 's/<code class="grid text-white whitespace-pre-wrap break-all">//')
echo "Init code: ${INIT_CODE:0:30}...${INIT_CODE: -10}"

FILENAME=$(rg -l $INIT_CODE $PWD)
if [ -n "$FILENAME" ]; then
    printf "\e[32mInit code found in: $FILENAME\e[0m\n"
else
    printf "\e[31mError: Init code not found in any file!\e[0m\n"
    exit 1
fi

COMPUTED_HASH=$(cast call $BCR "computeBytecodeHash((bytes32,uint256,bytes,address,string,bytes)) returns (bytes32)" "($CONTRACT_TYPE,$VERSION,$INIT_CODE,$AUTHOR,$SOURCE_URL,0x)" --rpc-url ${RPC_URL})

if [ "$COMPUTED_HASH" != "$BYTECODE_HASH" ]; then
    printf "\e[31mError: Hashes do not match! Computed hash: $COMPUTED_HASH\e[0m\n"
    exit 1
fi

printf "\e[32mSuccess: Hashes match!\e[0m\n"
