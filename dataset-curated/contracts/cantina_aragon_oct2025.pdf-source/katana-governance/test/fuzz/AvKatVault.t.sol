// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { Base } from "../Base.sol";
import { ERC721ReceiverMock } from "../mocks/MockERC721.sol";

contract VaultWithdrawTest is Base {
    uint256 internal constant USER_COUNT = 20;
    uint256 internal constant WITHDRAWAL_COUNT_AT_LEAST = 5;
    uint256 internal constant AMOUNT_AT_LEAST = 3;

    struct User {
        address account;
        uint128 amount;
        bool withdraws;
    }

    function setUp() public override {
        super.setUp();
    }

    modifier assumeValidation(User[USER_COUNT] memory _users) {
        uint256 withdrawalCount = 0;
        uint256 amountAtLeastOne = 0;
        for (uint256 i = 0; i < _users.length; i++) {
            vm.assume(_users[i].amount > 0 && _users[i].amount < type(uint128).max);
            vm.assume(_users[i].account != address(0));

            if (_users[i].account.code.length != 0) {
                ERC721ReceiverMock receiver = new ERC721ReceiverMock();
                _users[i].account = address(receiver);
            }

            _mintAndApprove(_users[i].account, address(vault), _users[i].amount);

            if (!_users[i].withdraws) {
                continue;
            }

            withdrawalCount++;
            if (_users[i].amount > _parseToken(1)) {
                amountAtLeastOne++;
            }
        }

        vm.assume(withdrawalCount >= WITHDRAWAL_COUNT_AT_LEAST);
        vm.assume(amountAtLeastOne >= AMOUNT_AT_LEAST);
        _;
    }

    function testFuzz_NoCompound(
        User[USER_COUNT] memory _users,
        uint128 _compoundAmount
    )
        public
        assumeValidation(_users)
    {
        uint256 totalDepositAmount = 0;
        uint256 totalDepositShares = 0;
        uint256 totalSharesBefore = vault.totalSupply();
        uint256 totalAssetsBefore = vault.totalAssets();

        assertEq(vault.convertToAssets(_parseToken(1)), _parseToken(1));

        for (uint256 i = 0; i < _users.length; i++) {
            vm.prank(_users[i].account);
            vault.deposit(_users[i].amount, _users[i].account);

            totalDepositAmount += _users[i].amount;
            totalDepositShares += vault.convertToShares(_users[i].amount);
        }

        assertEq(vault.convertToAssets(_parseToken(1)), _parseToken(1));

        assertEq(escrow.lastLockId(), _users.length + 1);
        assertEq(vault.totalAssets(), totalAssetsBefore + totalDepositAmount);
        assertEq(vault.totalSupply(), totalSharesBefore + totalDepositShares);
        assertEq(escrow.locked(masterTokenId).amount, totalAssetsBefore + totalDepositAmount);

        if (_compoundAmount > 0) {
            _mintAndApprove(address(this), address(escrow), _compoundAmount);
            uint256 tokenId = escrow.createLockFor(_compoundAmount, address(acStrategy));
            vm.startPrank(address(acStrategy));
            escrow.merge(tokenId, masterTokenId);
            vm.stopPrank();
        }

        assertGe(vault.convertToAssets(_parseToken(1)), _parseToken(1));

        // Withdraw...
        uint256 totalWithdrawAmount = 0;
        uint256 totalWithdrawShares = 0;
        totalAssetsBefore = vault.totalAssets();
        totalSharesBefore = vault.totalSupply();

        for (uint256 i = 0; i < _users.length; i++) {
            if (_users[i].withdraws) {
                continue;
            }

            vm.prank(_users[i].account);
            totalWithdrawShares += vault.withdraw(_users[i].amount, _users[i].account, _users[i].account);

            totalWithdrawAmount += _users[i].amount;
        }

        assertEq(vault.totalAssets(), totalAssetsBefore - totalWithdrawAmount);
        assertEq(escrow.locked(masterTokenId).amount, totalAssetsBefore - totalWithdrawAmount);
        assertEq(vault.totalSupply(), totalSharesBefore - totalWithdrawShares);
    }

    function testFuzz_WithCompound(
        User[USER_COUNT] memory _users,
        uint128 _compoundAmount
    )
        public
        assumeValidation(_users)
    {
        uint256[] memory userShares = new uint256[](_users.length);

        // Make `_compoundAmount` big enough so it causes difference.
        vm.assume(_compoundAmount >= _parseToken(1));

        // 1 share : 1 token rate
        assertEq(vault.convertToAssets(_parseToken(1)), _parseToken(1));

        for (uint256 i = 0; i < _users.length; i++) {
            vm.prank(_users[i].account);
            uint256 shares = vault.deposit(_users[i].amount, _users[i].account);
            userShares[i] += shares;
        }

        _increaseTotalAsset(_compoundAmount);

        // 1 share must give more tokens than 1 as
        // total assets increased without increasing total shares.
        assertGe(vault.convertToAssets(_parseToken(1)), _parseToken(1));

        for (uint256 i = 0; i < _users.length; i++) {
            // user's shares must give more tokens than what he depositted.
            assertGe(vault.convertToAssets(userShares[i]), _users[i].amount);

            if (!_users[i].withdraws) {
                continue;
            }

            // We withdraw only the same amount of tokens that user depositted.
            // At this point, total assets was increased but not total supply(shares).
            // When user withdraws the same amount as he depositted, it's clear that in most cases,
            // shares needed to withdraw the same amount of tokens msut be less than the shares user got
            // when he depositted. This is because after increasing total assets, 1 share now gives more assets.
            // As user withdraws the same amount as depositted, less shares must be needed.
            vm.prank(_users[i].account);
            uint256 shares = vault.withdraw(_users[i].amount, _users[i].account, _users[i].account);

            // It's worth noting that for some small deposits, the withdrawal for same amount will
            // need the same amount of shares as it minted at deposit due to rounding up.
            assertLe(shares, userShares[i]);
        }

        uint256 temp = 0;
        // Users still have some shares remaining. We withdraw them now..
        for (uint256 i = 0; i < _users.length; i++) {
            if (_users[i].withdraws) {
                continue;
            }

            address account = _users[i].account;
            uint256 leftAssets = vault.convertToAssets(vault.balanceOf(account));
            if (leftAssets == 0) {
                continue;
            }

            vm.prank(account);
            vault.withdraw(leftAssets, account, account);
            temp++;

            assertEq(vault.balanceOf(account), 0);
        }

        // Ensure that at least there was one person who depositted `x` tokens, got `y` shares
        // and withdrawal only caused `y - δ` shares to be burnt, so user still has some shares left
        // and withdraws those again.
        assertNotEq(temp, 0);
    }
}
