// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { ITheCompact } from "../../src/interfaces/ITheCompact.sol";

import { ResetPeriod } from "../../src/types/ResetPeriod.sol";
import { Scope } from "../../src/types/Scope.sol";

import { Setup } from "./Setup.sol";

contract DepositTest is Setup {
    function setUp() public override {
        super.setUp();
    }

    function test_depositETHBasic() public {
        address recipient = swapper;
        ResetPeriod resetPeriod = ResetPeriod.TenMinutes;
        Scope scope = Scope.Multichain;
        uint256 amount = 1e18;

        vm.prank(allocator);
        uint96 allocatorId = theCompact.__registerAllocator(allocator, "");

        bytes12 lockTag =
            bytes12(bytes32((uint256(scope) << 255) | (uint256(resetPeriod) << 252) | (uint256(allocatorId) << 160)));

        vm.prank(swapper);
        uint256 id = theCompact.depositNative{ value: amount }(lockTag, address(0));
        vm.snapshotGasLastCall("depositETHBasic");

        (
            address derivedToken,
            address derivedAllocator,
            ResetPeriod derivedResetPeriod,
            Scope derivedScope,
            bytes12 derivedLockTag
        ) = theCompact.getLockDetails(id);
        assertEq(derivedToken, address(0));
        assertEq(derivedAllocator, allocator);
        assertEq(uint256(derivedResetPeriod), uint256(resetPeriod));
        assertEq(uint256(derivedScope), uint256(scope));
        assertEq(
            id,
            (uint256(scope) << 255) | (uint256(resetPeriod) << 252) | (uint256(allocatorId) << 160)
                | uint256(uint160(address(0)))
        );
        assertEq(
            derivedLockTag,
            bytes12(bytes32((uint256(scope) << 255) | (uint256(resetPeriod) << 252) | (uint256(allocatorId) << 160)))
        );

        assertEq(address(theCompact).balance, amount);
        assertEq(theCompact.balanceOf(recipient, id), amount);
        assert(bytes(theCompact.tokenURI(id)).length > 0);
    }

    function test_depositETHAndURI() public {
        address recipient = 0x1111111111111111111111111111111111111111;
        ResetPeriod resetPeriod = ResetPeriod.TenMinutes;
        Scope scope = Scope.Multichain;
        uint256 amount = 1e18;

        vm.prank(allocator);
        uint96 allocatorId = theCompact.__registerAllocator(allocator, "");

        bytes12 lockTag =
            bytes12(bytes32((uint256(scope) << 255) | (uint256(resetPeriod) << 252) | (uint256(allocatorId) << 160)));

        vm.prank(swapper);
        uint256 id = theCompact.depositNative{ value: amount }(lockTag, recipient);
        vm.snapshotGasLastCall("depositETHAndURI");

        (
            address derivedToken,
            address derivedAllocator,
            ResetPeriod derivedResetPeriod,
            Scope derivedScope,
            bytes12 derivedLockTag
        ) = theCompact.getLockDetails(id);
        assertEq(derivedToken, address(0));
        assertEq(derivedAllocator, allocator);
        assertEq(uint256(derivedResetPeriod), uint256(resetPeriod));
        assertEq(uint256(derivedScope), uint256(scope));
        assertEq(
            id,
            (uint256(scope) << 255) | (uint256(resetPeriod) << 252) | (uint256(allocatorId) << 160)
                | uint256(uint160(address(0)))
        );
        assertEq(
            derivedLockTag,
            bytes12(bytes32((uint256(scope) << 255) | (uint256(resetPeriod) << 252) | (uint256(allocatorId) << 160)))
        );

        assertEq(address(theCompact).balance, amount);
        assertEq(theCompact.balanceOf(recipient, id), amount);
        assert(bytes(theCompact.tokenURI(id)).length > 0);
    }

    function test_depositERC20Basic() public {
        address recipient = swapper;
        ResetPeriod resetPeriod = ResetPeriod.TenMinutes;
        Scope scope = Scope.Multichain;
        uint256 amount = 1e18;

        vm.prank(allocator);
        uint96 allocatorId = theCompact.__registerAllocator(allocator, "");

        bytes12 lockTag =
            bytes12(bytes32((uint256(scope) << 255) | (uint256(resetPeriod) << 252) | (uint256(allocatorId) << 160)));

        vm.prank(swapper);
        uint256 id = theCompact.depositERC20(address(token), lockTag, amount, swapper);
        vm.snapshotGasLastCall("depositERC20Basic");

        (
            address derivedToken,
            address derivedAllocator,
            ResetPeriod derivedResetPeriod,
            Scope derivedScope,
            bytes12 derivedLockTag
        ) = theCompact.getLockDetails(id);
        assertEq(derivedToken, address(token));
        assertEq(derivedAllocator, allocator);
        assertEq(uint256(derivedResetPeriod), uint256(resetPeriod));
        assertEq(uint256(derivedScope), uint256(scope));
        assertEq(
            id,
            (uint256(scope) << 255) | (uint256(resetPeriod) << 252) | (uint256(allocatorId) << 160)
                | uint256(uint160(address(token)))
        );
        assertEq(
            derivedLockTag,
            bytes12(bytes32((uint256(scope) << 255) | (uint256(resetPeriod) << 252) | (uint256(allocatorId) << 160)))
        );

        assertEq(token.balanceOf(address(theCompact)), amount);
        assertEq(theCompact.balanceOf(recipient, id), amount);
        assert(bytes(theCompact.tokenURI(id)).length > 0);
    }

    function test_depositERC20AndURI() public {
        address recipient = 0x1111111111111111111111111111111111111111;
        ResetPeriod resetPeriod = ResetPeriod.TenMinutes;
        Scope scope = Scope.Multichain;
        uint256 amount = 1e18;

        vm.prank(allocator);
        uint96 allocatorId = theCompact.__registerAllocator(allocator, "");

        bytes12 lockTag =
            bytes12(bytes32((uint256(scope) << 255) | (uint256(resetPeriod) << 252) | (uint256(allocatorId) << 160)));

        vm.prank(swapper);
        uint256 id = theCompact.depositERC20(address(token), lockTag, amount, recipient);
        vm.snapshotGasLastCall("depositERC20AndURI");

        (
            address derivedToken,
            address derivedAllocator,
            ResetPeriod derivedResetPeriod,
            Scope derivedScope,
            bytes12 derivedLockTag
        ) = theCompact.getLockDetails(id);
        assertEq(derivedToken, address(token));
        assertEq(derivedAllocator, allocator);
        assertEq(uint256(derivedResetPeriod), uint256(resetPeriod));
        assertEq(uint256(derivedScope), uint256(scope));
        assertEq(
            id,
            (uint256(scope) << 255) | (uint256(resetPeriod) << 252) | (uint256(allocatorId) << 160)
                | uint256(uint160(address(token)))
        );
        assertEq(
            derivedLockTag,
            bytes12(bytes32((uint256(scope) << 255) | (uint256(resetPeriod) << 252) | (uint256(allocatorId) << 160)))
        );

        assertEq(token.balanceOf(address(theCompact)), amount);
        assertEq(theCompact.balanceOf(recipient, id), amount);
        assert(bytes(theCompact.tokenURI(id)).length > 0);
    }

    function test_depositBatchSingleNativeToken() public {
        address recipient = 0x1111111111111111111111111111111111111111;
        ResetPeriod resetPeriod = ResetPeriod.TenMinutes;
        Scope scope = Scope.Multichain;
        uint256 amount = 1e18;

        vm.prank(allocator);
        uint96 allocatorId = theCompact.__registerAllocator(allocator, "");

        uint256 id = (
            (uint256(scope) << 255) | (uint256(resetPeriod) << 252) | (uint256(allocatorId) << 160)
                | uint256(uint160(address(0)))
        );

        {
            uint256[2][] memory idsAndAmounts = new uint256[2][](1);
            idsAndAmounts[0] = [id, amount];

            vm.prank(swapper);
            bool ok = theCompact.batchDeposit{ value: amount }(idsAndAmounts, recipient);
            vm.snapshotGasLastCall("depositBatchSingleNative");
            assert(ok);
        }

        (
            address derivedToken,
            address derivedAllocator,
            ResetPeriod derivedResetPeriod,
            Scope derivedScope,
            bytes12 lockTag
        ) = theCompact.getLockDetails(id);
        assertEq(derivedToken, address(0));
        assertEq(derivedAllocator, allocator);
        assertEq(uint256(derivedResetPeriod), uint256(resetPeriod));
        assertEq(uint256(derivedScope), uint256(scope));

        assertEq(
            id,
            (uint256(scope) << 255) | (uint256(resetPeriod) << 252) | (uint256(allocatorId) << 160)
                | uint256(uint160(address(0)))
        );
        assertEq(
            lockTag,
            bytes12(bytes32((uint256(scope) << 255) | (uint256(resetPeriod) << 252) | (uint256(allocatorId) << 160)))
        );

        assertEq(address(theCompact).balance, amount);
        assertEq(theCompact.balanceOf(recipient, id), amount);
        assert(bytes(theCompact.tokenURI(id)).length > 0);
    }

    function test_depositBatchSingleERC20() public {
        address recipient = 0x1111111111111111111111111111111111111111;
        ResetPeriod resetPeriod = ResetPeriod.TenMinutes;
        Scope scope = Scope.Multichain;
        uint256 amount = 1e18;

        vm.prank(allocator);
        uint96 allocatorId = theCompact.__registerAllocator(allocator, "");

        uint256 id = (
            (uint256(scope) << 255) | (uint256(resetPeriod) << 252) | (uint256(allocatorId) << 160)
                | uint256(uint160(address(token)))
        );

        {
            uint256[2][] memory idsAndAmounts = new uint256[2][](1);
            idsAndAmounts[0] = [id, amount];

            vm.prank(swapper);
            bool ok = theCompact.batchDeposit(idsAndAmounts, recipient);
            vm.snapshotGasLastCall("depositBatchSingleERC20");
            assert(ok);
        }

        (
            address derivedToken,
            address derivedAllocator,
            ResetPeriod derivedResetPeriod,
            Scope derivedScope,
            bytes12 lockTag
        ) = theCompact.getLockDetails(id);
        assertEq(derivedToken, address(token));
        assertEq(derivedAllocator, allocator);
        assertEq(uint256(derivedResetPeriod), uint256(resetPeriod));
        assertEq(uint256(derivedScope), uint256(scope));

        assertEq(
            id,
            (uint256(scope) << 255) | (uint256(resetPeriod) << 252) | (uint256(allocatorId) << 160)
                | uint256(uint160(address(token)))
        );
        assertEq(
            lockTag,
            bytes12(bytes32((uint256(scope) << 255) | (uint256(resetPeriod) << 252) | (uint256(allocatorId) << 160)))
        );

        assertEq(token.balanceOf(address(theCompact)), amount);
        assertEq(theCompact.balanceOf(recipient, id), amount);
        assert(bytes(theCompact.tokenURI(id)).length > 0);
    }
}
