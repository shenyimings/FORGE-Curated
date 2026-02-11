// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Libraries
import {UtilsLib} from "src/libraries/UtilsLib.sol";
import {IEulerEarnHandler} from "../handlers/interfaces/IEulerEarnHandler.sol";
import {ConstantsLib} from "src/libraries/ConstantsLib.sol";
import "forge-std/console.sol";

// Test Contracts
import {BaseHooks} from "../base/BaseHooks.t.sol";

// Interfaces
import {IERC4626, IERC20} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {IERC20Handler} from "../handlers/interfaces/IERC20Handler.sol";
import {IEulerEarn} from "src/interfaces/IEulerEarn.sol";
import {IEulerEarnAdminHandler} from "../handlers/interfaces/IEulerEarnAdminHandler.sol";
import {IPublicAllocatorHandler} from "../handlers/interfaces/IPublicAllocatorHandler.sol";

/// @title Default Before After Hooks
/// @notice Helper contract for before and after hooks
/// @dev This contract is inherited by handlers
abstract contract DefaultBeforeAfterHooks is BaseHooks {
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                         STRUCTS                                           //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    struct User {
        uint256 eulerEarnBalance;
    }

    struct MarketData {
        uint256 nextCapTime;
        uint256 cap;
        uint256 removableAt;
        bool enabled;
    }

    struct EulerEarnData {
        // Accounting
        uint256 totalSupply;
        uint256 totalAssets;
        uint256 lastTotalAssets;
        uint256 lostAssets;
        // Fees
        uint256 fee;
        uint256 feeRecipientBalance;
        address feeRecipient;
        uint256 feeRecipientSharesBalance;
        // Times
        uint256 nextGuardianUpdateTime;
        uint256 nextTimelockDecreaseTime;
        uint256 timelock;
        // Addresses
        address guardian;
        // Markets
        mapping(IERC4626 => MarketData) markets;
        // Users
        mapping(address => User) users;
    }

    struct DefaultVars {
        mapping(address => EulerEarnData) eulerEarnVaults;
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                       HOOKS STORAGE                                       //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    DefaultVars defaultVarsBefore;
    DefaultVars defaultVarsAfter;

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                           SETUP                                           //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice Default hooks setup
    function _setUpDefaultHooks() internal {}

    /// @notice Helper to initialize storage arrays of default vars
    function _setUpDefaultVars(DefaultVars storage _defaultVars) internal {}

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                           HOOKS                                           //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function _defaultHooksBefore() internal {
        // Default values
        for (uint256 i; i < eulerEarnVaults.length; i++) {
            _setDefaultValues(defaultVarsBefore.eulerEarnVaults[eulerEarnVaults[i]], IEulerEarn(eulerEarnVaults[i]));

            // User account data
            _setUserValues(defaultVarsBefore.eulerEarnVaults[eulerEarnVaults[i]], eulerEarnVaults[i]);
        }
    }

    function _defaultHooksAfter() internal {
        // Default values
        for (uint256 i; i < eulerEarnVaults.length; i++) {
            _setDefaultValues(defaultVarsAfter.eulerEarnVaults[eulerEarnVaults[i]], IEulerEarn(eulerEarnVaults[i]));

            // User account data
            _setUserValues(defaultVarsAfter.eulerEarnVaults[eulerEarnVaults[i]], eulerEarnVaults[i]);
        }
    }

    /*/////////////////////////////////////////////////////////////////////////////////////////////
    //                                       HELPERS                                             //
    /////////////////////////////////////////////////////////////////////////////////////////////*/

    function _setDefaultValues(EulerEarnData storage _eulerEarnData, IEulerEarn _vault) internal {
        // Asset
        _eulerEarnData.totalSupply = _vault.totalSupply();
        _eulerEarnData.totalAssets = _vault.totalAssets();
        _eulerEarnData.lastTotalAssets = _vault.lastTotalAssets();
        _eulerEarnData.lostAssets = _vault.lostAssets();
        // Fees
        _eulerEarnData.fee = _vault.fee();
        _eulerEarnData.feeRecipient = _vault.feeRecipient();
        _eulerEarnData.feeRecipientBalance =
            loanToken.balanceOf(defaultVarsBefore.eulerEarnVaults[address(_vault)].feeRecipient);
        _eulerEarnData.feeRecipientSharesBalance =
            _vault.balanceOf(defaultVarsBefore.eulerEarnVaults[address(_vault)].feeRecipient);
        // Times
        _eulerEarnData.nextGuardianUpdateTime = _vault.pendingGuardian().validAt;
        _eulerEarnData.nextTimelockDecreaseTime = _vault.pendingTimelock().validAt;
        _eulerEarnData.timelock = _vault.timelock();

        // Addresses
        _eulerEarnData.guardian = _vault.guardian();

        // Markets
        for (uint256 i; i < allMarkets[address(_vault)].length; i++) {
            IERC4626 market = allMarkets[address(_vault)][i];
            _eulerEarnData.markets[market] = MarketData({
                nextCapTime: _vault.pendingCap(market).validAt,
                cap: _vault.pendingCap(market).value,
                removableAt: _vault.config(market).removableAt,
                enabled: _vault.config(market).enabled
            });
        }
    }

    function _setUserValues(EulerEarnData storage _eulerEarnData, address eulerEarnAddress) internal {
        for (uint256 i; i < actorAddresses.length; i++) {
            _eulerEarnData.users[actorAddresses[i]].eulerEarnBalance =
                IERC4626(eulerEarnAddress).balanceOf(actorAddresses[i]);
        }
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                   POST CONDITIONS: BASE                                   //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function assert_GPOST_BASE_B(address eulerEarnAddress, IERC4626 market) internal {
        if (
            msg.sig != IEulerEarnAdminHandler.revokePendingCap.selector
                && msg.sig != IEulerEarnAdminHandler.acceptCap.selector
        ) {
            assertGe(
                defaultVarsAfter.eulerEarnVaults[eulerEarnAddress].markets[market].nextCapTime,
                defaultVarsBefore.eulerEarnVaults[eulerEarnAddress].markets[market].nextCapTime,
                GPOST_BASE_B
            );
        }

        if (_hasCapIncreased(eulerEarnAddress, market)) {
            assertGt(
                block.timestamp,
                defaultVarsBefore.eulerEarnVaults[eulerEarnAddress].markets[market].nextCapTime,
                GPOST_BASE_B
            );
        }
    }

    function assert_GPOST_BASE_C(address eulerEarnAddress) internal {
        if (
            msg.sig != IEulerEarnAdminHandler.revokePendingTimelock.selector
                && msg.sig != IEulerEarnAdminHandler.acceptTimelock.selector
        ) {
            assertGe(
                defaultVarsAfter.eulerEarnVaults[eulerEarnAddress].nextTimelockDecreaseTime,
                defaultVarsBefore.eulerEarnVaults[eulerEarnAddress].nextTimelockDecreaseTime,
                GPOST_BASE_C
            );
        }

        if (_hasTimelockDecreased(eulerEarnAddress)) {
            assertGt(
                block.timestamp,
                defaultVarsBefore.eulerEarnVaults[eulerEarnAddress].nextTimelockDecreaseTime,
                GPOST_BASE_C
            );
        }
    }

    function assert_GPOST_BASE_D(address eulerEarnAddress, IERC4626 market) internal {
        if (msg.sig != IEulerEarnAdminHandler.revokePendingMarketRemoval.selector) {
            assertGe(
                defaultVarsAfter.eulerEarnVaults[eulerEarnAddress].markets[market].removableAt,
                defaultVarsBefore.eulerEarnVaults[eulerEarnAddress].markets[market].removableAt,
                GPOST_BASE_D
            );
        }

        if (_hasMarketBeenRemoved(eulerEarnAddress, market)) {
            assertGt(
                block.timestamp,
                defaultVarsBefore.eulerEarnVaults[eulerEarnAddress].markets[market].removableAt,
                GPOST_BASE_D
            );
        }
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                   POST CONDITIONS: FEES                                   //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function assert_GPOST_FEES_A(address eulerEarnAddress) internal {
        uint256 feeRecipientBalanceDelta = UtilsLib.zeroFloorSub(
            defaultVarsAfter.eulerEarnVaults[eulerEarnAddress].feeRecipientBalance,
            defaultVarsBefore.eulerEarnVaults[eulerEarnAddress].feeRecipientBalance
        );
        if (feeRecipientBalanceDelta != 0) {
            assertEq(feeRecipientBalanceDelta, defaultVarsBefore.eulerEarnVaults[eulerEarnAddress].fee, GPOST_FEES_A);
        }
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                 POST CONDITIONS: ACCOUNTING                               //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function assert_GPOST_ACCOUNTING_A() internal {
        if (_isEulerEarnVault(target)) {
            if (msg.sig != IEulerEarnHandler.withdrawEEV.selector && msg.sig != IEulerEarnHandler.redeemEEV.selector) {
                if (msg.sig == IPublicAllocatorHandler.reallocateTo.selector) {
                    if (
                        defaultVarsAfter.eulerEarnVaults[target].totalAssets
                            < defaultVarsBefore.eulerEarnVaults[target].totalAssets
                    ) {
                        assertLe(
                            defaultVarsBefore.eulerEarnVaults[target].totalAssets
                                - defaultVarsAfter.eulerEarnVaults[target].totalAssets,
                            1,
                            GPOST_ACCOUNTING_A
                        );
                    }
                } else {
                    assertGe(
                        defaultVarsAfter.eulerEarnVaults[target].totalAssets,
                        defaultVarsBefore.eulerEarnVaults[target].totalAssets,
                        GPOST_ACCOUNTING_A
                    );
                }
            }
        }
    }

    function assert_GPOST_ACCOUNTING_B() internal {
        if (_isEulerEarnVault(target)) {
            if (
                defaultVarsAfter.eulerEarnVaults[target].totalAssets
                    > defaultVarsBefore.eulerEarnVaults[target].totalAssets
            ) {
                assertTrue(
                    (
                        msg.sig == IEulerEarnHandler.depositEEV.selector
                            || msg.sig == IEulerEarnHandler.mintEEV.selector
                            || msg.sig == IEulerEarnAdminHandler.acceptCap.selector
                            || (
                                defaultVarsBefore.eulerEarnVaults[target].totalAssets
                                    > defaultVarsBefore.eulerEarnVaults[target].lastTotalAssets
                            )
                    ),
                    GPOST_ACCOUNTING_B
                );
            }
        }
    }

    function assert_GPOST_ACCOUNTING_C(address eulerEarnAddress) internal {
        if (
            defaultVarsAfter.eulerEarnVaults[eulerEarnAddress].totalSupply
                > defaultVarsBefore.eulerEarnVaults[eulerEarnAddress].totalSupply
        ) {
            assertTrue(
                (msg.sig == IEulerEarnHandler.depositEEV.selector || msg.sig == IEulerEarnHandler.mintEEV.selector)
                    || defaultVarsBefore.eulerEarnVaults[eulerEarnAddress].fee != 0
                    || msg.sig == IPublicAllocatorHandler.reallocateTo.selector,
                /// @dev eulerEarn is also a depositor on eulerEarn2
                GPOST_ACCOUNTING_C
            );
        }
    }

    function assert_GPOST_ACCOUNTING_D() internal {
        if (_isEulerEarnVault(target)) {
            if (
                defaultVarsAfter.eulerEarnVaults[target].totalSupply
                    < defaultVarsBefore.eulerEarnVaults[target].totalSupply
            ) {
                assertTrue(
                    msg.sig == IEulerEarnHandler.withdrawEEV.selector || msg.sig == IEulerEarnHandler.redeemEEV.selector,
                    GPOST_ACCOUNTING_D
                );
            }
        }
    }

    function assert_GPOST_ACCOUNTING_F(address eulerEarnAddress) internal {
        if (_isEulerEarnVault(target)) {
            assertGe(
                defaultVarsAfter.eulerEarnVaults[eulerEarnAddress].lostAssets,
                defaultVarsBefore.eulerEarnVaults[eulerEarnAddress].lostAssets,
                GPOST_ACCOUNTING_F
            );
        }
    }

    function assert_GPOST_ACCOUNTING_G(address eulerEarnAddress) internal {
        if (_isEulerEarnVaultAndTarget(eulerEarnAddress) && _functionAccruesInterest(msg.sig)) {
            uint256 lastTotalAssetsPositiveDelta = UtilsLib.zeroFloorSub(
                defaultVarsBefore.eulerEarnVaults[eulerEarnAddress].totalAssets,
                defaultVarsBefore.eulerEarnVaults[eulerEarnAddress].lastTotalAssets
            );

            if (lastTotalAssetsPositiveDelta != 0) {
                int256 realActionAssetDelta = actionAssetDelta + int256(lastTotalAssetsPositiveDelta);
                assertEq(
                    defaultVarsAfter.eulerEarnVaults[eulerEarnAddress].lastTotalAssets,
                    uint256(
                        int256(defaultVarsBefore.eulerEarnVaults[eulerEarnAddress].lastTotalAssets)
                            + realActionAssetDelta
                    ),
                    GPOST_ACCOUNTING_G
                );
            }
        }
    }

    function assert_GPOST_ACCOUNTING_H(address eulerEarnAddress) internal {
        if (_isEulerEarnVaultAndTarget(eulerEarnAddress) && _functionAccruesInterest(msg.sig)) {
            uint256 lastTotalAssetsNegativeDelta = UtilsLib.zeroFloorSub(
                defaultVarsBefore.eulerEarnVaults[eulerEarnAddress].lastTotalAssets,
                defaultVarsBefore.eulerEarnVaults[eulerEarnAddress].totalAssets
            );
            if (lastTotalAssetsNegativeDelta != 0) {
                assertEq(
                    defaultVarsAfter.eulerEarnVaults[eulerEarnAddress].lostAssets,
                    defaultVarsBefore.eulerEarnVaults[eulerEarnAddress].lostAssets + lastTotalAssetsNegativeDelta,
                    GPOST_ACCOUNTING_H
                );
            }
        }
    }

    function assert_GPOST_ACCOUNTING_I(address eulerEarnAddress) internal {
        if (_isEulerEarnVault(target)) {
            uint256 sharePriceBefore = _getSharePrice(
                defaultVarsBefore.eulerEarnVaults[eulerEarnAddress].totalSupply,
                defaultVarsBefore.eulerEarnVaults[eulerEarnAddress].totalAssets
            );
            uint256 sharePriceAfter = _getSharePrice(
                defaultVarsAfter.eulerEarnVaults[eulerEarnAddress].totalSupply,
                defaultVarsAfter.eulerEarnVaults[eulerEarnAddress].totalAssets
            );

            if (
                defaultVarsAfter.eulerEarnVaults[eulerEarnAddress].feeRecipientSharesBalance
                    == defaultVarsBefore.eulerEarnVaults[eulerEarnAddress].feeRecipientSharesBalance && sharePriceAfter != 0
            ) {
                assertGe(sharePriceAfter, sharePriceBefore, GPOST_ACCOUNTING_I);
            }
        }
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                          HELPERS                                          //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function _hasCapIncreased(address eulerEarnAddress, IERC4626 market) internal view returns (bool) {
        return defaultVarsBefore.eulerEarnVaults[eulerEarnAddress].markets[market].cap
            < defaultVarsAfter.eulerEarnVaults[eulerEarnAddress].markets[market].cap;
    }

    function _hasTimelockDecreased(address eulerEarnAddress) internal view returns (bool) {
        return defaultVarsBefore.eulerEarnVaults[eulerEarnAddress].timelock
            > defaultVarsAfter.eulerEarnVaults[eulerEarnAddress].timelock;
    }

    function _hasMarketBeenRemoved(address eulerEarnAddress, IERC4626 market) internal view returns (bool) {
        return defaultVarsBefore.eulerEarnVaults[eulerEarnAddress].markets[market].enabled
            && !defaultVarsAfter.eulerEarnVaults[eulerEarnAddress].markets[market].enabled;
    }

    function _balanceHasNotChanged(address eulerEarnAddress) internal view returns (bool) {
        for (uint256 i; i < actorAddresses.length; i++) {
            if (
                defaultVarsBefore.eulerEarnVaults[eulerEarnAddress].users[actorAddresses[i]].eulerEarnBalance
                    != defaultVarsAfter.eulerEarnVaults[eulerEarnAddress].users[actorAddresses[i]].eulerEarnBalance
            ) {
                return false;
            }
        }

        return true;
    }

    function _functionAccruesInterest(bytes4 functionSelector) internal pure returns (bool) {
        return functionSelector == IEulerEarnHandler.depositEEV.selector
            || functionSelector == IEulerEarnHandler.mintEEV.selector
            || functionSelector == IEulerEarnHandler.withdrawEEV.selector
            || functionSelector == IEulerEarnHandler.redeemEEV.selector
            || functionSelector == IEulerEarnAdminHandler.setFee.selector
            || functionSelector == IEulerEarnAdminHandler.setFeeRecipient.selector;
    }

    function _getSharePrice(uint256 totalSupply, uint256 totalAssets) internal pure returns (uint256) {
        return (totalSupply == 0)
            ? 0
            : (totalAssets + ConstantsLib.VIRTUAL_AMOUNT) * 1e18 / (totalSupply + ConstantsLib.VIRTUAL_AMOUNT);
    }
}
