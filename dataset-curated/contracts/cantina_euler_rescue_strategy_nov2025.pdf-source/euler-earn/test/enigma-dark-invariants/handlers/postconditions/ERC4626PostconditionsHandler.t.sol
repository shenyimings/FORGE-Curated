// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Interfaces
import {IEulerEarn} from "src/interfaces/IEulerEarn.sol";

// Libraries
import "forge-std/console.sol";
import {ErrorsLib} from "src/libraries/ErrorsLib.sol";

// Test Contracts
import {Actor} from "../../utils/Actor.sol";
import {BaseHandler} from "../../base/BaseHandler.t.sol";

/// @title ERC4626PostconditionsHandler
/// @notice Handler test contract for a set of predefinet postconditions
abstract contract ERC4626PostconditionsHandler is BaseHandler {
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                      STATE VARIABLES                                      //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                   PROPERTIES: NON-REVERT                                  //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function assert_ERC4626_DEPOSIT_INVARIANT_C(uint8 i) external setup {
        address target_ = _getRandomEulerEarnVault(i);

        address _account = address(actor);
        uint256 maxDeposit = IEulerEarn(target_).maxDeposit(_account);

        require(maxDeposit <= type(uint112).max, "maxDeposit is greater than uint112.max");

        uint256 accountBalance = loanToken.balanceOf(_account);

        if (accountBalance < maxDeposit) {
            loanToken.mint(_account, maxDeposit - accountBalance);
        }

        if (maxDeposit != 0) {
            vm.prank(_account);
            try IEulerEarn(target_).deposit(maxDeposit, _account) returns (uint256 shares) {
                /// @dev restore original state to not break invariants
                vm.prank(_account);
                IEulerEarn(target_).redeem(shares, address(0), _account);
            } catch (bytes memory reason) {
                // check if revert reason matches the custom error selector
                if (reason.length < 4 || bytes4(reason) != ErrorsLib.AllCapsReached.selector) {
                    assertTrue(false, ERC4626_DEPOSIT_INVARIANT_C);
                }
            }
        }
    }

    function assert_ERC4626_MINT_INVARIANT_C(uint8 i) public setup {
        address target_ = _getRandomEulerEarnVault(i);

        address _account = address(actor);
        uint256 maxMint = IEulerEarn(target_).maxMint(_account);
        uint256 accountBalance = loanToken.balanceOf(_account);

        uint256 maxMintToAssets = IEulerEarn(target_).previewMint(maxMint);

        require(maxMintToAssets <= type(uint112).max, "maxMintToAssets is greater than uint112.max");

        if (accountBalance < maxMintToAssets) {
            loanToken.mint(_account, maxMintToAssets - accountBalance);
        }

        if (maxMint != 0) {
            vm.prank(_account);
            try IEulerEarn(target_).mint(maxMint, _account) {
                /// @dev restore original state to not break invariants
                vm.prank(_account);
                IEulerEarn(target_).redeem(maxMint, address(0), _account);
            } catch (bytes memory reason) {
                // check if revert reason matches the custom error selector
                if (reason.length < 4 || bytes4(reason) != ErrorsLib.AllCapsReached.selector) {
                    assertTrue(false, ERC4626_MINT_INVARIANT_C);
                }
            }
        }
    }

    function assert_ERC4626_WITHDRAW_INVARIANT_C(uint8 i) public setup {
        address target_ = _getRandomEulerEarnVault(i);

        address _account = address(actor);
        uint256 maxWithdraw = IEulerEarn(target_).maxWithdraw(_account);

        if (maxWithdraw != 0) {
            vm.prank(_account);
            try IEulerEarn(target_).withdraw(maxWithdraw, _account, _account) {}
            catch {
                assertTrue(false, ERC4626_WITHDRAW_INVARIANT_C);
            }
        }
    }

    function assert_ERC4626_REDEEM_INVARIANT_C(uint8 i) public setup {
        address target_ = _getRandomEulerEarnVault(i);

        address _account = address(actor);
        uint256 maxRedeem = IEulerEarn(target_).maxRedeem(_account);

        if (maxRedeem != 0) {
            vm.prank(_account);
            try IEulerEarn(target_).redeem(maxRedeem, _account, _account) {}
            catch {
                assertTrue(false, ERC4626_REDEEM_INVARIANT_C); //test_replay_assert_ERC4626_REDEEM_INVARIANT_C
            }
        }
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                   PROPERTIES: ROUNDTRIP                                   //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function assert_ERC4626_ROUNDTRIP_INVARIANT_A(uint256 _assets, uint8 i) external {
        address target_ = _getRandomEulerEarnVault(i);

        _mintAndApprove(address(IEulerEarn(target_).asset()), address(this), target_, _assets);

        uint256 shares = IEulerEarn(target_).deposit(_assets, address(this));

        uint256 redeemedAssets = IEulerEarn(target_).redeem(shares, address(this), address(this));

        assertLe(redeemedAssets, _assets, ERC4626_ROUNDTRIP_INVARIANT_A);
    }

    function assert_ERC4626_ROUNDTRIP_INVARIANT_B(uint256 _assets, uint8 i) external {
        address target_ = _getRandomEulerEarnVault(i);

        _mintAndApprove(address(IEulerEarn(target_).asset()), address(this), target_, _assets);

        uint256 shares = IEulerEarn(target_).deposit(_assets, address(this));

        uint256 withdrawnShares = IEulerEarn(target_).withdraw(_assets, address(this), address(this));

        /// @dev restore original state to not break invariants
        IEulerEarn(target_).redeem(IEulerEarn(target_).balanceOf(address(this)), address(this), address(this));

        assertGe(withdrawnShares, shares, ERC4626_ROUNDTRIP_INVARIANT_B);
    }

    function assert_ERC4626_ROUNDTRIP_INVARIANT_C(uint256 _shares, uint8 i) external {
        address target_ = _getRandomEulerEarnVault(i);

        _mintApproveAndMint(target_, address(this), _shares);

        uint256 redeemedAssets = IEulerEarn(target_).redeem(_shares, address(this), address(this));

        uint256 mintedShares = IEulerEarn(target_).deposit(redeemedAssets, address(this));

        /// @dev restore original state to not break invariants
        IEulerEarn(target_).redeem(mintedShares, address(this), address(this));

        assertLe(mintedShares, _shares, ERC4626_ROUNDTRIP_INVARIANT_C);
    }

    function assert_ERC4626_ROUNDTRIP_INVARIANT_D(uint256 _shares, uint8 i) external {
        address target_ = _getRandomEulerEarnVault(i);

        _mintApproveAndMint(target_, address(this), _shares);

        uint256 redeemedAssets = IEulerEarn(target_).redeem(_shares, address(this), address(this));

        uint256 depositedAssets = IEulerEarn(target_).mint(_shares, address(this));

        /// @dev restore original state to not break invariants
        IEulerEarn(target_).withdraw(depositedAssets, address(this), address(this));

        assertGe(depositedAssets, redeemedAssets, ERC4626_ROUNDTRIP_INVARIANT_D);
    }

    function assert_ERC4626_ROUNDTRIP_INVARIANT_E(uint256 _shares, uint8 i) external {
        address target_ = _getRandomEulerEarnVault(i);

        _mintAndApprove(
            address(IEulerEarn(target_).asset()),
            address(this),
            target_,
            IEulerEarn(target_).convertToAssets(_shares) + 1
        );

        uint256 depositedAssets = IEulerEarn(target_).mint(_shares, address(this));

        uint256 withdrawnShares = IEulerEarn(target_).withdraw(depositedAssets, address(this), address(this));

        /// @dev restore original state to not break invariants
        IEulerEarn(target_).redeem(IEulerEarn(target_).balanceOf(address(this)), address(this), address(this));

        assertGe(withdrawnShares, _shares, ERC4626_ROUNDTRIP_INVARIANT_E);
    }

    function assert_ERC4626_ROUNDTRIP_INVARIANT_F(uint256 _shares, uint8 i) external {
        address target_ = _getRandomEulerEarnVault(i);

        _mintAndApprove(
            address(IEulerEarn(target_).asset()), address(this), target_, IEulerEarn(target_).convertToAssets(_shares)
        );

        uint256 depositedAssets = IEulerEarn(target_).mint(_shares, address(this));

        uint256 redeemedAssets = IEulerEarn(target_).redeem(_shares, address(this), address(this));

        assertLe(redeemedAssets, depositedAssets, ERC4626_ROUNDTRIP_INVARIANT_F);
    }

    function assert_ERC4626_ROUNDTRIP_INVARIANT_G(uint256 _assets, uint8 i) external {
        address target_ = _getRandomEulerEarnVault(i);

        _mintApproveAndDeposit(target_, address(this), _assets);

        uint256 redeemedShares = IEulerEarn(target_).withdraw(_assets, address(this), address(this));

        uint256 depositedAssets = IEulerEarn(target_).mint(redeemedShares, address(this));

        /// @dev restore original state to not break invariants
        IEulerEarn(target_).redeem(IEulerEarn(target_).balanceOf(address(this)), address(this), address(this));

        assertGe(depositedAssets, _assets, ERC4626_ROUNDTRIP_INVARIANT_G);
    }

    function assert_ERC4626_ROUNDTRIP_INVARIANT_H(uint256 _assets, uint8 i) external {
        address target_ = _getRandomEulerEarnVault(i);

        _mintApproveAndDeposit(target_, address(this), _assets);

        uint256 redeemedShares = IEulerEarn(target_).withdraw(_assets, address(this), address(this));

        uint256 mintedShares = IEulerEarn(target_).deposit(_assets, address(this));

        /// @dev restore original state to not break invariants
        IEulerEarn(target_).redeem(IEulerEarn(target_).balanceOf(address(this)), address(this), address(this));

        assertLe(mintedShares, redeemedShares, ERC4626_ROUNDTRIP_INVARIANT_H);
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                  PROPERTIES: ACCOUNTING                                   //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                           HELPERS                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////
}
