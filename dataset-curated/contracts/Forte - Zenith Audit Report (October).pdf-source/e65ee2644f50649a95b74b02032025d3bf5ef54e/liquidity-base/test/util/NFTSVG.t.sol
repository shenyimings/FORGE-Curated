// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "src/common/SVG/NFTSVG.sol";
import "src/amm/base/PoolBase.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "forge-std/console.sol";

contract NFTSVGTest is Test {
    using Descriptor for Descriptor.ConstructTokenURIParams;

    // function test_NFTSVG_WETH_USDC_1() public {
    //     ERC20 weth = new ERC20("WETH", "WETH");
    //     ERC20 usdc = new ERC20("USDC", "USDC");

    //     PoolBase pool = new PoolBase(address(weth), address(usdc), FeeInfo({
    //         _lpFee: 10000,
    //         _protocolFee: 10000,
    //         _protocolFeeCollector: address(0)
    //     }), "Test Pool", "TP");

    //     string memory uri = Descriptor.constructTokenURI(
    //         1,
    //         address(pool)
    //     );
    //     console.log(uri);
    // }

    // function test_NFTSVG_WETH_USDC_2() public pure {
    //     Descriptor.ConstructTokenURIParams memory params = Descriptor.ConstructTokenURIParams({
    //         tokenId: 2,
    //         xTokenAddress: address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2),
    //         yTokenAddress: address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48),
    //         poolManager: address(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266),
    //         xTokenSymbol: 'WETH',
    //         yTokenSymbol: 'USDC',
    //         fee: 10000
    //     });
    //     string memory uri = Descriptor.constructTokenURI(params);
    //     console.log(uri);
    // }

    // function test_NFTSVG_FRANK_USDC_1() public pure {
    //     Descriptor.ConstructTokenURIParams memory params = Descriptor.ConstructTokenURIParams({
    //         tokenId: 1,
    //         xTokenAddress: address(0x4200000000000000000000000000000000000006),
    //         yTokenAddress: address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48),
    //         poolManager: address(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266),
    //         xTokenSymbol: 'FRANK',
    //         yTokenSymbol: 'USDC',
    //         fee: 10000
    //     });
    //     string memory uri = Descriptor.constructTokenURI(params);
    //     console.log(uri);
    // }

    // function test_NFTSVG_FRANK_USDC_2() public pure {
    //     Descriptor.ConstructTokenURIParams memory params = Descriptor.ConstructTokenURIParams({
    //         tokenId: 2,
    //         xTokenAddress: address(0x4200000000000000000000000000000000000006),
    //         yTokenAddress: address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48),
    //         poolManager: address(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266),
    //         xTokenSymbol: 'FRANK',
    //         yTokenSymbol: 'USDC',
    //         fee: 10000
    //     });
    //     string memory uri = Descriptor.constructTokenURI(params);
    //     console.log(uri);
    // }

    // function test_NFTSVG_Zero_Fee() public pure {
    //     Descriptor.ConstructTokenURIParams memory params = Descriptor.ConstructTokenURIParams({
    //         tokenId: 1,
    //         xTokenAddress: address(0x4200000000000000000000000000000000000006),
    //         yTokenAddress: address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48),
    //         poolManager: address(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266),
    //         xTokenSymbol: 'FRANK',
    //         yTokenSymbol: 'USDC',
    //         fee: 0  // Zero fee
    //     });
    //     string memory uri = Descriptor.constructTokenURI(params);
    //     console.log(uri);
    // }

    // function test_NFTSVG_Special_Characters() public pure {
    //     Descriptor.ConstructTokenURIParams memory params = Descriptor.ConstructTokenURIParams({
    //         tokenId: 1,
    //         xTokenAddress: address(0x4200000000000000000000000000000000000006),
    //         yTokenAddress: address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48),
    //         poolManager: address(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266),
    //         xTokenSymbol: 'FRANK"',  // Add special character
    //         yTokenSymbol: 'USDC\n',  // Add special character
    //         fee: type(uint16).max
    //     });
    //     string memory uri = Descriptor.constructTokenURI(params);
    //     console.log(uri);
    // }

    // function test_NFTSVG_Edge_Cases() public pure {
    //     Descriptor.ConstructTokenURIParams memory params = Descriptor.ConstructTokenURIParams({
    //         tokenId: 0,  // Edge case token ID
    //         xTokenAddress: address(0),  // Zero address
    //         yTokenAddress: address(0),  // Zero address
    //         poolManager: address(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266),
    //         xTokenSymbol: '',  // Empty string
    //         yTokenSymbol: '',  // Empty string
    //         fee: type(uint16).max  // Near max fee
    //     });
    //     string memory uri = Descriptor.constructTokenURI(params);
    //     console.log(uri);
    // }
}
