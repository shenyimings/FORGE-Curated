// // SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import {Vault} from "../src/Vault.sol";
import {MockERC20} from "../test/MockERC20.sol";

// Deploy Command: forge script script/Vault.s.sol:VaultDeployerScript --broadcast --etherscan-api-key %ETHERSCAN_KEY% --verify -vvvv --rpc-url "RPC_URL"
contract VaultDeployerScript is Script {

    // @dev TODO: Please replace `multipleSignaturesAddress` with your own.
    //            You could get a multi-signature wallet address from: https://app.safe.global/welcome
    address constant multipleSignaturesAddress = 0x0000000000000000000000000000000000000000;
    // @dev TODO: Please replace `botAddress` with the bot address
    address constant botAddress = 0x0000000000000000000000000000000000000000;
    // @dev TODO: Please replace `ceffu` with the actual ceffu address
    address constant ceffu = 0x0000000000000000000000000000000000000000;
    // @dev TODO: Please modify the waiting time
    uint256 constant waitingTime = 14 days;
    // @dev TODO: Please modify according to the stablecoins that need to be supported.
    uint256 constant SUPPORT_TOKENS_NUMBER = 2;
    address constant usdt = 0x0000000000000000000000000000000000000000;
    address constant usdc = 0x0000000000000000000000000000000000000000;

    function run() public {
        // Get the private key from the `.env` file
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // @dev We do not need to deploy the ERC20 token used for testing in the production environment. 
        //      Therefore, remove the following two lines of code during production deployment.
        // MockERC20 token = new MockERC20();
        // console.log("Mock ERC20 address:", address(token));

        // @dev TODO: Please set up the configuration for supported tokens, 
        //      and make reasonable modifications according to the following format.
        address[] memory supportedTokens = new address[](SUPPORT_TOKENS_NUMBER);
        supportedTokens[0] = address(usdt);
        supportedTokens[1] = address(usdc);
        uint256[] memory rewardRate = new uint256[](SUPPORT_TOKENS_NUMBER);
        rewardRate[0] = 0; // e.g., APR: 700 -> 7%
        rewardRate[1] = 0; // e.g., APR: 700 -> 7%
        uint256[] memory minStakeAmount = new uint256[](SUPPORT_TOKENS_NUMBER);
        // @dev Note: The decimals of stablecoins may vary across different networks
        // For example: The decimal of USDT in Ethereum is 6, but it is 18 in BSC.
        minStakeAmount[0] = 0;
        minStakeAmount[1] = 0;
        uint256[] memory maxStakeAmount = new uint256[](SUPPORT_TOKENS_NUMBER);
        maxStakeAmount[0] = type(uint256).max;
        maxStakeAmount[1] = type(uint256).max;

        Vault vault = new Vault(
            supportedTokens, 
            rewardRate,
            minStakeAmount, 
            maxStakeAmount, 
            multipleSignaturesAddress, // admin
            botAddress, // bot
            ceffu, 
            waitingTime
        );

        console.log("Vault address:", address(vault));
        
        vm.stopBroadcast();
    }
}