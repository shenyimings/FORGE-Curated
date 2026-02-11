// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";

contract Environment is Test {
    address public constant AXELAR_GATEWAY_MAINNET = 0x4F4495243837681061C4743b74B3eEdf548D56A5;
    address public constant AXELAR_GATEWAY_BNB = 0x304acf330bbE08d1e512eefaa92F6a57871fD895;
    address public constant AXELAR_GATEWAY_POLYGON = 0x6f015F16De9fC8791b234eF68D486d2bF203FBA8;
    address public constant AXELAR_GATEWAY_AVALANCHE = 0x5029C0EFf6C34351a0CEc334542cDb22c7928f78;
    address public constant AXELAR_GATEWAY_ARBITRUM = 0xe432150cce91c13a887f7D836923d5597adD8E31;
    address public constant AXELAR_GATEWAY_OPTIMISM = 0xe432150cce91c13a887f7D836923d5597adD8E31;
    address public constant AXELAR_GATEWAY_BASE = 0xe432150cce91c13a887f7D836923d5597adD8E31;
    address public constant AXELAR_GATEWAY_LINEA = 0xe432150cce91c13a887f7D836923d5597adD8E31;
    address public constant AXELAR_GATEWAY_MANTLE = 0xe432150cce91c13a887f7D836923d5597adD8E31;
    address public constant AXELAR_GATEWAY_FANTOM = 0x304acf330bbE08d1e512eefaa92F6a57871fD895;
    address public constant AXELAR_GATEWAY_MOONBEAM = 0x4F4495243837681061C4743b74B3eEdf548D56A5;
    address public constant AXELAR_GATEWAY_CELO = 0xe432150cce91c13a887f7D836923d5597adD8E31;
    address public constant AXELAR_GATEWAY_FILECOIN = 0xe432150cce91c13a887f7D836923d5597adD8E31;
    address public constant AXELAR_GATEWAY_KAVA = 0xe432150cce91c13a887f7D836923d5597adD8E31;
    address public constant AXELAR_GATEWAY_BLAST = 0xe432150cce91c13a887f7D836923d5597adD8E31;
    address public constant AXELAR_GATEWAY_POLYGON_MUMBAI = 0xBF62ef1486468a6bd26Dd669C06db43dEd5B849B;
    address public constant AXELAR_GATEWAY_ETHEREUM_GOERLI = 0xe432150cce91c13a887f7D836923d5597adD8E31;

    address public constant AXELAR_GAS_SERVICE_MAINNET = 0x2d5d7d31F671F86C782533cc367F14109a082712;
    address public constant AXELAR_GAS_SERVICE_BNB = 0x2d5d7d31F671F86C782533cc367F14109a082712;
    address public constant AXELAR_GAS_SERVICE_POLYGON = 0x2d5d7d31F671F86C782533cc367F14109a082712;
    address public constant AXELAR_GAS_SERVICE_AVALANCHE = 0x2d5d7d31F671F86C782533cc367F14109a082712;
    address public constant AXELAR_GAS_SERVICE_ARBITRUM = 0x2d5d7d31F671F86C782533cc367F14109a082712;
    address public constant AXELAR_GAS_SERVICE_OPTIMISM = 0x2d5d7d31F671F86C782533cc367F14109a082712;
    address public constant AXELAR_GAS_SERVICE_BASE = 0x2d5d7d31F671F86C782533cc367F14109a082712;
    address public constant AXELAR_GAS_SERVICE_LINEA = 0x2d5d7d31F671F86C782533cc367F14109a082712;
    address public constant AXELAR_GAS_SERVICE_MANTLE = 0x2d5d7d31F671F86C782533cc367F14109a082712;
    address public constant AXELAR_GAS_SERVICE_FANTOM = 0x2d5d7d31F671F86C782533cc367F14109a082712;
    address public constant AXELAR_GAS_SERVICE_MOONBEAM = 0x2d5d7d31F671F86C782533cc367F14109a082712;
    address public constant AXELAR_GAS_SERVICE_CELO = 0x2d5d7d31F671F86C782533cc367F14109a082712;
    address public constant AXELAR_GAS_SERVICE_FILECOIN = 0x2d5d7d31F671F86C782533cc367F14109a082712;
    address public constant AXELAR_GAS_SERVICE_KAVA = 0x2d5d7d31F671F86C782533cc367F14109a082712;
    address public constant AXELAR_GAS_SERVICE_BLAST = 0x2d5d7d31F671F86C782533cc367F14109a082712;
    address public constant AXELAR_GAS_SERVICE_POLYGON_MUMBAI = 0xbE406F0189A0B4cf3A05C286473D23791Dd44Cc6;
    address public constant AXELAR_GAS_SERVICE_ETHEREUM_GOERLI = 0xbE406F0189A0B4cf3A05C286473D23791Dd44Cc6;

    address public constant UNISWAP_SWAP_ROUTER_02_MAINNET = 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;

    string public constant AXELAR_WETH_SYMBOL_MAINNET = "WETH";
    string public constant AXELAR_WETH_SYMBOL_BNB = "WBNB";
    string public constant AXELAR_WETH_SYMBOL_POLYGON = "WMATIC";
    string public constant AXELAR_WETH_SYMBOL_AVALANCHE = "WAVAX";
    string public constant AXELAR_WETH_SYMBOL_ARBITRUM = "axlETH";
    string public constant AXELAR_WETH_SYMBOL_OPTIMISM = "axlETH";
    string public constant AXELAR_WETH_SYMBOL_BASE = "axlETH";
    string public constant AXELAR_WETH_SYMBOL_LINEA = "axlETH";
    string public constant AXELAR_WETH_SYMBOL_MANTLE = "axlETH";
    string public constant AXELAR_WETH_SYMBOL_FANTOM = "WFTM";
    string public constant AXELAR_WETH_SYMBOL_MOONBEAM = "WGLMR";
    string public constant AXELAR_WETH_SYMBOL_CELO = "DISABLED";
    string public constant AXELAR_WETH_SYMBOL_FILECOIN = "WFIL";
    string public constant AXELAR_WETH_SYMBOL_KAVA = "axlETH";
    string public constant AXELAR_WETH_SYMBOL_BLAST = "axlETH";
    string public constant AXELAR_WETH_SYMBOL_POLYGON_MUMBAI = "WMATIC";
    string public constant AXELAR_WETH_SYMBOL_ETHEREUM_GOERLI = "WETH";

    address public gateway;
    address public gasService;
    address public swapRouter;
    string public wethSymbol;

    function setEnv(uint256 chainId) public {
        if (chainId == 1) {
            gateway = AXELAR_GATEWAY_MAINNET;
            gasService = AXELAR_GAS_SERVICE_MAINNET;
            swapRouter = UNISWAP_SWAP_ROUTER_02_MAINNET;
            wethSymbol = AXELAR_WETH_SYMBOL_MAINNET;
        } else if (chainId == 56) {
            gateway = AXELAR_GATEWAY_BNB;
            gasService = AXELAR_GAS_SERVICE_BNB;
            wethSymbol = AXELAR_WETH_SYMBOL_BNB;
        } else if (chainId == 137) {
            gateway = AXELAR_GATEWAY_POLYGON;
            gasService = AXELAR_GAS_SERVICE_POLYGON;
            wethSymbol = AXELAR_WETH_SYMBOL_POLYGON;
        } else if (chainId == 43114) {
            gateway = AXELAR_GATEWAY_AVALANCHE;
            gasService = AXELAR_GAS_SERVICE_AVALANCHE;
            wethSymbol = AXELAR_WETH_SYMBOL_AVALANCHE;
        } else if (chainId == 42161) {
            gateway = AXELAR_GATEWAY_ARBITRUM;
            gasService = AXELAR_GAS_SERVICE_ARBITRUM;
            wethSymbol = AXELAR_WETH_SYMBOL_ARBITRUM;
        } else if (chainId == 10) {
            gateway = AXELAR_GATEWAY_OPTIMISM;
            gasService = AXELAR_GAS_SERVICE_OPTIMISM;
            wethSymbol = AXELAR_WETH_SYMBOL_OPTIMISM;
        } else if (chainId == 8453) {
            gateway = AXELAR_GATEWAY_BASE;
            gasService = AXELAR_GAS_SERVICE_BASE;
            wethSymbol = AXELAR_WETH_SYMBOL_BASE;
        } else if (chainId == 59144) {
            gateway = AXELAR_GATEWAY_LINEA;
            gasService = AXELAR_GAS_SERVICE_LINEA;
            wethSymbol = AXELAR_WETH_SYMBOL_LINEA;
        } else if (chainId == 5000) {
            gateway = AXELAR_GATEWAY_MANTLE;
            gasService = AXELAR_GAS_SERVICE_MANTLE;
            wethSymbol = AXELAR_WETH_SYMBOL_MANTLE;
        } else if (chainId == 250) {
            gateway = AXELAR_GATEWAY_FANTOM;
            gasService = AXELAR_GAS_SERVICE_FANTOM;
            wethSymbol = AXELAR_WETH_SYMBOL_FANTOM;
        } else if (chainId == 1284) {
            gateway = AXELAR_GATEWAY_MOONBEAM;
            gasService = AXELAR_GAS_SERVICE_MOONBEAM;
            wethSymbol = AXELAR_WETH_SYMBOL_MOONBEAM;
        } else if (chainId == 42220) {
            gateway = AXELAR_GATEWAY_CELO;
            gasService = AXELAR_GAS_SERVICE_CELO;
            wethSymbol = AXELAR_WETH_SYMBOL_CELO;
        } else if (chainId == 314) {
            gateway = AXELAR_GATEWAY_FILECOIN;
            gasService = AXELAR_GAS_SERVICE_FILECOIN;
            wethSymbol = AXELAR_WETH_SYMBOL_FILECOIN;
        } else if (chainId == 2222) {
            gateway = AXELAR_GATEWAY_KAVA;
            gasService = AXELAR_GAS_SERVICE_KAVA;
            wethSymbol = AXELAR_WETH_SYMBOL_KAVA;
        } else if (chainId == 81457) {
            gateway = AXELAR_GATEWAY_BLAST;
            gasService = AXELAR_GAS_SERVICE_BLAST;
            wethSymbol = AXELAR_WETH_SYMBOL_BLAST;
        } else if (chainId == 80001) {
            gateway = AXELAR_GATEWAY_POLYGON_MUMBAI;
            gasService = AXELAR_GAS_SERVICE_POLYGON_MUMBAI;
            wethSymbol = AXELAR_WETH_SYMBOL_POLYGON_MUMBAI;
        } else if (chainId == 5) {
            gateway = AXELAR_GATEWAY_ETHEREUM_GOERLI;
            gasService = AXELAR_GAS_SERVICE_ETHEREUM_GOERLI;
            wethSymbol = AXELAR_WETH_SYMBOL_ETHEREUM_GOERLI;
        } else {
            revert("CHAIN UNSUPPORTED");
        }
    }
}
