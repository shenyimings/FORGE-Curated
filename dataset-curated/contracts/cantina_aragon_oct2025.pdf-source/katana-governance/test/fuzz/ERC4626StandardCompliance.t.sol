// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { ERC4626Test } from "erc4626-tests/ERC4626.test.sol";
import { Vm } from "forge-std/Vm.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { Base } from "../Base.sol";

/// Uses additional tests from https://github.com/a16z/erc4626-tests to verify ERC-4626 compliance.
/// Note: `redeem` and `withdraw` are overridden since, in AvKatVault, they return
/// a token ID instead of transferring assets directly.
contract ERC4626StandardComplianceTest is ERC4626Test, Base {
    enum ExitMode {
        REDEEM,
        WITHDRAW
    }

    function setUp() public override(Base, ERC4626Test) {
        Base.setUp();

        _underlying_ = vault.asset();

        _vault_ = address(vault);
        _delta_ = 0;
        _vaultMayBeEmpty = false;
        _unlimitedAmount = false;
    }

    function test_redeem(Init memory init, uint256 shares, uint256 allowance) public override {
        _testVaultExit({ init: init, mode: ExitMode.REDEEM, value: shares, allowance: allowance });
    }

    function test_withdraw(Init memory init, uint256 assets, uint256 allowance) public override {
        _testVaultExit({ init: init, mode: ExitMode.WITHDRAW, value: assets, allowance: allowance });
    }

    function _testVaultExit(Init memory init, ExitMode mode, uint256 value, uint256 allowance) internal {
        setUpVault(init);
        address caller = init.user[0];
        address receiver = init.user[1];
        address owner = init.user[2];
        uint256 maxValue = (mode == ExitMode.REDEEM) ? _max_redeem(owner) : _max_withdraw(owner);
        value = bound(value, 0, maxValue);

        _approve(_vault_, owner, caller, allowance);

        uint256 oldReceiverAsset = IERC20(_underlying_).balanceOf(receiver);
        uint256 oldOwnerShare = IERC20(_vault_).balanceOf(owner);
        uint256 oldAllowance = IERC20(_vault_).allowance(owner, caller);

        vm.recordLogs();
        vm.prank(caller);
        uint256 assets;
        uint256 shares;

        if (mode == ExitMode.REDEEM) {
            assets = vault_redeem(value, receiver, owner);
            shares = value;
        } else {
            shares = vault_withdraw(value, receiver, owner);
            assets = value;
        }

        uint256 tokenId = _getWithdrawnTokenId();

        uint256 newReceiverAsset = IERC20(_underlying_).balanceOf(receiver) + escrow.locked(tokenId).amount;
        uint256 newOwnerShare = IERC20(_vault_).balanceOf(owner);
        uint256 newAllowance = IERC20(_vault_).allowance(owner, caller);

        assertApproxEqAbs(newOwnerShare, oldOwnerShare - shares, _delta_, "share");

        // NOTE: may fail if receiver is a contract that internally retains funds
        assertApproxEqAbs(newReceiverAsset, oldReceiverAsset + assets, _delta_, "asset");

        if (caller != owner && oldAllowance != type(uint256).max) {
            assertApproxEqAbs(newAllowance, oldAllowance - shares, _delta_, "allowance");
        }

        assertTrue(caller == owner || oldAllowance != 0 || (shares == 0 && assets == 0), "access control");
    }

    function _getWithdrawnTokenId() internal returns (uint256 tokenId) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 topic = keccak256("TokenIdWithdrawn(uint256,address)");

        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == topic) {
                tokenId = uint256(logs[i].topics[1]);
                break;
            }
        }
    }
}
