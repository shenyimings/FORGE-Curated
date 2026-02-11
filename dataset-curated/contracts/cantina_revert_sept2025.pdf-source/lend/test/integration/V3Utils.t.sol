// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../../src/utils/Constants.sol";
import "../../src/transformers/V3Utils.sol";

contract V3UtilsIntegrationTest is Test {
    uint256 constant Q64 = 2 ** 64;

    int24 constant MIN_TICK_100 = -887272;
    int24 constant MIN_TICK_500 = -887270;

    IERC20 constant WETH_ERC20 = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IERC20 constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20 constant DAI = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);

    address constant WHALE_ACCOUNT = 0xF977814e90dA44bFA03b6295A0616a897441aceC;
    address constant DAI_WHALE_ACCOUNT = 0x2fEb1512183545f48f6b9C5b4EbfCaF49CfCa6F3;
    address constant OPERATOR_ACCOUNT = 0xF977814e90dA44bFA03b6295A0616a897441aceC;
    address constant WITHDRAWER_ACCOUNT = 0xF977814e90dA44bFA03b6295A0616a897441aceC;

    uint64 constant MAX_REWARD = uint64(Q64 / 400); //0.25%
    uint64 constant MAX_FEE_REWARD = uint64(Q64 / 20); //5%

    address FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;

    INonfungiblePositionManager constant NPM = INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);

    address EX0x = 0xDef1C0ded9bec7F1a1670819833240f027b25EfF; // 0x exchange proxy
    address UNIVERSAL_ROUTER = 0xEf1c6E67703c7BD7107eed8303Fbe6EC2554BF6B; // uniswap universal router
    address PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    // DAI/USDC 0.05% - one sided only DAI - current tick is near -276326 - no liquidity (-276320/-276310)
    uint256 constant TEST_NFT = 24181;
    address constant TEST_NFT_ACCOUNT = 0x8cadb20A4811f363Dadb863A190708bEd26245F8;
    address constant TEST_NFT_POOL = 0x6c6Bc977E13Df9b0de53b251522280BB72383700;

    uint256 constant TEST_NFT_2 = 7; // DAI/WETH 0.3% - one sided only WETH - with liquidity and fees (-84120/-78240)
    uint256 constant TEST_NFT_2_A = 126; // DAI/USDC 0.05% - in range (-276330/-276320)
    uint256 constant TEST_NFT_2_B = 37; // USDC/WETH 0.3% - out of range (192180/193380)
    address constant TEST_NFT_2_ACCOUNT = 0x3b8ccaa89FcD432f1334D35b10fF8547001Ce3e5;
    address constant TEST_NFT_2_POOL = 0xC2e9F25Be6257c210d7Adf0D4Cd6E3E881ba25f8;

    // DAI/USDC 0.05% - in range - with liquidity and fees
    uint256 constant TEST_NFT_3 = 4660;
    address constant TEST_NFT_3_ACCOUNT = 0xa3eF006a7da5BcD1144d8BB86EfF1734f46A0c1E;
    address constant TEST_NFT_3_POOL = 0x6c6Bc977E13Df9b0de53b251522280BB72383700;

    // USDC/WETH 0.3% - in range - with liquidity and fees
    uint256 constant TEST_NFT_4 = 827;
    address constant TEST_NFT_4_ACCOUNT = 0x96653b13bD00842Eb8Bc77dCCFd48075178733ce;
    address constant TEST_NFT_4_POOL = 0x8ad599c3A0ff1De082011EFDDc58f1908eb6e6D8;

    // DAI/USDC 0.05% - in range - with liquidity and fees
    uint256 constant TEST_NFT_5 = 23901;
    address constant TEST_NFT_5_ACCOUNT = 0x082d3e0f04664b65127876e9A05e2183451c792a;

    address constant TEST_FEE_ACCOUNT = 0x8df57E3D9dDde355dCE1adb19eBCe93419ffa0FB;

    uint256 mainnetFork;

    V3Utils v3utils;

    function setUp() external {
          string memory ANKR_RPC = string.concat(
            "https://rpc.ankr.com/eth/",
            vm.envString("ANKR_API_KEY")
        );
        mainnetFork = vm.createFork(ANKR_RPC, 15489169);
        vm.selectFork(mainnetFork);
        v3utils = new V3Utils(NPM, EX0x, UNIVERSAL_ROUTER, PERMIT2);
    }

    function testUnauthorizedTransfer() external {
        vm.expectRevert(abi.encodePacked("ERC721: transfer caller is not owner nor approved"));
        V3Utils.Instructions memory inst = V3Utils.Instructions(
            V3Utils.WhatToDo.CHANGE_RANGE,
            address(0),
            0,
            0,
            0,
            0,
            "",
            0,
            0,
            "",
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            TEST_NFT_ACCOUNT,
            TEST_NFT_ACCOUNT,
            false,
            "",
            ""
        );
        NPM.safeTransferFrom(TEST_NFT_ACCOUNT, address(v3utils), TEST_NFT, abi.encode(inst));
    }

    function testInvalidInstructions() external {
        // reverts with ERC721Receiver error if Instructions are invalid
        vm.expectRevert(abi.encodePacked("ERC721: transfer to non ERC721Receiver implementer"));
        vm.prank(TEST_NFT_ACCOUNT);
        NPM.safeTransferFrom(TEST_NFT_ACCOUNT, address(v3utils), TEST_NFT, abi.encode(true, false, 1, "test"));
    }

    function testSendEtherNotAllowed() external {
        bool success;
        vm.expectRevert(Constants.NotWETH.selector);
        (success,) = address(v3utils).call{value: 123}("");
    }

    function testTransferWithCompoundNoSwap() external {
        V3Utils.Instructions memory inst = V3Utils.Instructions(
            V3Utils.WhatToDo.COMPOUND_FEES,
            address(0),
            0,
            0,
            0,
            0,
            "",
            0,
            0,
            "",
            type(uint128).max,
            type(uint128).max,
            0,
            0,
            0,
            0,
            0,
            0,
            block.timestamp,
            TEST_NFT_3_ACCOUNT,
            TEST_NFT_3_ACCOUNT,
            false,
            "",
            ""
        );

        uint256 daiBefore = DAI.balanceOf(TEST_NFT_3_ACCOUNT);
        uint256 usdcBefore = USDC.balanceOf(TEST_NFT_3_ACCOUNT);
        (,,,,,,, uint128 liquidityBefore,,,,) = NPM.positions(TEST_NFT_3);

        assertEq(daiBefore, 14382879654257202832190);
        assertEq(usdcBefore, 754563026);
        assertEq(liquidityBefore, 12922419498089422291);

        vm.prank(TEST_NFT_3_ACCOUNT);
        NPM.safeTransferFrom(TEST_NFT_3_ACCOUNT, address(v3utils), TEST_NFT_3, abi.encode(inst));

        uint256 daiAfter = DAI.balanceOf(TEST_NFT_3_ACCOUNT);
        uint256 usdcAfter = USDC.balanceOf(TEST_NFT_3_ACCOUNT);
        (,,,,,,, uint128 liquidityAfter,,,,) = NPM.positions(TEST_NFT_3);

        assertEq(daiAfter, 14382879654257202838632);
        assertEq(usdcAfter, 806331571);
        assertEq(liquidityAfter, 13034529712992826193);
    }
  
    function test_RevertWhen_EmptySwapAndMint() external {
        V3Utils.SwapAndMintParams memory params = V3Utils.SwapAndMintParams(
            DAI,
            USDC,
            500,
            MIN_TICK_500,
            -MIN_TICK_500,
            0,
            0,
            TEST_NFT_ACCOUNT,
            TEST_NFT_ACCOUNT,
            block.timestamp,
            IERC20(address(0)),
            0,
            0,
            "",
            0,
            0,
            "",
            0,
            0,
            "",
            ""
        );

        vm.prank(TEST_NFT_ACCOUNT);
        vm.expectRevert(); // Add explicit expectRevert
        v3utils.swapAndMint(params);
    }

    function testSwapAndMintPermit2() public {
        // use newer fork which has permit2
          string memory ANKR_RPC = string.concat(
            "https://rpc.ankr.com/eth/",
            vm.envString("ANKR_API_KEY")
        );
        mainnetFork = vm.createFork(ANKR_RPC, 18521658);
        vm.selectFork(mainnetFork);
        v3utils = new V3Utils(NPM, EX0x, UNIVERSAL_ROUTER, PERMIT2);

        uint256 amountDAI = 1 ether;
        uint256 amountUSDC = 1000000;
        uint256 privateKey = 123;
        address addr = vm.addr(privateKey);

        // give coins
        vm.deal(addr, 1 ether);
        vm.prank(WHALE_ACCOUNT);
        USDC.transfer(addr, amountUSDC);

        vm.prank(DAI_WHALE_ACCOUNT);
        DAI.transfer(addr, amountDAI);

        vm.prank(addr);
        USDC.approve(PERMIT2, type(uint256).max);

        vm.prank(addr);
        DAI.approve(PERMIT2, type(uint256).max);

        ISignatureTransfer.TokenPermissions[] memory permissions = new ISignatureTransfer.TokenPermissions[](2);
        permissions[0] = ISignatureTransfer.TokenPermissions(address(DAI), amountDAI);
        permissions[1] = ISignatureTransfer.TokenPermissions(address(USDC), amountUSDC);

        ISignatureTransfer.PermitBatchTransferFrom memory tf =
            ISignatureTransfer.PermitBatchTransferFrom(permissions, 1, block.timestamp);

        bytes memory signature = _getPermitBatchTransferFromSignature(tf, privateKey, address(v3utils));
        bytes memory permitData = abi.encode(tf, signature);

        V3Utils.SwapAndMintParams memory params = V3Utils.SwapAndMintParams(
            DAI,
            USDC,
            500,
            MIN_TICK_500,
            -MIN_TICK_500,
            amountDAI,
            amountUSDC,
            addr,
            addr,
            block.timestamp,
            IERC20(address(0)),
            0,
            0,
            "",
            0,
            0,
            "",
            0,
            0,
            "",
            permitData
        );

        vm.prank(addr);
        (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1) = v3utils.swapAndMint(params);

        assertEq(tokenId, 599811);
        assertEq(liquidity, 999808574760);
        assertEq(amount0, 999617186163914918);
        assertEq(amount1, 1000000);
    }

    function testSwapDataError() public {
        V3Utils.SwapParams memory params = V3Utils.SwapParams(
            USDC,
            DAI,
            1000000, // 1 USDC
            1 ether, // 1 DAI
            TEST_NFT_ACCOUNT,
            _getInvalidSwapData(),
            false,
            ""
        );

        vm.startPrank(TEST_NFT_ACCOUNT);
        USDC.approve(address(v3utils), 1000000);

        vm.expectRevert();
        v3utils.swap(params);
        vm.stopPrank();
    }

    function _increaseLiquidity() internal returns (uint128 liquidity, uint256 amount0, uint256 amount1) {
        V3Utils.SwapAndIncreaseLiquidityParams memory params = V3Utils.SwapAndIncreaseLiquidityParams(
            TEST_NFT,
            1000000000000000000,
            0,
            TEST_NFT_ACCOUNT,
            block.timestamp,
            IERC20(address(0)),
            0, // no swap
            0,
            "",
            0, // no swap
            0,
            "",
            0,
            0,
            ""
        );

        uint256 balanceBefore = DAI.balanceOf(TEST_NFT_ACCOUNT);

        vm.startPrank(TEST_NFT_ACCOUNT);
        DAI.approve(address(v3utils), 1000000000000000000);
        (liquidity, amount0, amount1) = v3utils.swapAndIncreaseLiquidity(params);
        vm.stopPrank();

        uint256 balanceAfter = DAI.balanceOf(TEST_NFT_ACCOUNT);

        // uniswap sometimes adds not full balance (this tests that leftover tokens were returned correctly)
        assertEq(balanceBefore - balanceAfter, 999999999999999633);

        assertEq(liquidity, 2001002825163355);
        assertEq(amount0, 999999999999999633); // added amount
        assertEq(amount1, 0); // only added on one side

        uint256 balanceDAI = DAI.balanceOf(address(v3utils));
        uint256 balanceUSDC = USDC.balanceOf(address(v3utils));

        assertEq(balanceDAI, 0);
        assertEq(balanceUSDC, 0);
    }

    function _getInvalidSwapData() internal view returns (bytes memory) {
        return abi.encode(EX0x, hex"1234567890");
    }

    function _getPermitBatchTransferFromSignature(
        ISignatureTransfer.PermitBatchTransferFrom memory permit,
        uint256 privateKey,
        address to
    ) internal returns (bytes memory sig) {
        bytes32 _PERMIT_BATCH_TRANSFER_FROM_TYPEHASH = keccak256(
            "PermitBatchTransferFrom(TokenPermissions[] permitted,address spender,uint256 nonce,uint256 deadline)TokenPermissions(address token,uint256 amount)"
        );
        bytes32 _TOKEN_PERMISSIONS_TYPEHASH = keccak256("TokenPermissions(address token,uint256 amount)");
        bytes32[] memory tokenPermissions = new bytes32[](permit.permitted.length);
        for (uint256 i = 0; i < permit.permitted.length; ++i) {
            tokenPermissions[i] = keccak256(abi.encode(_TOKEN_PERMISSIONS_TYPEHASH, permit.permitted[i]));
        }

        bytes32 msgHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                IPermit2(PERMIT2).DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        _PERMIT_BATCH_TRANSFER_FROM_TYPEHASH,
                        keccak256(abi.encodePacked(tokenPermissions)),
                        to,
                        permit.nonce,
                        permit.deadline
                    )
                )
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, msgHash);
        return bytes.concat(r, s, bytes1(v));
    }
}

