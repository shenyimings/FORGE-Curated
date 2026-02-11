// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "../src/Vault.sol";
import "../src/zkToken.sol";
import "../src/WithdrawVault.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract VaultV2ARB is Script {
    address owner = 0x6740a2b31BC55782e46C2a9D7A32A38905E118C5;
    address bot = 0x934C775d3004689EA5738FE80F34378f589F190D;
    address ceffu = 0xD038213A84a86348d000929C115528AE9DdC1158;
    address airdrop = address(0x01);//need modify
    address deployer;//need modify
    IVault vaultV1 = IVault(0x59f6E226a1055D05a9BD07f40AC2aa87e303CC33);
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address USDT = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;
        address USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;

        //rewardRate & supportToken
        address[] memory supportedTokens = new address[](2);
        supportedTokens[0] = USDT;
        supportedTokens[1] = USDC;
        uint256[] memory rewardRate = new uint256[](2);
        rewardRate[0] = 700;
        rewardRate[1] = 700;
        uint256[] memory minStakeAmount = new uint256[](2);
        minStakeAmount[0] = 0;
        minStakeAmount[1] = 0;
        uint256[] memory maxStakeAmount = new uint256[](2);
        maxStakeAmount[0] = type(uint256).max;
        maxStakeAmount[1] = type(uint256).max;

        WithdrawVault withdrawVault = new WithdrawVault(supportedTokens, deployer, bot, ceffu);

        vaultV1.pause();
        
        uint[] memory totalStaked = new uint[](2);
        totalStaked[0] = 1500 ether;//need modify
        totalStaked[1] = 1500 ether;
        uint[] memory tvl = new uint[](2);
        tvl[0] = vaultV1.getTVL(USDT);
        tvl[1] = vaultV1.getTVL(USDC);

        zkToken zkt = new zkToken("zkUSDT", "zkUSDT", deployer);
        zkToken zkc = new zkToken("zkUSDC", "zkUSDC", deployer);
        address[] memory zks = new address[](2);
        zks[0] = address(zkt);
        zks[0] = address(zkc);
        zkt.mint(airdrop, totalStaked[0]);
        zkc.mint(airdrop, totalStaked[1]);

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
            airdrop
        );

        withdrawVault.setVault(address(vault));
        withdrawVault.changeAdmin(owner);

        zkt.setToVault(address(vault), address(vault));
        zkc.setToVault(address(vault), address(vault));

        zkt.setAirdropper(airdrop);
        zkc.setAirdropper(airdrop);

        zkt.setAdmin(owner);
        zkc.setAdmin(owner);

        vm.stopBroadcast();

        console.log("vault address:", address(vault));
        console.log("withdrawVault address:", address(withdrawVault));
        console.log("vaultV1 address:", address(vaultV1));
        console.log("zkUSDT address:", address(zkt));
        console.log("zkUSDC address:", address(zkc));

    }
}
//forge script VaultV2ARB --rpc-url https://arbitrum.llamarpc.com --broadcast --etherscan-api-key YFSWHWURTC46D6R9GY7Z4YA1KR3YKT4AFY --verify