// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2025 Steakhouse Financial
pragma solidity 0.8.28;

import {FundingAave, IPool} from "../FundingAave.sol";

contract FundingAaveFactory {
    /* STORAGE */

    mapping(address account => bool) public isFundingAave;

    /* EVENTS */
    event CreateFundingAave(address indexed owner, address indexed pool, uint8 indexed eMode, FundingAave fundingAave);

    /* FUNCTIONS */

    function createFundingAave(address _owner, IPool _pool, uint8 _eMode) external returns (FundingAave) {
        FundingAave _funding = new FundingAave(_owner, _pool, _eMode);

        isFundingAave[address(_funding)] = true;

        emit CreateFundingAave(_owner, address(_pool), _eMode, _funding);

        return _funding;
    }
}
