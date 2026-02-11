#!/bin/bash

# run fork tests, tests in fork/<chain_name>/ will be run against <CHAIN_NAME>_FORK_URL
# if there is a chain dir without a corresponding env var, the script will fail

shopt -s globstar

chains=$(ls -d ./test/fork/*/ 2>/dev/null)

if [ -z "$chains" ]; then
    echo "No directories found in ./test/fork/"
    exit 0
fi

for dir in $chains; do
    dirName=$(basename "$dir")
    forkUrlName="${dirName^^}_FORK_URL"
    forkUrl="${!forkUrlName}"

    if [ -z "$forkUrl" ]; then
        echo "No value found for $forkUrlName"
        exit 1
    fi

    code=0

    hardhatFiles=$(find "$dir" -name "*.test.ts")
    if [ -z "$hardhatFiles" ]; then
        echo "No .test.ts files found in $dir"
    else
        echo "Running hardhat tests against \$$forkUrlName ..."
        FORK_URL=$forkUrl yarn run hardhat test $hardhatFiles --network fork
        CODE=$?
    fi
    [ "$code" -ne 0 ] && exit $code

    foundryFiles=$(find "$dir" -name "*.t.sol")
    if [ -z "$foundryFiles" ]; then
        echo "No .t.sol files found in $dir"
    else
        echo "Running foundry tests against \$$forkUrlName ..."
        forge test --fork-url $forkUrl --match-path "$dir**/*.t.sol"
        code=$?
    fi
    [ "$code" -ne 0 ] && exit $code
done

exit 0