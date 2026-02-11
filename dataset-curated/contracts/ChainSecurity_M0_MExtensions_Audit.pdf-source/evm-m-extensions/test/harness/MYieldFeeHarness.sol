// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import { MYieldFee } from "../../src/projects/yieldToAllWithFee/MYieldFee.sol";

contract MYieldFeeHarness is MYieldFee {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        string memory name,
        string memory symbol,
        address mToken,
        address swapFacility,
        uint16 feeRate,
        address feeRecipient,
        address admin,
        address yieldFeeManager,
        address claimRecipientManager
    ) public override initializer {
        super.initialize(
            name,
            symbol,
            mToken,
            swapFacility,
            feeRate,
            feeRecipient,
            admin,
            yieldFeeManager,
            claimRecipientManager
        );
    }

    function currentBlockTimestamp() external view returns (uint40) {
        return _latestEarnerRateAccrualTimestamp();
    }

    function currentEarnerRate() external view returns (uint32) {
        return _currentEarnerRate();
    }

    function setAccountOf(address account, uint256 balance, uint112 principal) external {
        MYieldFeeStorageStruct storage $ = _getMYieldFeeStorageLocation();

        $.balanceOf[account] = balance;
        $.principalOf[account] = principal;
    }

    function setLatestIndex(uint256 latestIndex_) external {
        _getMYieldFeeStorageLocation().latestIndex = uint128(latestIndex_);
    }

    function setLatestRate(uint256 latestRate_) external {
        _getMYieldFeeStorageLocation().latestRate = uint32(latestRate_);
    }

    function setLatestUpdateTimestamp(uint256 latestUpdateTimestamp_) external {
        _getMYieldFeeStorageLocation().latestUpdateTimestamp = uint40(latestUpdateTimestamp_);
    }

    function setTotalSupply(uint256 totalSupply_) external {
        _getMYieldFeeStorageLocation().totalSupply = totalSupply_;
    }

    function setTotalPrincipal(uint112 totalPrincipal_) external {
        _getMYieldFeeStorageLocation().totalPrincipal = totalPrincipal_;
    }
}
