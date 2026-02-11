// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import "./MockToken.sol";
import "../src/Interface.sol";
import "../src/Swap.sol";
import "../src/AssetFactory.sol";
import "../src/AssetIssuer.sol";
import "../src/StakeFactory.sol";
import "../src/StakeToken.sol";
import "../src/AssetLocking.sol";
import "../src/USSI.sol";

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {Test, console} from "forge-std/Test.sol";

contract StakingTest is Test {
    MockToken WBTC = new MockToken("Wrapped BTC", "WBTC", 8);
    MockToken WETH = new MockToken("Wrapped ETH", "WETH", 18);

    address owner = vm.addr(0x1);
    address vault = vm.addr(0x2);
    address pmm = vm.addr(0x3);
    address ap = vm.addr(0x4);
    address swap = vm.addr(0x5);
    address rebalancer = vm.addr(0x7);
    address feeManager = vm.addr(0x8);
    uint256 orderSignerPk = 0x9;
    address orderSigner = vm.addr(orderSignerPk);
    address staker = vm.addr(0x10);
    address hedger = vm.addr(0x10);

    AssetIssuer issuer;
    AssetToken assetToken;
    AssetFactory factory;
    StakeFactory stakeFactory;
    StakeToken stakeToken;
    AssetLocking assetLocking;
    USSI uSSI;

    uint256 stakeAmount = 1e8;

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

    function setUp() public {
        vm.startPrank(owner);
        AssetToken tokenImpl = new AssetToken();
        AssetFactory factoryImpl = new AssetFactory();
        address factoryAddress = address(new ERC1967Proxy(
            address(factoryImpl),
            abi.encodeCall(AssetFactory.initialize, (owner, vault, "SETH", address(tokenImpl)))
        ));
        factory = AssetFactory(factoryAddress);
        issuer = AssetIssuer(address(new ERC1967Proxy(
            address(new AssetIssuer()),
            abi.encodeCall(AssetController.initialize, (owner, address(factory)))
        )));
        address assetTokenAddress = factory.createAssetToken(getAsset(), 10000, address(issuer), rebalancer, feeManager, swap);
        assetToken = AssetToken(assetTokenAddress);
        StakeToken stakeTokenImpl = new StakeToken();
        StakeFactory stakeFactoryImpl = new StakeFactory();
        address stakeFactoryAddress = address(new ERC1967Proxy(
            address(stakeFactoryImpl),
            abi.encodeCall(StakeFactory.initialize, (owner, address(factory), address(stakeTokenImpl)))
        ));
        stakeFactory = StakeFactory(stakeFactoryAddress);
        assetLocking = AssetLocking(address(new ERC1967Proxy(
            address(new AssetLocking()),
            abi.encodeCall(AssetLocking.initialize, owner)
        )));
        uSSI = USSI(address(new ERC1967Proxy(
            address(new USSI()),
            abi.encodeCall(USSI.initialize, (owner, orderSigner, address(factory), address(WBTC), "SETH"))
        )));
        vm.stopPrank();
        vm.startPrank(address(issuer));
        assetToken.mint(staker, stakeAmount);
        vm.stopPrank();
    }

    function testStakeAndLock() public {
        // create stake token
        vm.startPrank(owner);
        stakeToken = StakeToken(stakeFactory.createStakeToken(assetToken.id(), 3600*24*7));
        assertEq(stakeToken.token(), address(assetToken));
        vm.stopPrank();
        // test pause
        vm.startPrank(owner);
        stakeFactory.pauseStakeToken(assetToken.id());
        vm.stopPrank();
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        stakeToken.stake(stakeAmount);
        vm.startPrank(owner);
        stakeFactory.unpauseStakeToken(assetToken.id());
        vm.stopPrank();
        // stake
        vm.startPrank(staker);
        assetToken.approve(address(stakeToken), stakeAmount * 10);
        stakeToken.stake(stakeAmount);
        vm.expectRevert();
        stakeToken.stake(1);
        vm.stopPrank();
        // check balance
        assertEq(assetToken.balanceOf(staker), 0);
        assertEq(stakeToken.balanceOf(staker), stakeAmount);
        assertEq(stakeToken.totalSupply(), stakeAmount);
        assertEq(assetToken.totalSupply(), stakeAmount);
        // unstake
        vm.startPrank(staker);
        uint256 unstakeAmount = stakeAmount * 50 / 100;
        stakeToken.unstake(unstakeAmount);
        vm.stopPrank();
        (uint256 cooldownAmount, uint256 cooldownEndTimestamp) = stakeToken.cooldownInfos(staker);
        assertEq(cooldownAmount, stakeAmount - cooldownAmount);
        assertEq(unstakeAmount, cooldownAmount);
        assertEq(cooldownEndTimestamp, block.timestamp + stakeToken.cooldown());
        // check balance
        assertEq(stakeToken.balanceOf(staker), stakeAmount - unstakeAmount);
        assertEq(stakeToken.totalSupply(), stakeAmount - unstakeAmount);
        assertEq(assetToken.totalSupply(), stakeAmount);
        // withdraw
        vm.startPrank(staker);
        vm.expectRevert();
        stakeToken.withdraw(cooldownAmount);
        vm.stopPrank();
        vm.warp(block.timestamp + stakeToken.cooldown());
        //// update cooldown
        vm.startPrank(owner);
        stakeFactory.updateCooldown(assetToken.id(), 3600*24*14);
        assertEq(stakeToken.cooldown(), 3600*24*14);
        vm.stopPrank();
        vm.startPrank(staker);
        stakeToken.withdraw(cooldownAmount);
        // check balance
        assertEq(assetToken.balanceOf(staker), unstakeAmount);
        assertEq(stakeToken.balanceOf(staker), stakeAmount - unstakeAmount);
        assertEq(stakeToken.totalSupply(), stakeAmount - unstakeAmount);
        assertEq(assetToken.totalSupply(), stakeAmount);
        // stake again to test new cooldown duration
        stakeToken.stake(unstakeAmount);
        stakeToken.unstake(unstakeAmount);
        vm.warp(block.timestamp + 3600*24*7);
        vm.expectRevert();
        stakeToken.withdraw(unstakeAmount);
        vm.warp(block.timestamp + 3600*24*7);
        stakeToken.withdraw(unstakeAmount);
        vm.stopPrank();
        // lock
        uint256 lockAmount = stakeAmount - unstakeAmount;
        // can not lock
        vm.startPrank(staker);
        vm.expectRevert();
        assetLocking.lock(address(stakeToken), lockAmount);
        vm.stopPrank();
        // owner update stake config
        vm.startPrank(owner);
        assetLocking.updateLockConfig(address(stakeToken), 0, lockAmount * 2, 7 days);
        vm.stopPrank();
        // can lock
        vm.startPrank(staker);
        stakeToken.approve(address(assetLocking), lockAmount);
        assetLocking.lock(address(stakeToken), lockAmount);
        vm.stopPrank();
        assertEq(stakeToken.balanceOf(staker), 0);
        assertEq(stakeToken.balanceOf(address(assetLocking)), lockAmount);
        uint256 amount;
        (amount, cooldownAmount, cooldownEndTimestamp) = assetLocking.lockDatas(address(stakeToken), staker);
        assertEq(amount, lockAmount);
        assertEq(cooldownAmount, 0);
        assertEq(cooldownEndTimestamp, 0);
        // unlock
        vm.startPrank(staker);
        vm.expectRevert();
        assetLocking.unlock(address(stakeToken), lockAmount + 1);
        assetLocking.unlock(address(stakeToken), lockAmount);
        vm.stopPrank();
        assertEq(stakeToken.balanceOf(staker), 0);
        assertEq(stakeToken.balanceOf(address(assetLocking)), lockAmount);
        (amount, cooldownAmount, cooldownEndTimestamp) = assetLocking.lockDatas(address(stakeToken), staker);
        (,,uint256 cooldown,,) = assetLocking.lockConfigs(address(stakeToken));
        assertEq(amount, 0);
        assertEq(cooldownAmount, lockAmount);
        assertEq(cooldownEndTimestamp, block.timestamp + cooldown);
        // withdraw
        vm.startPrank(staker);
        vm.expectRevert();
        assetLocking.withdraw(address(stakeToken), lockAmount);
        vm.warp(block.timestamp + cooldown);
        assetLocking.withdraw(address(stakeToken), lockAmount);
        vm.stopPrank();
        assertEq(stakeToken.balanceOf(staker), lockAmount);
        assertEq(stakeToken.balanceOf(address(assetLocking)), 0);
    }

    function testUSSI() public {
        // apply mint
        USSI.HedgeOrder memory mintOrder = USSI.HedgeOrder({
            chain: "SETH",
            orderType: USSI.HedgeOrderType.MINT,
            assetID: 1,
            redeemToken: address(0),
            nonce: 0,
            inAmount: stakeAmount,
            outAmount: stakeAmount * 10,
            deadline: block.timestamp + 600,
            requester: hedger,
            receiver: hedger
        });
        vm.startPrank(hedger);
        vm.expectRevert();
        uSSI.applyMint(mintOrder, new bytes(10));
        vm.stopPrank();
        vm.startPrank(owner);
        uSSI.grantRole(uSSI.PARTICIPANT_ROLE(), hedger);
        uSSI.addSupportAsset(1);
        vm.stopPrank();
        bytes32 orderHash = keccak256(abi.encode(mintOrder));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(orderSignerPk, orderHash);
        bytes memory orderSign = abi.encodePacked(r, s, v);
        vm.startPrank(hedger);
        assetToken.approve(address(uSSI), stakeAmount);
        uSSI.applyMint(mintOrder, orderSign);
        vm.stopPrank();
        // confirm mint
        vm.startPrank(owner);
        uSSI.confirmMint(orderHash);
        vm.stopPrank();
        assertEq(assetToken.balanceOf(hedger), 0);
        assertEq(uSSI.balanceOf(hedger), stakeAmount * 10);
        // apply redeem
        USSI.HedgeOrder memory redeemOrder = USSI.HedgeOrder({
            chain: "SETH",
            orderType: USSI.HedgeOrderType.REDEEM,
            assetID: 1,
            redeemToken: uSSI.redeemToken(),
            nonce: 1,
            inAmount: stakeAmount * 10,
            outAmount: stakeAmount,
            deadline: block.timestamp + 600,
            requester: hedger,
            receiver: hedger
        });
        orderHash = keccak256(abi.encode(redeemOrder));
        (v, r, s) = vm.sign(orderSignerPk, orderHash);
        orderSign = abi.encodePacked(r, s, v);
        vm.startPrank(hedger);
        uSSI.approve(address(uSSI), stakeAmount * 10);
        uSSI.applyRedeem(redeemOrder, orderSign);
        vm.stopPrank();
        // confirm redeem
        vm.startPrank(owner);
        vm.expectRevert();
        uSSI.confirmRedeem(orderHash, bytes32(0));
        WBTC.mint(owner, stakeAmount);
        WBTC.transfer(address(uSSI), stakeAmount);
        uSSI.confirmRedeem(orderHash, bytes32(uint256(1)));
        vm.stopPrank();
        assertEq(uSSI.balanceOf(hedger), 0);
        assertEq(WBTC.balanceOf(address(uSSI)), stakeAmount);
        assertEq(WBTC.balanceOf(hedger), 0);
    }
}