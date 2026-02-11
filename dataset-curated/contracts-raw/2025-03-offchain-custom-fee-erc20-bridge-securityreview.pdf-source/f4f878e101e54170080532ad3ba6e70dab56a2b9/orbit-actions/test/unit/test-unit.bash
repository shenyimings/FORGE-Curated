#!/bin/bash

shopt -s globstar

code=0

hardhatFiles=$(ls ./test/unit/**/*.test.ts 2>/dev/null)
if [ -n "$hardhatFiles" ]; then
    yarn run hardhat test $hardhatFiles
    code=$?
fi

[ "$code" -ne 0 ] && exit $code

foundryFiles=$(ls ./test/unit/**/*.t.sol 2>/dev/null)
if [ -n "$foundryFiles" ]; then
    forge test --match-path "test/unit/*.t.sol" -vvv
    code=$?
fi

exit $code
