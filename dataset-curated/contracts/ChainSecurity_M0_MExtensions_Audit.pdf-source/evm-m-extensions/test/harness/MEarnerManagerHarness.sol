// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import { MEarnerManager } from "../../src/projects/earnerManager/MEarnerManager.sol";

contract MEarnerManagerHarness is MEarnerManager {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        string memory name,
        string memory symbol,
        address mToken,
        address swapFacility,
        address admin,
        address earnerManager,
        address feeRecipient_
    ) public override initializer {
        super.initialize(name, symbol, mToken, swapFacility, admin, earnerManager, feeRecipient_);
    }

    function setAccountOf(
        address account,
        uint256 balance,
        uint112 principal,
        bool isWhitelisted,
        uint16 feeRate
    ) external {
        MEarnerManagerStorageStruct storage $ = _getMEarnerManagerStorageLocation();

        $.accounts[account].balance = balance;
        $.accounts[account].principal = principal;
        $.accounts[account].isWhitelisted = isWhitelisted;
        $.accounts[account].feeRate = feeRate;
    }

    function setTotalSupply(uint256 totalSupply_) external {
        _getMEarnerManagerStorageLocation().totalSupply = totalSupply_;
    }

    function setTotalPrincipal(uint112 totalPrincipal_) external {
        _getMEarnerManagerStorageLocation().totalPrincipal = totalPrincipal_;
    }

    // function setFeeRecipient
}
