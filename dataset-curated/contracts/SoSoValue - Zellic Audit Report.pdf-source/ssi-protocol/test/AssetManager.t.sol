// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import "./MockToken.sol";
import "../src/Interface.sol";
import "../src/Swap.sol";
import "../src/AssetIssuer.sol";
import "../src/AssetRebalancer.sol";
import "../src/AssetFeeManager.sol";
import "../src/AssetFactory.sol";

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";


import {Test, console} from "forge-std/Test.sol";

contract FundManagerTest is Test {
    MockToken WBTC;
    MockToken WETH;

    address owner = vm.addr(0x1);
    address vault = vm.parseAddress("0xc9b6174bDF1deE9Ba42Af97855Da322b91755E63");
    address pmm = vm.addr(0x3);
    address ap = vm.addr(0x4);
    Swap swap;
    AssetIssuer issuer;
    AssetRebalancer rebalancer;
    AssetFeeManager feeManager;
    AssetFactory factory;
    AssetToken tokenImpl;
    AssetFactory factoryImpl;

    function setUp() public {
        WBTC = new MockToken("Wrapped BTC", "WBTC", 8);
        WETH = new MockToken("Wrapped ETH", "WETH", 18);
        vm.startPrank(owner);
        swap = Swap(address(new ERC1967Proxy(
            address(new Swap()),
            abi.encodeCall(Swap.initialize, (owner, "SETH")))
        ));
        tokenImpl = new AssetToken();
        factoryImpl = new AssetFactory();
        address factoryAddress = address(new ERC1967Proxy(
            address(factoryImpl),
            abi.encodeCall(AssetFactory.initialize, (owner, vault, "SETH", address(tokenImpl)))
        ));
        factory = AssetFactory(factoryAddress);
        issuer = AssetIssuer(address(new ERC1967Proxy(
            address(new AssetIssuer()),
            abi.encodeCall(AssetController.initialize, (owner, address(factory)))
        )));
        rebalancer = AssetRebalancer(address(new ERC1967Proxy(
            address(new AssetRebalancer()),
            abi.encodeCall(AssetController.initialize, (owner, address(factory)))
        )));
        feeManager = AssetFeeManager(address(new ERC1967Proxy(
            address(new AssetFeeManager()),
            abi.encodeCall(AssetController.initialize, (owner, address(factory)))
        )));
        swap.grantRole(swap.MAKER_ROLE(), pmm);
        swap.grantRole(swap.TAKER_ROLE(), address(issuer));
        swap.grantRole(swap.TAKER_ROLE(), address(rebalancer));
        swap.grantRole(swap.TAKER_ROLE(), address(feeManager));
        string[] memory outWhiteAddresses = new string[](2);
        outWhiteAddresses[0] = vm.toString(address(issuer));
        outWhiteAddresses[1] = vm.toString(vault);
        swap.setTakerAddresses(outWhiteAddresses, outWhiteAddresses);
        Token[] memory whiteListTokens = new Token[](2);
        whiteListTokens[0] = Token({
            chain: "SETH",
            symbol: WBTC.symbol(),
            addr: vm.toString(address(WBTC)),
            decimals: WBTC.decimals(),
            amount: 0
        });
        whiteListTokens[1] = Token({
            chain: "SETH",
            symbol: WETH.symbol(),
            addr: vm.toString(address(WETH)),
            decimals: WETH.decimals(),
            amount: 0
        });
        swap.addWhiteListTokens(whiteListTokens);
        vm.stopPrank();
    }

    function test_Sign() public view {
        address maker = 0xd1d1aDfD330B29D4ccF9E0d44E90c256Df597dc9;
        bytes32 orderHash = 0xd43e73902ff40548ac79fff32652e7e0a9af269dcbaf60999601fee4267797a8;
        bytes memory orderSign = hex"81542ef8cee89f0c5501db77e5c0836f367c06039de4454b529df8f63d347ae8083ef4b33cdea8b5defb799b154b6d1f1fa3baf88614ae8c2024cd2579f1b0371b";
        assertTrue(SignatureChecker.isValidSignatureNow(maker, orderHash, orderSign));
    }

    uint maxFee = 10000;
    function getAsset() public view returns (Asset memory) {
        Token[] memory tokenset_ = new Token[](1);
        tokenset_[0] = Token({
            chain: "SETH",
            symbol: WBTC.symbol(),
            addr: vm.toString(address(WBTC)),
            decimals: WBTC.decimals(),
            amount: 10 * 10 ** WBTC.decimals() / 60000
        });
        Asset memory asset = Asset({
            id: 1,
            name: "BTC",
            symbol: "BTC",
            tokenset: tokenset_
        });
        return asset;
    }

    function createAssetToken() public returns (address) {
        vm.startPrank(owner);
        address assetTokenAddress = factory.createAssetToken(getAsset(), maxFee, address(issuer), address(rebalancer), address(feeManager), address(swap));
        IAssetToken assetToken = IAssetToken(assetTokenAddress);
        issuer.setIssueFee(assetToken.id(), 10000);
        issuer.setIssueAmountRange(assetToken.id(), Range({min:10*10**8, max:10000*10**8}));
        issuer.addParticipant(assetToken.id(), ap);
        vm.stopPrank();
        return assetTokenAddress;
    }

    function pmmQuoteMint() public returns (OrderInfo memory) {
        vm.startPrank(pmm);
        Token[] memory inTokenset = new Token[](1);
        inTokenset[0] = Token({
            chain: "SETH",
            symbol: WETH.symbol(),
            addr: vm.toString(address(WETH)),
            decimals: WETH.decimals(),
            amount: 10 ** WETH.decimals()
        });
        Order memory order = Order({
            chain: "SETH",
            maker: pmm,
            nonce: 1,
            inTokenset: inTokenset,
            outTokenset: getAsset().tokenset,
            inAddressList: new string[](1),
            outAddressList: new string[](1),
            inAmount: 10 ** 8,
            outAmount: 3000 * 10 ** 8 / 10,
            deadline: vm.getBlockTimestamp() + 60,
            requester: ap
        });
        order.inAddressList[0] = vm.toString(pmm);
        order.outAddressList[0] = vm.toString(vault);
        bytes32 orderHash = keccak256(abi.encode(order));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0x3, orderHash);
        bytes memory orderSign = abi.encodePacked(r, s, v);
        OrderInfo memory orderInfo = OrderInfo({
            order: order,
            orderHash: orderHash,
            orderSign: orderSign
        });
        vm.stopPrank();
        return orderInfo;
    }

    function apAddMintRequest(address assetTokenAddress, OrderInfo memory orderInfo) public returns (uint, uint) {
        vm.startPrank(ap);
        IAssetToken assetToken = IAssetToken(assetTokenAddress);
        WETH.mint(ap, 10 ** WETH.decimals() * (10**8 + 10000) / 10**8);
        WETH.approve(address(issuer), 10 ** WETH.decimals() * (10**8 + 10000) / 10**8);
        uint amountBeforeMint = WETH.balanceOf(ap);
        uint nonce = issuer.addMintRequest(assetToken.id(), orderInfo, 10000);
        vm.stopPrank();
        return (nonce, amountBeforeMint);
    }

    function pmmConfirmSwapRequest(OrderInfo memory orderInfo, bool byContract) public {
        vm.startPrank(pmm);
        uint transferAmount = orderInfo.order.outTokenset[0].amount * orderInfo.order.outAmount / 10**8;
        MockToken token = MockToken(vm.parseAddress(orderInfo.order.outTokenset[0].addr));
        token.mint(pmm, transferAmount);
        if (!byContract) {
            token.transfer(vm.parseAddress(orderInfo.order.outAddressList[0]), transferAmount);
            bytes[] memory outTxHashs = new bytes[](1);
            outTxHashs[0] = 'outTxHashs';
            swap.makerConfirmSwapRequest(orderInfo, outTxHashs);
        } else {
            token.approve(address(swap), transferAmount);
            bytes[] memory outTxHashs = new bytes[](0);
            swap.makerConfirmSwapRequest(orderInfo, outTxHashs);
        }
        
    }

    function vaultConfirmSwap(OrderInfo memory orderInfo, uint256 beforeAmount, bool check) public {
        vm.startPrank(vault);
        if (check) {
            uint outAmount = orderInfo.order.outTokenset[0].amount * orderInfo.order.outAmount / 10**8;
            MockToken outToken = MockToken(vm.parseAddress(orderInfo.order.outTokenset[0].addr));
            vm.assertEq(outToken.balanceOf(vault), outAmount + beforeAmount);
        }
        uint inAmount = orderInfo.order.inTokenset[0].amount * orderInfo.order.inAmount / 10**8;
        MockToken inToken = MockToken(vm.parseAddress(orderInfo.order.inTokenset[0].addr));
        inToken.transfer(pmm, inAmount);
        vm.stopPrank();
    }

    function confirmMintRequest(uint nonce, OrderInfo memory orderInfo) public {
        vm.startPrank(owner);
        bytes[] memory inTxHashs = new bytes[](1);
        inTxHashs[0] = 'inTxHashs';
        issuer.confirmMintRequest(nonce, orderInfo, inTxHashs);
        vm.stopPrank();
    }

    function pmmQuoteRedeem() public returns (OrderInfo memory) {
        vm.startPrank(pmm);
        Token[] memory outTokenset = new Token[](1);
        outTokenset[0] = Token({
            chain: "SETH",
            symbol: WETH.symbol(),
            addr: vm.toString(address(WETH)),
            decimals: WETH.decimals(),
            amount: 10 ** WETH.decimals()
        });
        WETH.approve(address(swap), 10**WETH.decimals());
        Order memory order = Order({
            chain: "SETH",
            maker: pmm,
            nonce: 1,
            inTokenset: getAsset().tokenset,
            outTokenset: outTokenset,
            inAddressList: new string[](1),
            outAddressList: new string[](1),
            inAmount: 3000 * 10 ** 8 / 10,
            outAmount: 10 ** 8,
            deadline: vm.getBlockTimestamp() + 60,
            requester: ap
        });
        order.inAddressList[0] = vm.toString(pmm);
        order.outAddressList[0] = vm.toString(address(issuer));
        bytes32 orderHash = keccak256(abi.encode(order));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0x3, orderHash);
        bytes memory orderSign = abi.encodePacked(r, s, v);
        OrderInfo memory orderInfo = OrderInfo({
            order: order,
            orderHash: orderHash,
            orderSign: orderSign
        });
        vm.stopPrank();
        return orderInfo;
    }

    function apAddRedeemRequest(address assetTokenAddress, OrderInfo memory orderInfo) public returns (uint, uint) {
        vm.startPrank(ap);
        IAssetToken assetToken = IAssetToken(assetTokenAddress);
        assetToken.approve(address(issuer), orderInfo.order.inAmount);
        uint amountBeforeRedeem = assetToken.balanceOf(ap);
        uint nonce = issuer.addRedeemRequest(assetToken.id(), orderInfo, 10000);
        vm.stopPrank();
        return (nonce, amountBeforeRedeem);
    }

    function vaultTransferToIssuer(OrderInfo memory orderInfo) public returns (address) {
        vm.startPrank(vault);
        uint outAmount = orderInfo.order.outTokenset[0].amount * orderInfo.order.outAmount / 10**8;
        MockToken outToken = MockToken(vm.parseAddress(orderInfo.order.outTokenset[0].addr));
        outToken.transfer(address(issuer), outAmount);
        vm.stopPrank();
        return address(outToken);
    }

    function confirmRedeemRequest(uint nonce, OrderInfo memory orderInfo) public {
        vm.startPrank(owner);
        bytes[] memory inTxHashs = new bytes[](1);
        inTxHashs[0] = 'inTxHashs';
        issuer.confirmRedeemRequest(nonce, orderInfo, inTxHashs, false);
        vm.stopPrank();
    }

    function collectFeeTokenset(address assetTokenAddress) public {
        AssetToken assetToken = AssetToken(assetTokenAddress);
        Token[] memory basket = assetToken.getBasket();
        vm.startPrank(owner);
        vm.warp(vm.getBlockTimestamp() + 2 days);
        feeManager.collectFeeTokenset(assetToken.id());
        vm.stopPrank();
        uint firstDayAmount = basket[0].amount - basket[0].amount * assetToken.fee() / 10 ** assetToken.feeDecimals();
        uint sencodDayAmount = firstDayAmount - firstDayAmount * assetToken.fee() / 10 ** assetToken.feeDecimals();
        uint feeAmount = 0;
        feeAmount += basket[0].amount * assetToken.fee() / 10 ** assetToken.feeDecimals();
        feeAmount += firstDayAmount * assetToken.fee() / 10 ** assetToken.feeDecimals();
        assertEq(assetToken.getBasket()[0].amount, sencodDayAmount);
        assertEq(assetToken.getFeeTokenset()[0].amount, feeAmount);
        assertEq(assetToken.getTokenset()[0].amount, sencodDayAmount * 10**assetToken.decimals() / assetToken.totalSupply());
    }

    function pmmQuoteBurn(address assetTokenAddress) public returns (OrderInfo memory) {
        AssetToken assetToken = AssetToken(assetTokenAddress);
        Token[] memory inTokenset = assetToken.getFeeTokenset();
        vm.startPrank(pmm);
        Token[] memory outTokenset = new Token[](1);
        outTokenset[0] = Token({
            chain: "SETH",
            symbol: WETH.symbol(),
            addr: vm.toString(address(WETH)),
            decimals: WETH.decimals(),
            amount: 10 ** WETH.decimals()
        });
        Order memory order = Order({
            chain: "SETH",
            maker: pmm,
            nonce: 1,
            inTokenset: inTokenset,
            outTokenset: outTokenset,
            inAddressList: new string[](1),
            outAddressList: new string[](1),
            inAmount: 10 ** 8,
            outAmount: 60000 * inTokenset[0].amount / 3000,
            deadline: vm.getBlockTimestamp() + 60,
            requester: ap
        });
        order.inAddressList[0] = vm.toString(pmm);
        order.outAddressList[0] = vm.toString(vault);
        bytes32 orderHash = keccak256(abi.encode(order));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0x3, orderHash);
        bytes memory orderSign = abi.encodePacked(r, s, v);
        OrderInfo memory orderInfo = OrderInfo({
            order: order,
            orderHash: orderHash,
            orderSign: orderSign
        });
        vm.stopPrank();
        return orderInfo;
    }

    function addBurnFeeRequest(address assetTokenAddress, OrderInfo memory orderInfo) public returns (uint) {
        vm.startPrank(owner);
        IAssetToken assetToken = IAssetToken(assetTokenAddress);
        uint nonce = feeManager.addBurnFeeRequest(assetToken.id(), orderInfo);
        vm.stopPrank();
        return nonce;
    }

    function confirmBurnFeeRequest(uint nonce, OrderInfo memory orderInfo) public {
        vm.startPrank(owner);
        bytes[] memory inTxHashs = new bytes[](1);
        inTxHashs[0] = 'inTxHashs';
        feeManager.confirmBurnFeeRequest(nonce, orderInfo, inTxHashs);
        vm.stopPrank();
    }

    function pmmQuoteRebalance(address assetTokenAddress) public returns (OrderInfo memory) {
        vm.startPrank(pmm);
        AssetToken assetToken = AssetToken(assetTokenAddress);
        Token[] memory outTokenset = new Token[](1);
        outTokenset[0] = Token({
            chain: "SETH",
            symbol: WETH.symbol(),
            addr: vm.toString(address(WETH)),
            decimals: WETH.decimals(),
            amount: 10 ** WETH.decimals()
        });
        Order memory order = Order({
            chain: "SETH",
            maker: pmm,
            nonce: 1,
            inTokenset: assetToken.getBasket(),
            outTokenset: outTokenset,
            inAddressList: new string[](1),
            outAddressList: new string[](1),
            inAmount: 10 ** 8,
            outAmount: assetToken.getBasket()[0].amount * 60000 / 3000,
            deadline: vm.getBlockTimestamp() + 60,
            requester: ap
        });
        order.inAddressList[0] = vm.toString(pmm);
        order.outAddressList[0] = vm.toString(vault);
        bytes32 orderHash = keccak256(abi.encode(order));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0x3, orderHash);
        bytes memory orderSign = abi.encodePacked(r, s, v);
        OrderInfo memory orderInfo = OrderInfo({
            order: order,
            orderHash: orderHash,
            orderSign: orderSign
        });
        vm.stopPrank();
        return orderInfo;
    }

    function addRebalanceRequest(address assetTokenAddress, OrderInfo memory orderInfo) public returns (uint) {
        vm.startPrank(owner);
        AssetToken assetToken = AssetToken(assetTokenAddress);
        uint nonce = rebalancer.addRebalanceRequest(assetToken.id(), assetToken.getBasket(), orderInfo);
        vm.stopPrank();
        return nonce;
    }

    function confirmRebalanceRequest(uint nonce, OrderInfo memory orderInfo) public {
        vm.startPrank(owner);
        bytes[] memory inTxHashs = new bytes[](1);
        inTxHashs[0] = 'inTxHashs';
        rebalancer.confirmRebalanceRequest(nonce, orderInfo, inTxHashs);
        vm.stopPrank();
    }

    function test_CreateAssetToken() public {
        address assetTokenAddress = createAssetToken();
        IAssetToken assetToken = IAssetToken(assetTokenAddress);
        assertEq(factory.getAssetIDs().length, 1);
        assertEq(factory.assetTokens(factory.getAssetIDs()[0]), assetTokenAddress);
        assertEq(issuer.getIssueFee(assetToken.id()), 10000);
        assertEq(abi.encode(issuer.getIssueAmountRange(assetToken.id())), abi.encode(Range({min:10*10**8, max:10000*10**8})));
    }

    function test_Mint() public returns (address) {
        address assetTokenAddress = createAssetToken();
        OrderInfo memory orderInfo = pmmQuoteMint();
        (uint nonce, ) = apAddMintRequest(assetTokenAddress, orderInfo);
        // uint256 beforeAmount = IERC20(vm.parseAddress(orderInfo.order.outTokenset[0].addr)).balanceOf(vault);
        pmmConfirmSwapRequest(orderInfo, false);
        // vaultConfirmSwap(orderInfo, beforeAmount);
        confirmMintRequest(nonce, orderInfo);
        assertEq(IERC20(assetTokenAddress).balanceOf(ap), orderInfo.order.outAmount);
        assertEq(AssetToken(assetTokenAddress).getBasket()[0].amount, orderInfo.order.outTokenset[0].amount * orderInfo.order.outAmount / 10 ** 8);
        return assetTokenAddress;
    }

    function test_Redeem() public {
        address assetTokenAddress = test_Mint();
        OrderInfo memory orderInfo = pmmQuoteRedeem();
        (uint nonce, ) = apAddRedeemRequest(assetTokenAddress, orderInfo);
        uint256 beforeAmount = IERC20(vm.parseAddress(orderInfo.order.outTokenset[0].addr)).balanceOf(vault);
        pmmConfirmSwapRequest(orderInfo, true);
        vaultConfirmSwap(orderInfo, beforeAmount, false);
        // address outTokenAddress = vaultTransferToIssuer(orderInfo);
        address outTokenAddress = vm.parseAddress(orderInfo.order.outTokenset[0].addr);
        confirmRedeemRequest(nonce, orderInfo);
        MockToken outToken = MockToken(outTokenAddress);
        assertEq(IERC20(assetTokenAddress).balanceOf(ap), 0);
        uint256 expectAmount = orderInfo.order.outTokenset[0].amount * orderInfo.order.outAmount / 10 ** 8;
        assertEq(outToken.balanceOf(ap), expectAmount - expectAmount * 10000 / 10**8);
    }

    function test_BurnFee() public {
        address assetTokenAddress = test_Mint();
        AssetToken assetToken = AssetToken(assetTokenAddress);
        collectFeeTokenset(assetTokenAddress);
        assertEq(assetToken.getFeeTokenset().length, 1);
        OrderInfo memory orderInfo = pmmQuoteBurn(assetTokenAddress);
        uint nonce = addBurnFeeRequest(assetTokenAddress, orderInfo);
        uint256 beforeAmount = IERC20(vm.parseAddress(orderInfo.order.outTokenset[0].addr)).balanceOf(vault);
        pmmConfirmSwapRequest(orderInfo, true);
        vaultConfirmSwap(orderInfo, beforeAmount, false);
        confirmBurnFeeRequest(nonce, orderInfo);
        assertEq(assetToken.getFeeTokenset().length, 0);
        assertEq(IERC20(vm.parseAddress(orderInfo.order.outTokenset[0].addr)).balanceOf(vault),
                 beforeAmount + orderInfo.order.outTokenset[0].amount * orderInfo.order.outAmount / 10**8);
    }

    function test_Rebalance() public {
        address assetTokenAddress = test_Mint();
        AssetToken assetToken = AssetToken(assetTokenAddress);
        OrderInfo memory orderInfo = pmmQuoteRebalance(assetTokenAddress);
        uint nonce = addRebalanceRequest(assetTokenAddress, orderInfo);
        uint256 beforeAmount = IERC20(vm.parseAddress(orderInfo.order.outTokenset[0].addr)).balanceOf(vault);
        pmmConfirmSwapRequest(orderInfo, false);
        vaultConfirmSwap(orderInfo, beforeAmount, true);
        confirmRebalanceRequest(nonce, orderInfo);
        assertEq(assetToken.getBasket()[0].symbol, orderInfo.order.outTokenset[0].symbol);
        assertEq(assetToken.getBasket()[0].amount, orderInfo.order.outTokenset[0].amount * orderInfo.order.outAmount / 10**8);
        assertEq(assetToken.getBasket()[0].amount, assetToken.getTokenset()[0].amount * assetToken.totalSupply() / 10 ** 8);
        assertEq(assetToken.getBasket()[0].amount, IERC20(vm.parseAddress(assetToken.getBasket()[0].addr)).balanceOf(vault) - beforeAmount);
    }

    function test_PauseIssuer() public {
        address assetTokenAddress = createAssetToken();
        IAssetToken assetToken = IAssetToken(assetTokenAddress);
        OrderInfo memory orderInfo = pmmQuoteMint();
        vm.startPrank(owner);
        assertEq(issuer.paused(), false);
        issuer.pause();
        assertEq(issuer.paused(), true);
        vm.stopPrank();
        vm.startPrank(ap);
        WETH.mint(ap, 10 ** WETH.decimals());
        WETH.approve(address(issuer), 10 ** WETH.decimals());
        uint256 assetID = assetToken.id();
        vm.expectRevert();
        issuer.addMintRequest(assetID, orderInfo, 10000);
        vm.stopPrank();
    }

    function test_RejectMint() public {
        address assetTokenAddress = createAssetToken();
        OrderInfo memory orderInfo = pmmQuoteMint();
        IERC20 inToken = IERC20(vm.parseAddress(orderInfo.order.inTokenset[0].addr));
        (uint nonce, uint amountBeforeMint) = apAddMintRequest(assetTokenAddress, orderInfo);
        Request memory mintRequest = issuer.getMintRequest(nonce);
        vm.startPrank(pmm);
        swap.makerRejectSwapRequest(orderInfo);
        vm.stopPrank();
        // vm.startPrank(vault);
        // uint tokenAmount = orderInfo.order.inTokenset[0].amount * orderInfo.order.inAmount / 10**8;
        // uint feeAmount = tokenAmount * 10000 / 10**8;
        // inToken.transfer(address(issuer), tokenAmount + feeAmount);
        // vm.stopPrank();
        vm.startPrank(owner);
        issuer.rejectMintRequest(nonce, orderInfo, false);
        assertEq(inToken.balanceOf(ap), amountBeforeMint);
        assertTrue(issuer.getMintRequest(nonce).status == RequestStatus.REJECTED);
        assertTrue(swap.getSwapRequest(mintRequest.orderHash).status == SwapRequestStatus.REJECTED);
    }

    function test_RejectRedeem() public {
        address assetTokenAddress = test_Mint();
        OrderInfo memory orderInfo = pmmQuoteRedeem();
        (uint nonce, uint amountBeforeRedeem) = apAddRedeemRequest(assetTokenAddress, orderInfo);
        Request memory redeemRequest = issuer.getRedeemRequest(nonce);
        vm.startPrank(pmm);
        swap.makerRejectSwapRequest(orderInfo);
        vm.stopPrank();
        vm.startPrank(owner);
        issuer.rejectRedeemRequest(nonce);
        assertEq(IERC20(assetTokenAddress).balanceOf(ap), amountBeforeRedeem);
        assertTrue(issuer.getRedeemRequest(nonce).status == RequestStatus.REJECTED);
        assertTrue(swap.getSwapRequest(redeemRequest.orderHash).status == SwapRequestStatus.REJECTED);
    }

    function test_RejectRebalance() public {
        address assetTokenAddress = test_Mint();
        AssetToken assetToken = AssetToken(assetTokenAddress);
        OrderInfo memory orderInfo = pmmQuoteRebalance(assetTokenAddress);
        Token[] memory basket = assetToken.getBasket();
        Token[] memory tokenset = assetToken.getTokenset();
        uint256 vaultBeforeAmount = IERC20(vm.parseAddress(basket[0].addr)).balanceOf(vault);
        uint256 apBeforeAmount = assetToken.balanceOf(ap);
        uint nonce = addRebalanceRequest(assetTokenAddress, orderInfo);
        Request memory rebalanceRequest = rebalancer.getRebalanceRequest(nonce);
        vm.startPrank(pmm);
        swap.makerRejectSwapRequest(orderInfo);
        vm.stopPrank();
        vm.startPrank(owner);
        rebalancer.rejectRebalanceRequest(nonce);
        vm.stopPrank();
        assertEq(keccak256(abi.encode(assetToken.getBasket())), keccak256(abi.encode(basket)));
        assertEq(keccak256(abi.encode(assetToken.getTokenset())), keccak256(abi.encode(tokenset)));
        assertEq(apBeforeAmount, assetToken.balanceOf(ap));
        assertEq(vaultBeforeAmount, IERC20(vm.parseAddress(assetToken.getBasket()[0].addr)).balanceOf(vault));
        assertTrue(rebalancer.getRebalanceRequest(nonce).status == RequestStatus.REJECTED);
        assertTrue(swap.getSwapRequest(rebalanceRequest.orderHash).status == SwapRequestStatus.REJECTED);
    }

    function test_RejectBurnFee() public {
        address assetTokenAddress = test_Mint();
        AssetToken assetToken = AssetToken(assetTokenAddress);
        collectFeeTokenset(assetTokenAddress);
        assertEq(assetToken.getFeeTokenset().length, 1);
        OrderInfo memory orderInfo = pmmQuoteBurn(assetTokenAddress);
        Token[] memory feeTokenset = assetToken.getFeeTokenset();
        uint256 vaultBeforeAmount = IERC20(vm.parseAddress(feeTokenset[0].addr)).balanceOf(vault);
        uint nonce = addBurnFeeRequest(assetTokenAddress, orderInfo);
        Request memory burnFeeRequest = feeManager.getBurnFeeRequest(nonce);
        vm.startPrank(pmm);
        swap.makerRejectSwapRequest(orderInfo);
        vm.stopPrank();
        vm.startPrank(owner);
        feeManager.rejectBurnFeeRequest(nonce);
        vm.stopPrank();
        assertEq(keccak256(abi.encode(assetToken.getFeeTokenset())), keccak256(abi.encode(feeTokenset)));
        assertEq(vaultBeforeAmount, IERC20(vm.parseAddress(feeTokenset[0].addr)).balanceOf(vault));
        assertTrue(feeManager.getBurnFeeRequest(nonce).status == RequestStatus.REJECTED);
        assertTrue(swap.getSwapRequest(burnFeeRequest.orderHash).status == SwapRequestStatus.REJECTED);
    }

    function test_MintRange() public {
        address assetTokenAddress = createAssetToken();
        IAssetToken assetToken = IAssetToken(assetTokenAddress);
        OrderInfo memory orderInfo = pmmQuoteMint();
        WETH.mint(ap, 10 ** WETH.decimals() * (10**8 + 10000) / 10**8);
        WETH.approve(address(issuer), 10 ** WETH.decimals() * (10**8 + 10000) / 10**8);
        uint256 assetID = assetToken.id();
        vm.startPrank(owner);
        issuer.setIssueAmountRange(assetID, Range({
            min: 400 * 10**8,
            max: 10000 * 10**8
        }));
        vm.stopPrank();
        vm.startPrank(ap);
        vm.expectRevert(bytes("mint amount not in range"));
        issuer.addMintRequest(assetID, orderInfo, 10000);
        vm.stopPrank();
        vm.startPrank(owner);
        issuer.setIssueAmountRange(assetID, Range({
            min: 100 * 10**8,
            max: 200 * 10**8
        }));
        vm.stopPrank();
        vm.startPrank(ap);
        vm.expectRevert(bytes("mint amount not in range"));
        issuer.addMintRequest(assetID, orderInfo, 10000);
        vm.stopPrank();
    }

    function test_RedeemRange() public {
        address assetTokenAddress = test_Mint();
        AssetToken assetToken = AssetToken(assetTokenAddress);
        OrderInfo memory orderInfo = pmmQuoteRedeem();
        vm.startPrank(ap);
        assetToken.approve(address(issuer), orderInfo.order.inAmount);
        vm.stopPrank();
        uint256 assetID = assetToken.id();
        vm.startPrank(owner);
        issuer.setIssueAmountRange(assetID, Range({
            min: 400 * 10**8,
            max: 10000 * 10**8
        }));
        vm.stopPrank();
        vm.startPrank(ap);
        vm.expectRevert(bytes("redeem amount not in range"));
        issuer.addRedeemRequest(assetID, orderInfo, 10000);
        vm.stopPrank();
        vm.startPrank(owner);
        issuer.setIssueAmountRange(assetID, Range({
            min: 100 * 10**8,
            max: 200 * 10**8
        }));
        vm.stopPrank();
        vm.startPrank(ap);
        vm.expectRevert(bytes("redeem amount not in range"));
        issuer.addRedeemRequest(assetID, orderInfo, 10000);
        vm.stopPrank();
    }

    function test_RebalanceV2() public {
        Token[] memory tokenset_ = new Token[](2);
        tokenset_[0] = Token({
            chain: "TBSC_BNB",
            symbol: "TBSC_BNB",
            addr: "",
            decimals: 18,
            amount: 1412368749000018
        });
        tokenset_[1] = Token({
            chain: "SETH",
            symbol: "SETH",
            addr: "",
            decimals: 18,
            amount: 8379981918000000
        });
        Asset memory asset = Asset({
            id: 1,
            name: "ETHBNB",
            symbol: "ETHBNB",
            tokenset: tokenset_
        });
        maxFee = 10000;
        vm.startPrank(owner);
        Token[] memory whiteListTokens = new Token[](2);
        whiteListTokens[0] = Token({
            chain: "TBSC_BNB",
            symbol: "TBSC_BNB",
            addr: "",
            decimals: 18,
            amount: 0
        });
        whiteListTokens[1] = Token({
            chain: "SETH",
            symbol: "SETH",
            addr: "",
            decimals: 18,
            amount: 0
        });
        swap.addWhiteListTokens(whiteListTokens);
        address assetTokenAddress = factory.createAssetToken(asset, maxFee, address(issuer), address(rebalancer), address(feeManager), address(swap));
        AssetToken assetToken = AssetToken(assetTokenAddress);
        issuer.setIssueFee(assetToken.id(), 10000);
        issuer.setIssueAmountRange(assetToken.id(), Range({min:10*10**8, max:10000*10**8}));
        vm.stopPrank();
        vm.startPrank(address(issuer));
        assetToken.mint(owner, 3313411);
        vm.stopPrank();
        string[] memory inAddressList = new string[](1);
        inAddressList[0] = "0xd1d1aDfD330B29D4ccF9E0d44E90c256Df597dc9";
        string[] memory outAddressList = new string[](1);
        outAddressList[0] = "0xc9b6174bDF1deE9Ba42Af97855Da322b91755E63";
        Token[] memory inTokenset = new Token[](1);
        inTokenset[0] = Token({
            chain: "SETH",
            symbol: "SETH",
            addr: "",
            decimals: 18,
            amount: 134694404446823
        });
        Token[] memory outTokenset = new Token[](1);
        outTokenset[0] = Token({
            chain: "TBSC_BNB",
            symbol: "TBSC_BNB",
            addr: "",
            decimals: 18,
            amount: 800375696545671
        });
        Order memory order = Order({
            chain: "SETH",
            maker: pmm,
            nonce: 1719484311801267893,
            inTokenset: inTokenset,
            outTokenset: outTokenset,
            inAddressList: inAddressList,
            outAddressList: outAddressList,
            inAmount: 100000000,
            outAmount: 98168567,
            deadline: block.timestamp + 60,
            requester: ap
        });
        bytes32 orderHash = keccak256(abi.encode(order));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0x3, orderHash);
        bytes memory orderSign = abi.encodePacked(r, s, v);
        OrderInfo memory orderInfo = OrderInfo({
            order: order,
            orderHash: orderHash,
            orderSign: orderSign
        });
        vm.startPrank(owner);
        swap.grantRole(swap.MAKER_ROLE(), 0xd1d1aDfD330B29D4ccF9E0d44E90c256Df597dc9);
        rebalancer.addRebalanceRequest(assetToken.id(), assetToken.getBasket(), orderInfo);
        vm.stopPrank();
    }

    function test_SwapTakerAddress() public {
        vm.startPrank(owner);
        string[] memory receiverAddressList = new string[](2);
        receiverAddressList[0] = "0xc9b6174bDF1deE9Ba42Af97855Da322b91755E63";
        receiverAddressList[1] = "0xe224fb2f5557a869e66d13a709093de8cdf99129";
        string[] memory senderAddressList = new string[](2);
        senderAddressList[0] = "0xe224fb2f5557a869e66d13a709093de8cdf99129";
        senderAddressList[1] = "0xc9b6174bDF1deE9Ba42Af97855Da322b91755E63";
        swap.setTakerAddresses(receiverAddressList, senderAddressList);
        (string[] memory receivers, string[] memory senders) = swap.getTakerAddresses();
        assertEq(abi.encode(receiverAddressList), abi.encode(receivers));
        assertEq(abi.encode(senderAddressList), abi.encode(senders));
    }

    function test_Swap() public {
        OrderInfo memory orderInfo = pmmQuoteMint();
        vm.startPrank(address(issuer));
        swap.addSwapRequest(orderInfo, false, false);
        vm.stopPrank();
    }

    function test_rollback() public {
        address assetTokenAddress = createAssetToken();
        OrderInfo memory orderInfo = pmmQuoteMint();
        apAddMintRequest(assetTokenAddress, orderInfo);
        vm.startPrank(pmm);
        bytes[] memory outTxHashs = new bytes[](1);
        outTxHashs[0] = "outTxhash";
        swap.makerConfirmSwapRequest(orderInfo, outTxHashs);
        vm.stopPrank();
        vm.startPrank(owner);
        issuer.rollbackSwapRequest(address(swap), orderInfo);
        vm.stopPrank();
        SwapRequest memory swapRequest = swap.getSwapRequest(orderInfo.orderHash);
        assertTrue(swapRequest.status == SwapRequestStatus.PENDING);
    }

    function test_cancel() public {
        address assetTokenAddress = createAssetToken();
        OrderInfo memory orderInfo = pmmQuoteMint();
        IERC20 inToken = IERC20(vm.parseAddress(orderInfo.order.inTokenset[0].addr));
        (uint nonce, uint amountBeforeMint) = apAddMintRequest(assetTokenAddress, orderInfo);
        vm.startPrank(owner);
        vm.expectRevert();
        issuer.cancelSwapRequest(address(swap), orderInfo);
        vm.stopPrank();
        vm.startPrank(owner);
        vm.warp(block.timestamp + 1 hours);
        issuer.cancelSwapRequest(address(swap), orderInfo);
        vm.stopPrank();
        SwapRequest memory swapRequest = swap.getSwapRequest(orderInfo.orderHash);
        assertTrue(swapRequest.status == SwapRequestStatus.CANCEL);
        vm.startPrank(owner);
        issuer.rejectMintRequest(nonce, orderInfo, false);
        assertEq(inToken.balanceOf(ap), amountBeforeMint);
        assertTrue(issuer.getMintRequest(nonce).status == RequestStatus.REJECTED);
    }

    function test_withdraw() public {
        WETH.mint(owner, 10**18);
        vm.startPrank(owner);
        WETH.transfer(address(issuer), 10**18);
        address[] memory tokenAddresses = new address[](2);
        tokenAddresses[0] = address(WETH);
        tokenAddresses[1] = address(0);
        issuer.withdraw(tokenAddresses);
        assertEq(WETH.balanceOf(owner), 10**18);
        vm.stopPrank();
        address assetTokenAddress = createAssetToken();
        OrderInfo memory orderInfo = pmmQuoteMint();
        (uint nonce,) = apAddMintRequest(assetTokenAddress, orderInfo);
        vm.startPrank(owner);
        WETH.transfer(address(issuer), 10**18);
        vm.expectRevert();
        issuer.withdraw(tokenAddresses);
        vm.stopPrank();
        vm.startPrank(pmm);
        swap.makerRejectSwapRequest(orderInfo);
        vm.stopPrank();
        vm.startPrank(owner);
        issuer.rejectMintRequest(nonce, orderInfo, false);
        issuer.withdraw(tokenAddresses);
        assertEq(WETH.balanceOf(owner), 10**18);
    }

    function test_BurnFor() public {
        address tokenAddress = test_Mint();
        IAssetToken token = IAssetToken(tokenAddress);
        vm.startPrank(ap);
        token.approve(address(issuer), token.balanceOf(ap));
        issuer.burnFor(token.id(), token.balanceOf(ap));
        vm.stopPrank();
        assertEq(token.balanceOf(ap), 0);
        assertEq(token.balanceOf(address(issuer)), 0);
        Token[] memory tokens = token.getBasket();
        assertEq(tokens.length, 0);
    }

    function test_forceConfirmRedeemRequest() public {
        address assetTokenAddress = test_Mint();
        OrderInfo memory orderInfo = pmmQuoteRedeem();
        (uint nonce, ) = apAddRedeemRequest(assetTokenAddress, orderInfo);
        uint256 beforeAmount = IERC20(vm.parseAddress(orderInfo.order.outTokenset[0].addr)).balanceOf(vault);
        pmmConfirmSwapRequest(orderInfo, true);
        vaultConfirmSwap(orderInfo, beforeAmount, false);
        address outTokenAddress = vm.parseAddress(orderInfo.order.outTokenset[0].addr);
        MockToken outToken = MockToken(outTokenAddress);
        outToken.blockAccount(ap, true);
        vm.startPrank(owner);
        bytes[] memory inTxHashs = new bytes[](1);
        inTxHashs[0] = 'inTxHashs';
        vm.expectRevert();
        issuer.confirmRedeemRequest(nonce, orderInfo, inTxHashs, false);
        issuer.confirmRedeemRequest(nonce, orderInfo, inTxHashs, true);
        vm.stopPrank();
        assertEq(IERC20(assetTokenAddress).balanceOf(ap), 0);
        uint256 expectAmount = orderInfo.order.outTokenset[0].amount * orderInfo.order.outAmount / 10 ** 8;
        assertEq(outToken.balanceOf(ap), 0);
        vm.startPrank(owner);
        address[] memory withdrawTokens = new address[](1);
        withdrawTokens[0] = outTokenAddress;
        issuer.withdraw(withdrawTokens);
        vm.stopPrank();
        outToken.blockAccount(ap, false);
        vm.startPrank(ap);
        issuer.claim(outTokenAddress);
        assertEq(outToken.balanceOf(ap), expectAmount - expectAmount * 10000 / 10**8);
        vm.stopPrank();
    }

    function test_forceRejectMintRequest() public {
        address assetTokenAddress = createAssetToken();
        OrderInfo memory orderInfo = pmmQuoteMint();
        MockToken inToken = MockToken(vm.parseAddress(orderInfo.order.inTokenset[0].addr));
        (uint nonce, uint amountBeforeMint) = apAddMintRequest(assetTokenAddress, orderInfo);
        uint amountAfterMint = inToken.balanceOf(ap);
        Request memory mintRequest = issuer.getMintRequest(nonce);
        vm.startPrank(pmm);
        swap.makerRejectSwapRequest(orderInfo);
        vm.stopPrank();
        inToken.blockAccount(ap, true);
        vm.startPrank(owner);
        vm.expectRevert();
        issuer.rejectMintRequest(nonce, orderInfo, false);
        issuer.rejectMintRequest(nonce, orderInfo, true);
        assertEq(inToken.balanceOf(ap), amountAfterMint);
        assertTrue(issuer.getMintRequest(nonce).status == RequestStatus.REJECTED);
        assertTrue(swap.getSwapRequest(mintRequest.orderHash).status == SwapRequestStatus.REJECTED);
        address[] memory withdrawTokens = new address[](1);
        withdrawTokens[0] = address(inToken);
        issuer.withdraw(withdrawTokens);
        vm.stopPrank();
        inToken.blockAccount(ap, false);
        vm.startPrank(ap);
        issuer.claim(address(inToken));
        assertEq(inToken.balanceOf(ap), amountBeforeMint);
        vm.stopPrank();
    }

    function test_removeWhiteListTokens() public {
        assertEq(swap.getWhiteListTokens().length, 2);
        Token[] memory whiteListTokens = new Token[](1);
        whiteListTokens[0] = Token({
            chain: "SETH",
            symbol: WBTC.symbol(),
            addr: vm.toString(address(WBTC)),
            decimals: WBTC.decimals(),
            amount: 0
        });
        vm.startPrank(owner);
        swap.removeWhiteListTokens(whiteListTokens);
        vm.stopPrank();
        assertEq(swap.getWhiteListTokens().length, 1);
    }
}