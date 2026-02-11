// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import {Script, console} from "forge-std/Script.sol";
import {Bedrock} from "../contracts/BR.sol";

/*

# prepare .env file
DEPLOYER=<deployer-account-name>
DEPLOYER_ADDRESS=<deployer-address>

EVM_RPC=<evm-rpc>
ETHERSCAN_API_URL=<etherscan-api-url> # https://api.etherscan.io/api , https://api.bscscan.com/api
ETHERSCAN_API_KEY=<etherscan-api-key>

# source .env
# forge script -vvvv --account $DEPLOYER --sender $DEPLOYER_ADDRESS -f $EVM_RPC --broadcast --verify --verifier custom --verifier-api-key $ETHERSCAN_API_KEY --verifier-url $ETHERSCAN_API_URL fscripts/deploy_BR.s.sol:Depoly

*/

contract Depoly is Script {
    function run() external {
        address deployer = vm.envAddress("DEPLOYER_ADDRESS");

        vm.startBroadcast(deployer);
        console.log("[Signer] deployer:", deployer);

        address _defaultAdmin = deployer;
        console.log("[Signer] defaultAdmin:", address(_defaultAdmin));

        address _defaultMinter = address(0x0);
        console.log("[Signer] defaultMinter:", address(_defaultMinter));

        Bedrock impl = new Bedrock(_defaultAdmin, _defaultMinter);
        console.log("[Contract] Bedrock:", address(impl));

        vm.stopBroadcast();
    }
}
