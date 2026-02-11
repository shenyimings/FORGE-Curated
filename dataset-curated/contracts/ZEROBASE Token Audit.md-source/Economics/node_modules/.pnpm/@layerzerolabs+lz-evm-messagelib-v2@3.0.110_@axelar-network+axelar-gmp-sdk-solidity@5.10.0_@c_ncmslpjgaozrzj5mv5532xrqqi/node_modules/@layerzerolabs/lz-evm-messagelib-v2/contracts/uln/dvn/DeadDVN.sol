// SPDX-License-Identifier: LZBL-1.2

pragma solidity ^0.8.20;

import { ILayerZeroDVN } from "../interfaces/ILayerZeroDVN.sol";

contract DeadDVN is ILayerZeroDVN {
    string internal constant ERROR_NOT_ALLOWED = "Please set your OApp's DVNs and/or Executor";

    /// @dev for ULN301, ULN302 and more to assign job
    function assignJob(AssignJobParam calldata, bytes calldata) external payable returns (uint256) {
        revert(ERROR_NOT_ALLOWED);
    }

    /// @dev to support ULNv2
    function assignJob(uint16, uint16, uint64, address) external pure returns (uint256) {
        revert(ERROR_NOT_ALLOWED);
    }

    // ========================= View =========================

    function getFee(uint32, uint64, address, bytes calldata) external pure returns (uint256) {
        revert(ERROR_NOT_ALLOWED);
    }

    /// @dev to support ULNv2
    function getFee(uint16, uint16, uint64, address) public pure returns (uint256) {
        revert(ERROR_NOT_ALLOWED);
    }
}
