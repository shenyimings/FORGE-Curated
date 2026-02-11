// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { AutoCompoundBase } from "./AutoCompoundBase.t.sol";
import { AragonMerklAutoCompoundStrategy as AutoCompoundStrategy } from
    "src/strategies/AragonMerklAutoCompoundStrategy.sol";
import { DaoUnauthorized } from "@aragon/osx-commons-contracts/src/permission/auth/auth.sol";

contract AutoCompoundWithdrawTokensTest is AutoCompoundBase {
    function testRevert_MixedWithMasterToken() public {
        // Create regular tokens
        escrowToken.approve(address(escrow), 100e18);
        uint256 tokenId1 = escrow.createLock(100e18);

        // Transfer tokens to strategy
        lockNft.safeTransferFrom(address(this), address(acStrategy), tokenId1);

        // Get master token ID
        uint256 strategyMasterTokenId = acStrategy.masterTokenId();

        // Try to withdraw mix of regular tokens and master token
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = tokenId1;
        tokenIds[1] = strategyMasterTokenId; // Master token in the middle

        // Should revert when array contains master token
        vm.expectRevert(AutoCompoundStrategy.CannotTransferMasterToken.selector);
        acStrategy.withdrawTokens(tokenIds, alice);
    }

    function testRevert_NoPermission() public {
        // Try to withdraw without permission
        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector,
                address(dao),
                address(acStrategy),
                alice,
                acStrategy.AUTOCOMPOUND_STRATEGY_ADMIN_ROLE()
            )
        );
        vm.prank(alice);
        acStrategy.withdrawTokens(new uint256[](0), bob);
    }

    function test_WithdrawsTokenIdsSuccessfully() public {
        // Create some token IDs for testing
        escrowToken.approve(address(escrow), 200e18);
        uint256 tokenId1 = escrow.createLock(100e18);
        uint256 tokenId2 = escrow.createLock(100e18);

        // Transfer tokens to strategy
        lockNft.safeTransferFrom(address(this), address(acStrategy), tokenId1);
        lockNft.safeTransferFrom(address(this), address(acStrategy), tokenId2);

        // Prepare withdrawal array
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = tokenId1;
        tokenIds[1] = tokenId2;

        vm.expectEmit();
        emit AutoCompoundStrategy.Sweep(tokenIds, alice);

        // Withdraw tokens to alice
        acStrategy.withdrawTokens(tokenIds, alice);

        // Verify alice now owns all tokens
        assertEq(lockNft.ownerOf(tokenId1), alice);
        assertEq(lockNft.ownerOf(tokenId2), alice);
    }
}
