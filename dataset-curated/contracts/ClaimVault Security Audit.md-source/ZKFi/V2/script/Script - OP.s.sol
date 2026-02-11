// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "../src/Vault.sol";
import "../src/zkToken.sol";
import "../src/WithdrawVault.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract VaultV2OP is Script {
    address owner = 0x6740a2b31BC55782e46C2a9D7A32A38905E118C5;
    address bot = 0x934C775d3004689EA5738FE80F34378f589F190D;
    address ceffu = 0xD038213A84a86348d000929C115528AE9DdC1158;
    address deployer;//need modify
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address USDT = 0x94b008aA00579c1307B0EF2c499aD98a8ce58e58;
        address USDC = 0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85;

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

        WithdrawVault withdrawVault = new WithdrawVault(supportedTokens, owner, bot, ceffu);


        zkToken zkt = new zkToken("zkUSDT", "zkUSDT", deployer);
        zkToken zkc = new zkToken("zkUSDC", "zkUSDC", deployer);
        address[] memory zks = new address[](2);
        zks[0] = address(zkt);
        zks[0] = address(zkc);

        uint[] memory totals = new uint[](2);
        totals[0] = 0;
        totals[1] = 0;

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

        zkt.setToVault(address(vault), address(vault));
        zkc.setToVault(address(vault), address(vault));

        zkt.setAdmin(owner);
        zkc.setAdmin(owner);

        vm.stopBroadcast();

        console.log("vault address:", address(vault));
        console.log("withdrawVault address:", address(withdrawVault));
        console.log("zkUSDT address:", address(zkt));
        console.log("zkUSDC address:", address(zkc));

    }
}
//forge script VaultV2OP --rpc-url https://optimism.llamarpc.com --broadcast --etherscan-api-key 6HF9Y3GRMNEQDD5DIYVXYMB58SYS7NRSR2 --verify