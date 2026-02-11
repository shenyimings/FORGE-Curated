// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2025.
pragma solidity ^0.8.23;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {ICreditAccountV3} from "@gearbox-protocol/core-v3/contracts/interfaces/ICreditAccountV3.sol";
import {ICreditFacadeV3} from "@gearbox-protocol/core-v3/contracts/interfaces/ICreditFacadeV3.sol";
import {
    CollateralCalcTask,
    CollateralDebtData,
    ICreditManagerV3
} from "@gearbox-protocol/core-v3/contracts/interfaces/ICreditManagerV3.sol";
import {IPoolQuotaKeeperV3} from "@gearbox-protocol/core-v3/contracts/interfaces/IPoolQuotaKeeperV3.sol";

import {ICreditAccountCompressor} from "../interfaces/ICreditAccountCompressor.sol";

import {AP_CREDIT_ACCOUNT_COMPRESSOR} from "../libraries/Literals.sol";

import {CreditAccountData, TokenInfo} from "../types/CreditAccountState.sol";
import {CreditAccountFilter, CreditManagerFilter} from "../types/Filters.sol";

import {BaseCompressor} from "./BaseCompressor.sol";

/// @title  Credit account compressor
/// @notice Allows to fetch data on all credit accounts matching certain criteria in an efficient manner
/// @dev    The contract is not gas optimized and is thus not recommended for on-chain use
/// @dev    Querying functions try to process as many accounts as possible and stop when they get close to gas limit
contract CreditAccountCompressor is BaseCompressor, ICreditAccountCompressor {
    /// @notice Contract version
    uint256 public constant override version = 3_10;

    /// @notice Contract type
    bytes32 public constant override contractType = AP_CREDIT_ACCOUNT_COMPRESSOR;

    /// @notice Constructor
    /// @param  addressProvider_ Address provider contract address
    constructor(address addressProvider_) BaseCompressor(addressProvider_) {}

    // -------- //
    // QUERYING //
    // -------- //

    /// @notice Returns data for a particular `creditAccount`
    function getCreditAccountData(address creditAccount) external view returns (CreditAccountData memory) {
        address creditManager = ICreditAccountV3(creditAccount).creditManager();
        return _getCreditAccountData(creditAccount, creditManager);
    }

    /// @notice Returns data for credit accounts that match `caFilter` in credit managers matching `cmFilter`
    /// @dev    The non-zero value of `nextOffset` return variable indicates that gas supplied with a call was
    ///         insufficient to process all the accounts and next iteration starting from this value is needed
    function getCreditAccounts(CreditManagerFilter memory cmFilter, CreditAccountFilter memory caFilter, uint256 offset)
        external
        view
        returns (CreditAccountData[] memory data, uint256 nextOffset)
    {
        address[] memory creditManagers = _getCreditManagers(cmFilter);
        return _getCreditAccounts(creditManagers, caFilter, offset, type(uint256).max);
    }

    /// @dev Same as above but with `limit` parameter that specifies the number of accounts to process
    function getCreditAccounts(
        CreditManagerFilter memory cmFilter,
        CreditAccountFilter memory caFilter,
        uint256 offset,
        uint256 limit
    ) public view returns (CreditAccountData[] memory data, uint256 nextOffset) {
        address[] memory creditManagers = _getCreditManagers(cmFilter);
        return _getCreditAccounts(creditManagers, caFilter, offset, limit);
    }

    /// @notice Returns data for credit accounts that match `caFilter` in a given `creditManager`
    /// @dev    The non-zero value of `nextOffset` return variable indicates that gas supplied with a call was
    ///         insufficient to process all the accounts and next iteration starting from this value is needed
    function getCreditAccounts(address creditManager, CreditAccountFilter memory caFilter, uint256 offset)
        external
        view
        returns (CreditAccountData[] memory data, uint256 nextOffset)
    {
        address[] memory creditManagers = new address[](1);
        creditManagers[0] = creditManager;
        return _getCreditAccounts(creditManagers, caFilter, offset, type(uint256).max);
    }

    /// @dev Same as above but with `limit` parameter that specifies the number of accounts to process
    function getCreditAccounts(
        address creditManager,
        CreditAccountFilter memory caFilter,
        uint256 offset,
        uint256 limit
    ) external view returns (CreditAccountData[] memory data, uint256 nextOffset) {
        address[] memory creditManagers = new address[](1);
        creditManagers[0] = creditManager;
        return _getCreditAccounts(creditManagers, caFilter, offset, limit);
    }

    // -------- //
    // COUNTING //
    // -------- //

    /// @notice Counts credit accounts that match `caFilter` in credit managers matching `cmFilter`
    function countCreditAccounts(CreditManagerFilter memory cmFilter, CreditAccountFilter memory caFilter)
        external
        view
        returns (uint256)
    {
        address[] memory creditManagers = _getCreditManagers(cmFilter);
        return _countCreditAccounts(creditManagers, caFilter, 0, type(uint256).max);
    }

    /// @notice Counts credit accounts that match `caFilter` in a given `creditManager`
    function countCreditAccounts(address creditManager, CreditAccountFilter memory caFilter)
        external
        view
        returns (uint256)
    {
        address[] memory creditManagers = new address[](1);
        creditManagers[0] = creditManager;
        return _countCreditAccounts(creditManagers, caFilter, 0, type(uint256).max);
    }

    // --------- //
    // INTERNALS //
    // --------- //

    /// @dev Querying implementation
    function _getCreditAccounts(
        address[] memory creditManagers,
        CreditAccountFilter memory filter,
        uint256 offset,
        uint256 limit
    ) internal view returns (CreditAccountData[] memory data, uint256 nextOffset) {
        uint256 num = _countCreditAccounts(creditManagers, filter, offset, limit);
        if (num == 0) return (data, 0);

        // allocating the `CreditAccountData` array might consume most of the gas leaving no room for computations,
        // so we instead allocate and gradually fill the array of pointers to structs which takes much less space
        bytes32[] memory dataPointers = new bytes32[](num);
        uint256 dataOffset;

        // to adjust to RPC provider's call gas limit, the function stops when gas left gets below gas reserve, which
        // starts at this number that should be enough to cover a single account processing, and increases with each
        // new data struct to accommodate the cost of memory expansion that happens upon ABI-encoding returned data
        uint256 gasReserve = 2e6;

        nextOffset = offset;
        for (uint256 i; i < creditManagers.length; ++i) {
            address creditManager = creditManagers[i];
            uint256 len = ICreditManagerV3(creditManager).creditAccountsLen();

            // first, we need to get to the `offset` position
            if (len <= offset) {
                offset -= len;
                continue;
            }

            uint256 count = Math.min(len - offset, limit);
            address[] memory creditAccounts = ICreditManagerV3(creditManager).creditAccounts(offset, count);

            // circumvent the "Stack too deep." error
            CreditAccountFilter memory filter_ = filter;

            for (uint256 j; j < creditAccounts.length; ++j) {
                address creditAccount = creditAccounts[j];
                if (_checkFilterMatch(creditAccount, creditManager, filter_)) {
                    uint256 gasBefore = gasleft();

                    CreditAccountData memory d = _getCreditAccountData(creditAccount, creditManager);
                    ++dataOffset;
                    assembly {
                        // save the pointer to created struct
                        mstore(add(dataPointers, mul(0x20, dataOffset)), d)
                    }

                    // rough approximation of gas that will be needed to accommodate additional memory expansion cost
                    gasReserve += (gasBefore - gasleft()) / 2;
                }
                --count;

                if (dataOffset == num || gasleft() < gasReserve) break;
            }

            nextOffset += creditAccounts.length - count;
            if (dataOffset == num || count != 0) break;

            limit -= creditAccounts.length;
            if (limit == 0) break;
            offset = 0;
        }

        assembly {
            // cast array of pointers to structs to array of structs
            data := dataPointers
            // trim array to its actual size
            mstore(data, dataOffset)
        }

        // set `nextOffset` to zero to indicate that scanning is finished
        if (dataOffset == num) nextOffset = 0;
    }

    /// @dev Counting implementation
    function _countCreditAccounts(
        address[] memory creditManagers,
        CreditAccountFilter memory filter,
        uint256 offset,
        uint256 limit
    ) internal view returns (uint256 num) {
        for (uint256 i; i < creditManagers.length; ++i) {
            address creditManager = creditManagers[i];
            uint256 len = ICreditManagerV3(creditManager).creditAccountsLen();

            // first, we need to get to the `offset` position
            if (len <= offset) {
                offset -= len;
                continue;
            }

            address[] memory creditAccounts =
                ICreditManagerV3(creditManager).creditAccounts(offset, Math.min(len - offset, limit));
            for (uint256 j; j < creditAccounts.length; ++j) {
                if (_checkFilterMatch(creditAccounts[j], creditManager, filter)) {
                    ++num;
                }
            }

            limit -= creditAccounts.length;
            if (limit == 0) break;
            offset = 0;
        }
    }

    /// @dev Data loading implementation
    function _getCreditAccountData(address creditAccount, address creditManager)
        internal
        view
        returns (CreditAccountData memory data)
    {
        data.creditAccount = creditAccount;
        data.creditManager = creditManager;
        data.creditFacade = ICreditManagerV3(creditManager).creditFacade();
        data.underlying = ICreditManagerV3(creditManager).underlying();
        data.owner = ICreditManagerV3(creditManager).getBorrowerOrRevert(creditAccount);
        data.expirationDate = ICreditFacadeV3(data.creditFacade).expirationDate();

        CollateralDebtData memory cdd =
            ICreditManagerV3(creditManager).calcDebtAndCollateral(creditAccount, CollateralCalcTask.DEBT_ONLY);
        data.enabledTokensMask = cdd.enabledTokensMask;
        data.debt = cdd.debt;
        data.accruedInterest = cdd.accruedInterest;
        data.accruedFees = cdd.accruedFees;

        // collateral is computed separately since it might revert on `balanceOf` and `latestRoundData` calls
        try ICreditManagerV3(creditManager).calcDebtAndCollateral(creditAccount, CollateralCalcTask.DEBT_COLLATERAL)
        returns (CollateralDebtData memory cdd_) {
            data.totalDebtUSD = cdd_.totalDebtUSD;
            data.totalValueUSD = cdd_.totalValueUSD;
            data.twvUSD = cdd_.twvUSD;
            data.totalValue = cdd_.totalValue;
            data.healthFactor = _calcHealthFactor(cdd_);
            data.success = true;
        } catch {}

        uint256 maxTokens = ICreditManagerV3(creditManager).collateralTokensCount();

        // the function is called for every account, so allocating an array of size `maxTokens` and trimming it
        // might cause issues with memory expansion and we must count the precise number of tokens in advance
        uint256 numTokens;
        uint256 returnedTokensMask;
        for (uint256 k; k < maxTokens; ++k) {
            uint256 mask = 1 << k;
            if (cdd.enabledTokensMask & mask == 0) {
                address token = ICreditManagerV3(creditManager).getTokenByMask(mask);
                try IERC20(token).balanceOf(creditAccount) returns (uint256 balance) {
                    if (balance <= 1) continue;
                } catch {
                    continue;
                }
            }
            ++numTokens;
            returnedTokensMask |= mask;
        }

        data.tokens = new TokenInfo[](numTokens);
        uint256 i;
        while (returnedTokensMask != 0) {
            uint256 mask = returnedTokensMask & uint256(-int256(returnedTokensMask));
            address token = ICreditManagerV3(creditManager).getTokenByMask(mask);
            data.tokens[i].token = token;
            data.tokens[i].mask = mask;

            try IERC20(token).balanceOf(creditAccount) returns (uint256 balance) {
                data.tokens[i].balance = balance;
                data.tokens[i].success = true;
            } catch {}

            if (IPoolQuotaKeeperV3(cdd._poolQuotaKeeper).isQuotedToken(token)) {
                (data.tokens[i].quota,) =
                    IPoolQuotaKeeperV3(cdd._poolQuotaKeeper).getQuotaAndOutstandingInterest(creditAccount, token);
            }

            returnedTokensMask ^= mask;
            ++i;
        }
    }

    /// @dev Credit account filtering implementation
    function _checkFilterMatch(address creditAccount, address creditManager, CreditAccountFilter memory filter)
        internal
        view
        returns (bool)
    {
        if (filter.owner != address(0)) {
            address owner = ICreditManagerV3(creditManager).getBorrowerOrRevert(creditAccount);
            if (owner != filter.owner) return false;
        }

        if (!filter.includeZeroDebt) {
            (uint256 debt,,,,,,,) = ICreditManagerV3(creditManager).creditAccountInfo(creditAccount);
            if (debt == 0) return false;
        }

        if (filter.minHealthFactor != 0 || filter.maxHealthFactor != 0 || filter.reverting) {
            try ICreditManagerV3(creditManager).calcDebtAndCollateral(creditAccount, CollateralCalcTask.DEBT_COLLATERAL)
            returns (CollateralDebtData memory cdd) {
                if (filter.reverting) return false;
                uint256 healthFactor = _calcHealthFactor(cdd);
                if (filter.minHealthFactor != 0 && healthFactor < filter.minHealthFactor) return false;
                if (filter.maxHealthFactor != 0 && healthFactor > filter.maxHealthFactor) return false;
            } catch {
                if (!filter.reverting) return false;
            }
        }

        return true;
    }

    /// @dev Calculates health factor with 18 decimals precision, returns `type(uint256).max` if debt is zero
    function _calcHealthFactor(CollateralDebtData memory cdd) internal pure returns (uint256) {
        return cdd.totalDebtUSD == 0 ? type(uint256).max : cdd.twvUSD * 1e18 / cdd.totalDebtUSD;
    }
}
