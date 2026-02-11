// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "../src/Vault.sol";
import "../src/zkToken.sol";
import "../src/WithdrawVault.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract VaultV2BASE is Script {
    address owner = 0x6740a2b31BC55782e46C2a9D7A32A38905E118C5;
    address bot = 0x934C775d3004689EA5738FE80F34378f589F190D;
    address ceffu = 0xD038213A84a86348d000929C115528AE9DdC1158;
    address deployer;//need modify
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

        //rewardRate & supportToken
        address[] memory supportedTokens = new address[](1);
        supportedTokens[0] = USDC;
        uint256[] memory rewardRate = new uint256[](1);
        rewardRate[0] = 700;
        uint256[] memory minStakeAmount = new uint256[](1);
        minStakeAmount[0] = 0;
        uint256[] memory maxStakeAmount = new uint256[](1);
        maxStakeAmount[0] = type(uint256).max;

        WithdrawVault withdrawVault = new WithdrawVault(supportedTokens, deployer, bot, ceffu);


        zkToken zkc = new zkToken("zkUSDC", "zkUSDC", owner);
        address[] memory zks = new address[](1);
        zks[0] = address(zkc);

        uint[] memory totals = new uint[](1);
        totals[0] = 0;

        IVault vault = new Vault(
            supportedTokens,
            zks,
            rewardRate,
            minStakeAmount,
            maxStakeAmount,
            owner, // admin
            bot, // bot
            ceffu,
            14 days,
            payable(address(withdrawVault)),
            address(0)
        );

        withdrawVault.setVault(address(vault));
        withdrawVault.changeAdmin(owner);

        zkc.setToVault(address(vault), address(vault));
        zkc.setAdmin(owner);

        vm.stopBroadcast();

        console.log("vault address:", address(vault));
        console.log("withdrawVault address:", address(withdrawVault));
        console.log("zkUSDC address:", address(zkc));

    }
}
//forge script VaultV2BASE --rpc-url https://base.llamarpc.com --broadcast --etherscan-api-key BC4TGWPYAWBVTSNJZ2568U3UQ56GT3AVJB --verify
