#!/bin/bash

source .env

# send output to null
cast chain-id --rpc-url $LOCAL_L3_URL &> /dev/null

# if the above command fails set ORBIT_TEST = 0
if [ $? -ne 0 ]; then
    export ORBIT_TEST=0
else
    export ORBIT_TEST=1
fi

cd lib/arbitrum-sdk && yarn gen:network && cd -

# if the above command fails, exit
if [ $? -ne 0 ]; then
    echo "Failed to generate network"
    exit 1
fi

yarn hardhat compile 

yarn mocha test/e2e/ --timeout 30000000 --bail
