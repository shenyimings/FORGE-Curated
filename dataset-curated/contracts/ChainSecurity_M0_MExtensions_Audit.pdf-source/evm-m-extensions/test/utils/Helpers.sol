// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import { UIntMath } from "../../lib/common/src/libs/UIntMath.sol";

contract Helpers {
    uint16 public constant ONE_HUNDRED_PERCENT = 10_000;

    function _getEarnerRate(uint32 mEarnerRate, uint32 feeRate) internal pure returns (uint32) {
        return UIntMath.safe32((uint256(ONE_HUNDRED_PERCENT - feeRate) * mEarnerRate) / ONE_HUNDRED_PERCENT);
    }

    function _getYieldFee(uint256 yield, uint16 feeRate) internal pure returns (uint256) {
        return yield == 0 ? 0 : (yield * feeRate) / ONE_HUNDRED_PERCENT;
    }
}
