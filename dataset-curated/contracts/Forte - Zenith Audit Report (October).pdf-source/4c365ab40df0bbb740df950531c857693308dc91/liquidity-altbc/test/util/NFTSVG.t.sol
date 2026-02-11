// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "liquidity-base/src/common/SVG/NFTSVG.sol";
import {LPToken} from "liquidity-base/src/common/LPToken.sol";
import "liquidity-base/src/example/ERC20/GenericERC20.sol";
import "src/amm/ALTBCPool.sol";
import "forge-std/console.sol";

contract NFTSVGTest is Test {
    using Descriptor for Descriptor.ConstructTokenURIParams;

    ALTBCInput altbcInput = ALTBCInput(1e18, 1e14, 1e18, 1e24);

    function test_NFTSVG_WETH_USDC_1() public {
        GenericERC20 weth = new GenericERC20("WETH", "WETH");
        GenericERC20 usdc = new GenericERC20("USDC", "USDC");
        LPToken lpToken = new LPToken("LPToken", "LPT");

        ALTBCPool pool = new ALTBCPool(
            address(weth),
            address(usdc),
            address(lpToken),
            1,
            FeeInfo({_lpFee: 4800, _protocolFee: 20, _protocolFeeCollector: address(msg.sender)}),
            altbcInput,
            "1.0.0"
        );

        string memory uri = Descriptor.constructTokenURI(3, address(pool), false);
        console.log(uri);
    }

    function test_NFTSVG_WETH_USDC_2() public {
        GenericERC20 weth = new GenericERC20("WETH", "WETH");
        GenericERC20 usdc = new GenericERC20("USDC", "USDC");
        LPToken lpToken = new LPToken("LPToken", "LPT");

        ALTBCPool pool = new ALTBCPool(
            address(weth),
            address(usdc),
            address(lpToken),
            1,
            FeeInfo({_lpFee: 4800, _protocolFee: 20, _protocolFeeCollector: address(msg.sender)}),
            altbcInput,
            "1.0.0"
        );

        string memory uri = Descriptor.constructTokenURI(2, address(pool), false);
        console.log(uri);
    }

    function test_NFTSVG_Zero_Fee() public {
        GenericERC20 frank = new GenericERC20("FRANK", "FRANK");
        GenericERC20 usdc = new GenericERC20("USDC", "USDC");
        LPToken lpToken = new LPToken("LPToken", "LPT");

        ALTBCPool pool = new ALTBCPool(
            address(frank),
            address(usdc),
            address(lpToken),
            1,
            FeeInfo({_lpFee: 0, _protocolFee: 0, _protocolFeeCollector: address(msg.sender)}),
            altbcInput,
            "1.0.0"
        );
        string memory uri = Descriptor.constructTokenURI(2, address(pool), false);
        console.log(uri);
    }

    function test_NFTSVG_Edge_Cases() public {
        GenericERC20 frank = new GenericERC20("", "");
        GenericERC20 usdc = new GenericERC20("", "");
        LPToken lpToken = new LPToken("LPToken", "LPT");

        ALTBCPool pool = new ALTBCPool(
            address(frank),
            address(usdc),
            address(lpToken),
            1,
            FeeInfo({_lpFee: 4800, _protocolFee: 0, _protocolFeeCollector: address(msg.sender)}),
            altbcInput,
            "1.0.0"
        );

        string memory uri = Descriptor.constructTokenURI(1, address(pool), true);
        console.log(uri);
    }

    function test_NFTSVG_Special_Characters() public {
        GenericERC20 frank = new GenericERC20('FRANK"', 'FRANK"');
        GenericERC20 usdc = new GenericERC20("USDC\n", "USDC\n");
        LPToken lpToken = new LPToken("LPToken", "LPT");

        ALTBCPool pool = new ALTBCPool(
            address(frank),
            address(usdc),
            address(lpToken),
            1,
            FeeInfo({_lpFee: 4800, _protocolFee: 0, _protocolFeeCollector: address(msg.sender)}),
            altbcInput,
            "1.0.0"
        );

        string memory uri = Descriptor.constructTokenURI(4, address(pool), false);
        console.log(uri);
    }
}
