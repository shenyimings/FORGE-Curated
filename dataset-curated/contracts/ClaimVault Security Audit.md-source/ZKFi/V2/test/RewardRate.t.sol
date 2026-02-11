// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/IVault.sol";


contract rateTest is Test{

    function testAVAXRate() public {
        vm.createSelectFork("https://avax.meowrpc.com");
        IVault vault = IVault(0x59f6E226a1055D05a9BD07f40AC2aa87e303CC33);
        (uint rate, ) = vault.getCurrentRewardRate(0x9702230A8Ea53601f5cD2dc00fDBc13d4dF4A8c7);
        (uint rate1, ) = vault.getCurrentRewardRate(0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E);
        console.log("rateUSDT: ", rate);
        console.log("rateUSDC: ", rate1);
    }
    function testPOLYRate() public {
        vm.createSelectFork("https://polygon-rpc.com");
        IVault vault = IVault(0x59f6E226a1055D05a9BD07f40AC2aa87e303CC33);
        (uint rate, ) = vault.getCurrentRewardRate(0xc2132D05D31c914a87C6611C10748AEb04B58e8F);
        (uint rate1, ) = vault.getCurrentRewardRate(0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359);
        console.log("rateUSDT: ", rate);
        console.log("rateUSDC: ", rate1);
    }
    function testBSCRate() public {
        vm.createSelectFork("https://bsc.drpc.org");
        IVault vault = IVault(0x59f6E226a1055D05a9BD07f40AC2aa87e303CC33);
        (uint rate, ) = vault.getCurrentRewardRate(0x55d398326f99059fF775485246999027B3197955);
        (uint rate1, ) = vault.getCurrentRewardRate(0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d);
        console.log("rateUSDT: ", rate);
        console.log("rateUSDC: ", rate1);
    }
    function testETHRate() public {
        vm.createSelectFork("https://eth.llamarpc.com");
        IVault vault = IVault(0x59f6E226a1055D05a9BD07f40AC2aa87e303CC33);
        (uint rate, ) = vault.getCurrentRewardRate(0xdAC17F958D2ee523a2206206994597C13D831ec7);
        (uint rate1, ) = vault.getCurrentRewardRate(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
        console.log("rateUSDT: ", rate);
        console.log("rateUSDC: ", rate1);
    }
    function testARBRate() public {
        vm.createSelectFork("https://arbitrum.drpc.org");
        IVault vault = IVault(0x59f6E226a1055D05a9BD07f40AC2aa87e303CC33);
        (uint rate, ) = vault.getCurrentRewardRate(0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9);
        (uint rate1, ) = vault.getCurrentRewardRate(0xaf88d065e77c8cC2239327C5EDb3A432268e5831);
        console.log("rateUSDT: ", rate);
        console.log("rateUSDC: ", rate1);
    }
}