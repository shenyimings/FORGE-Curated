// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {SetupStvStETHPool} from "./SetupStvStETHPool.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Test} from "forge-std/Test.sol";
import {FeaturePausable} from "src/utils/FeaturePausable.sol";

contract MintingPauseTest is Test, SetupStvStETHPool {
    address public mintingPauseRoleHolder;
    address public mintingResumeRoleHolder;

    bytes32 mintingFeatureId;

    function setUp() public override {
        super.setUp();

        mintingPauseRoleHolder = makeAddr("mintingPauseRoleHolder");
        mintingResumeRoleHolder = makeAddr("mintingResumeRoleHolder");

        vm.deal(mintingPauseRoleHolder, 10 ether);
        vm.deal(mintingResumeRoleHolder, 10 ether);

        vm.startPrank(owner);
        pool.grantRole(pool.MINTING_PAUSE_ROLE(), mintingPauseRoleHolder);
        pool.grantRole(pool.MINTING_RESUME_ROLE(), mintingResumeRoleHolder);
        vm.stopPrank();

        mintingFeatureId = pool.MINTING_FEATURE();
        vm.deal(address(this), 100 ether);

        pool.depositETH{value: 10 ether}(address(this), address(0));
    }

    function test_MintStethShares_RevertWhenPaused() public {
        vm.prank(mintingPauseRoleHolder);
        pool.pauseMinting();

        vm.expectRevert(abi.encodeWithSelector(FeaturePausable.FeaturePauseEnforced.selector, mintingFeatureId));
        pool.mintStethShares(10 ** 18);
    }

    function test_MintWsteth_RevertWhenPaused() public {
        vm.prank(mintingPauseRoleHolder);
        pool.pauseMinting();

        vm.expectRevert(abi.encodeWithSelector(FeaturePausable.FeaturePauseEnforced.selector, mintingFeatureId));
        pool.mintWsteth(10 ** 18);
    }

    function test_PauseMinting_RevertWhenCallerUnauthorized() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), pool.MINTING_PAUSE_ROLE()
            )
        );
        pool.pauseMinting();
    }

    function test_ResumeMinting_RevertWhenCallerUnauthorized() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), pool.MINTING_RESUME_ROLE()
            )
        );
        pool.resumeMinting();
    }

    function test_ResumeMinting_AllowsMintAfterPause() public {
        vm.prank(mintingPauseRoleHolder);
        pool.pauseMinting();

        vm.prank(mintingResumeRoleHolder);
        pool.resumeMinting();

        pool.mintStethShares(10 ** 18);
        assertEq(pool.mintedStethSharesOf(address(this)), 10 ** 18);
    }

    function test_DepositAndMintSteth_RevertWhenMintingPaused() public {
        vm.prank(mintingPauseRoleHolder);
        pool.pauseMinting();

        vm.expectRevert(abi.encodeWithSelector(FeaturePausable.FeaturePauseEnforced.selector, mintingFeatureId));
        pool.depositETHAndMintStethShares{value: 1 ether}(address(0), 10 ** 18);
    }

    function test_DepositAndMintWsteth_RevertWhenMintingPaused() public {
        vm.prank(mintingPauseRoleHolder);
        pool.pauseMinting();

        vm.expectRevert(abi.encodeWithSelector(FeaturePausable.FeaturePauseEnforced.selector, mintingFeatureId));
        pool.depositETHAndMintWsteth{value: 1 ether}(address(0), 10 ** 18);
    }
}
