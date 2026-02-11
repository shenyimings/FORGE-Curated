// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {CommonEvents} from "src/common/IEvents.sol";
import {TestCommonSetup, FactoryBase} from "test/util/TestCommonSetup.sol";
import "forge-std/console2.sol";

/**
 * @title Test PoolFactory contract
 * @dev unit test
 * @author @oscarsernarosero @mpetersoCode55
 */
abstract contract FactoryCommon is TestCommonSetup {
    FactoryBase factory;

    function _setUp() public {
        _setUpTokens(1e11 * 1e18);
    }

    function _buildDeployment() internal {
        _deployFactory();
        _deployAllowLists();
        factory = FactoryBase(_getFactoryAddress());
    }

    function testLiquidity_PoolFactory_version() public {
        _buildDeployment();
        assertEq(factory.VERSION(), "v1.0.0");
    }

    function testLiquidity_PoolFactory_deployment() public {
        _buildDeployment();
        assertNotEq(_getFactoryAddress(), address(0));
        assertNotEq(_getFactoryAddress(), address(0));
    }

    function testLiquidity_PoolFactory_owner() public {
        _buildDeployment();
        (bool success, bytes memory res) = address(factory).call(abi.encodeWithSignature("owner()"));
        if (!success) revert("call to owner failed");
        address owner = abi.decode(res, (address));
        assertEq(owner, admin);
    }

    function testLiquidity_PoolFactory_setYTokenAllowList_NotOnwer() public {
        _buildDeployment();
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", alice));
        factory.setYTokenAllowList(address(yTokenAllowList));
    }

    function testLiquidity_PoolFactory_setYTokenAllowList_Positive() public {
        _buildDeployment();
        vm.startPrank(admin);
        factory.setYTokenAllowList(address(yTokenAllowList));
    }

    function testLiquidity_PoolFactory_setDeployerAllowList_NotOnwer() public {
        _buildDeployment();
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", alice));
        factory.setDeployerAllowList(address(deployerAllowList));
    }

    function testLiquidity_PoolFactory_setDeployerAllowList_Positive() public {
        _buildDeployment();
        vm.startPrank(admin);
        factory.setDeployerAllowList(address(deployerAllowList));
        assertEq(factory.getDeployerAllowList(), address(deployerAllowList));
    }

    function _deployAndSetupFactory() internal {
        _buildDeployment();
        _setupFactory(address(factory));
    }

    function _build_proposeNewProtocolFeeCollector() public {
        _deployAndSetupFactory();
        vm.startPrank(admin);
        factory.proposeProtocolFeeCollector(address(0xbabe));
    }

    function testLiquidity_PoolFactory_proposeNewProtocolFeeCollector_Positive() public {
        _build_proposeNewProtocolFeeCollector();
        assertEq(factory.proposedProtocolFeeCollector(), address(0xbabe));
    }

    function testLiquidity_PoolFactory_confirmNewProtocolFeeCollector_Positive() public {
        _build_proposeNewProtocolFeeCollector();
        vm.startPrank(address(0xbabe));
        factory.confirmProtocolFeeCollector();
        assertEq(factory.protocolFeeCollector(), address(0xbabe));
    }

    function testLiquidity_PoolFactory_confirmNewProtocolFeeCollector_NotProposedProtocolFeeCollector(address confirmer) public {
        if (confirmer == address(0xbabe)) return;
        _build_proposeNewProtocolFeeCollector();
        vm.startPrank(confirmer);
        vm.expectRevert(abi.encodeWithSignature("NotProposedProtocolFeeCollector()"));
        factory.confirmProtocolFeeCollector();
    }

    function testLiquidity_PoolFactory_proposeNewProtocolFeeCollector_NotOwner(address proposer) public {
        if (proposer == admin) return;
        _deployAndSetupFactory();
        vm.startPrank(proposer);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", proposer));
        factory.proposeProtocolFeeCollector(address(0xbabe));
    }

    function testLiquidity_PoolFactory_setProtocolFee_Positive(uint16 _fee) public {
        _deployAndSetupFactory();
        uint16 feeUpdate = uint16(bound(_fee, 0, 20));
        vm.startPrank(admin);
        vm.expectEmit(true, true, true, true, address(factory));
        emit CommonEvents.FeeSet(CommonEvents.FeeCollectionType.PROTOCOL, feeUpdate);
        factory.setProtocolFee(feeUpdate);
        assertTrue(factory.protocolFee() == feeUpdate, "Fee should equal updatedFee");
    }

    function testLiquidity_PoolFactory_setProtocolFee_NotProtocolCollector() public {
        _deployAndSetupFactory();
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", bob));
        vm.startPrank(bob);
        factory.setProtocolFee(20);
    }

    function testLiquidity_PoolFactory_setProtocolFee_OverMax() public {
        _deployAndSetupFactory();
        vm.startPrank(admin);
        vm.expectRevert(abi.encodeWithSignature("ProtocolFeeAboveMax(uint16,uint16)", 21, 20));
        factory.setProtocolFee(21);
    }

    function testLiquidity_PoolFactory_RevertOnRenounceOwnershipCall() public {
        _deployAndSetupFactory();
        vm.startPrank(admin);
        vm.expectRevert(abi.encodeWithSignature("RenouncingOwnershipForbidden()"));
        factory.renounceOwnership();
    }
}
