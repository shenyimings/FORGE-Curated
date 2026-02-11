// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {packedFloat, MathLibs} from "src/amm/mathLibs/MathLibs.sol";
import "src/common/IErrors.sol";
import "src/common/IEvents.sol";
import {TestCommonSetup, LPToken} from "test/util/TestCommonSetup.sol";

abstract contract LPTokenTest is TestCommonSetup {
    using MathLibs for packedFloat;
    using MathLibs for int256;
    address mockFactory = address(0xfac);
    address mockPool1 = address(0xf00101);
    address mockPool2 = address(0xf00102);
    address mockNewFactory = address(0xBabe);
    address mockMaliciousFactory = address(0xB0b);
    address mockMaliciousPool = address(0xC0C0);
    address cade = address(0xCade);
    string mockPoolName = "ABC / DEF";
    function setUp() public startAsAdmin {
        vm.expectEmit(true, true, true, true);
        emit ILPTokenEvents.ALTBCPositionTokenDeployed();
        _deployLPToken();
    }

    function testLPToken_proposeFactoryAddress() public {
        // test zero address
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector));
        lpToken.proposeFactoryAddress(address(0));
        // test not owner
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", mockMaliciousFactory));
        vm.startPrank(mockMaliciousFactory);
        lpToken.proposeFactoryAddress(mockNewFactory);
        // test not proposed factory
        vm.startPrank(admin);
        lpToken.proposeFactoryAddress(mockNewFactory);
        vm.expectRevert(abi.encodeWithSignature("NotProposedFactory(address)", mockNewFactory));
        vm.startPrank(mockMaliciousFactory);
        lpToken.confirmFactoryAddress();
        // test positive case
        vm.startPrank(mockNewFactory);
        lpToken.confirmFactoryAddress();
        assertEq(lpToken.factoryAddress(), mockNewFactory);
    }

    function testLPToken_addPoolToAllowList() public {
        // setup
        lpToken.proposeFactoryAddress(mockFactory);
        vm.startPrank(mockFactory);
        lpToken.confirmFactoryAddress();
        vm.startPrank(mockFactory);
        // test zero address
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector));
        lpToken.addPoolToAllowList(address(0));
        // test positive case
        lpToken.addPoolToAllowList(mockPool1);
        // test pool already allowed
        vm.expectRevert(abi.encodeWithSelector(PoolAlreadyAllowed.selector));
        lpToken.addPoolToAllowList(mockPool1);
        // test not factory
        vm.startPrank(mockMaliciousFactory);
        vm.expectRevert(abi.encodeWithSelector(NotFactory.selector));
        lpToken.addPoolToAllowList(mockPool2);
        assertTrue(lpToken.isPoolAllowed(mockPool1));
    }

    function testLPToken_mintTokenAndUpdate() public {
        // setup
        lpToken.proposeFactoryAddress(mockFactory);
        vm.startPrank(mockFactory);
        lpToken.confirmFactoryAddress();
        lpToken.addPoolToAllowList(mockPool1);
        // test not allowed pool
        vm.startPrank(mockMaliciousPool);
        vm.expectRevert(abi.encodeWithSelector(PoolNotAllowed.selector));
        lpToken.mintTokenAndUpdate(alice, int(1e18).toPackedFloat(0), int(1e18).toPackedFloat(0));
        // test positive case
        vm.startPrank(mockPool1);
        uint tokenId = lpToken.mintTokenAndUpdate(alice, int(1e18).toPackedFloat(0), int(1e18).toPackedFloat(0));
        assertEq(lpToken.ownerOf(tokenId), alice);
        assertEq(lpToken.balanceOf(alice), 1);
        // test inactive token
        assertTrue(lpToken.inactiveToken(tokenId));
        uint activeTokenId = lpToken.mintTokenAndUpdate(alice, int(1e18).toPackedFloat(0), int(1e18).toPackedFloat(0));
        assertFalse(lpToken.inactiveToken(activeTokenId));
        assertEq(lpToken.balanceOf(alice), 2);
        // test inactive in another pool
        vm.startPrank(mockFactory);
        lpToken.addPoolToAllowList(mockPool2);
        vm.startPrank(mockPool2);
        tokenId = lpToken.mintTokenAndUpdate(alice, int(1e18).toPackedFloat(0), int(1e18).toPackedFloat(0));
        assertEq(lpToken.ownerOf(tokenId), alice);
        assertEq(lpToken.balanceOf(alice), 3);
        // test inactive token
        assertTrue(lpToken.inactiveToken(tokenId));
        activeTokenId = lpToken.mintTokenAndUpdate(alice, int(1e18).toPackedFloat(0), int(1e18).toPackedFloat(0));
        assertFalse(lpToken.inactiveToken(activeTokenId));
        assertEq(lpToken.balanceOf(alice), 4);
    }

    function testLPToken_update() public {
        // setup
        lpToken.proposeFactoryAddress(mockFactory);
        vm.startPrank(mockFactory);
        lpToken.confirmFactoryAddress();
        lpToken.addPoolToAllowList(mockPool1);
        lpToken.addPoolToAllowList(mockPool2);
        vm.startPrank(mockPool1);
        uint tokenIdPool1 = lpToken.mintTokenAndUpdate(alice, int(1e18).toPackedFloat(0), int(1e18).toPackedFloat(0));
        vm.startPrank(mockPool2);
        uint tokenIdPool2 = lpToken.mintTokenAndUpdate(alice, int(1e36).toPackedFloat(0), int(1e36).toPackedFloat(0));
        // test tokenNotFromPool
        vm.startPrank(mockPool1);
        vm.expectRevert(abi.encodeWithSelector(TokenNotFromPool.selector));
        lpToken.updateLPToken(tokenIdPool2, int(1e18).toPackedFloat(0), int(1e18).toPackedFloat(0));
        // test positive case
        lpToken.updateLPToken(tokenIdPool1, int(1e18).toPackedFloat(0), int(1e18).toPackedFloat(0));
        (packedFloat wj, packedFloat rj) = lpToken.getLPToken(tokenIdPool1);
        assertEq(packedFloat.unwrap(wj), packedFloat.unwrap(int(1e18).toPackedFloat(0)));
        assertEq(packedFloat.unwrap(rj), packedFloat.unwrap(int(1e18).toPackedFloat(0)));
    }

    function testLPToken_withdrawalTokenAndUpdate() public {
        // setup
        lpToken.proposeFactoryAddress(mockFactory);
        vm.startPrank(mockFactory);
        lpToken.confirmFactoryAddress();
        lpToken.addPoolToAllowList(mockPool1);
        lpToken.addPoolToAllowList(mockPool2);
        vm.startPrank(mockPool1);
        uint tokenIdPool1 = lpToken.mintTokenAndUpdate(alice, int(1e18).toPackedFloat(0), int(1e18).toPackedFloat(0));
        assertEq(lpToken.ownerOf(tokenIdPool1), alice);
        assertEq(lpToken.balanceOf(alice), 1);
        vm.startPrank(mockPool2);
        uint tokenIdPool2 = lpToken.mintTokenAndUpdate(alice, int(1e36).toPackedFloat(0), int(1e36).toPackedFloat(0));
        assertEq(lpToken.ownerOf(tokenIdPool2), alice);
        assertEq(lpToken.balanceOf(alice), 2);
        // test not-allowed-pool error through token-not-from-pool error
        vm.startPrank(mockMaliciousPool);
        vm.expectRevert(abi.encodeWithSelector(TokenNotFromPool.selector));
        lpToken.updateLPTokenWithdrawal(tokenIdPool1, int(1e18).toPackedFloat(0), int(1e18).toPackedFloat(0));
        vm.expectRevert(abi.encodeWithSelector(TokenNotFromPool.selector));
        lpToken.updateLPTokenWithdrawal(tokenIdPool2, int(1e18).toPackedFloat(0), int(1e18).toPackedFloat(0));
        // test token not from pool
        vm.startPrank(mockPool1);
        vm.expectRevert(abi.encodeWithSelector(TokenNotFromPool.selector));
        lpToken.updateLPTokenWithdrawal(tokenIdPool2, int(1e18).toPackedFloat(0), int(1e18).toPackedFloat(0));
        vm.startPrank(mockPool2);
        vm.expectRevert(abi.encodeWithSelector(TokenNotFromPool.selector));
        lpToken.updateLPTokenWithdrawal(tokenIdPool1, int(1e18).toPackedFloat(0), int(1e18).toPackedFloat(0));
        // test positive case
        vm.startPrank(mockPool1);
        lpToken.updateLPTokenWithdrawal(tokenIdPool1, int(1e18).toPackedFloat(int(-18)), int(1e18).toPackedFloat(int(-18)));
        vm.startPrank(mockPool2);
        lpToken.updateLPTokenWithdrawal(tokenIdPool2, int(1e18).toPackedFloat(int(-18)), int(1e18).toPackedFloat(int(-18)));
        (packedFloat wj, packedFloat rj) = lpToken.getLPToken(tokenIdPool1);
        assertEq(packedFloat.unwrap(wj), packedFloat.unwrap(int(1e18).toPackedFloat(int(-18))));
        assertEq(packedFloat.unwrap(rj), packedFloat.unwrap(int(1e18).toPackedFloat(int(-18))));
        (wj, rj) = lpToken.getLPToken(tokenIdPool2);
        assertEq(packedFloat.unwrap(wj), packedFloat.unwrap(int(1e18).toPackedFloat(int(-18))));
        assertEq(packedFloat.unwrap(rj), packedFloat.unwrap(int(1e18).toPackedFloat(int(-18))));
        // test burn
        assertEq(lpToken.balanceOf(alice), 2);
        vm.startPrank(mockPool1);
        lpToken.updateLPTokenWithdrawal(tokenIdPool1, packedFloat.wrap(0), int(1e18).toPackedFloat(int(-18)));
        vm.expectRevert(abi.encodeWithSignature("ERC721NonexistentToken(uint256)", tokenIdPool1));
        lpToken.ownerOf(tokenIdPool1);
        assertEq(lpToken.balanceOf(alice), 1);
        vm.startPrank(mockPool2);
        lpToken.updateLPTokenWithdrawal(tokenIdPool2, packedFloat.wrap(0), int(1e18).toPackedFloat(int(-18)));
        vm.expectRevert(abi.encodeWithSignature("ERC721NonexistentToken(uint256)", tokenIdPool2));
        lpToken.ownerOf(tokenIdPool2);
        assertEq(lpToken.balanceOf(alice), 0);
    }

    function testLPToken_transferOwnership() public {
        // setup
        lpToken.proposeFactoryAddress(mockFactory);
        vm.startPrank(mockFactory);
        lpToken.confirmFactoryAddress();
        // test not owner
        vm.startPrank(mockMaliciousFactory);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", mockMaliciousFactory));
        lpToken.transferOwnership(mockMaliciousFactory);
        // test not proposed owner
        vm.startPrank(admin);
        lpToken.transferOwnership(cade);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", mockMaliciousFactory));
        vm.startPrank(mockMaliciousFactory);
        lpToken.acceptOwnership();
        // test positive case
        vm.startPrank(cade);
        lpToken.acceptOwnership();
        assertEq(lpToken.owner(), cade);
    }

    function testLPToken_transferTokens() public {
        // setup
        lpToken.proposeFactoryAddress(mockFactory);
        vm.startPrank(mockFactory);
        lpToken.confirmFactoryAddress();
        lpToken.addPoolToAllowList(mockPool1);
        lpToken.addPoolToAllowList(mockPool2);
        vm.startPrank(mockPool1);
        uint tokenIdPool1 = lpToken.mintTokenAndUpdate(alice, int(1e18).toPackedFloat(0), int(1e18).toPackedFloat(0));
        vm.startPrank(mockPool2);
        lpToken.mintTokenAndUpdate(alice, int(1e36).toPackedFloat(0), int(1e36).toPackedFloat(0));
        // test
        vm.startPrank(alice);
        lpToken.safeTransferFrom(alice, cade, tokenIdPool1);
        assertEq(lpToken.ownerOf(tokenIdPool1), cade);
        assertEq(lpToken.balanceOf(cade), 1);
        assertEq(lpToken.balanceOf(alice), 1);
    }
}
