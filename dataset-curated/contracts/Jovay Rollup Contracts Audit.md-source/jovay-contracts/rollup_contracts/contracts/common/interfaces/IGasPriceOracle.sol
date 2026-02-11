// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IGasPriceOracle {
    event BaseFeeChanged(uint256 oldL2BaseFee, uint256 newL2BaseFee);

    /**
     * @notice Estimates the cost of sending a message from L2 to L1.
     * @param gasLimit_ The gas limit for the transaction on L2.
     */
    function estimateMsgFee(uint256 gasLimit_) external view returns (uint256);

    /**
     * @notice Sets the base fee.
     * @param newBaseFee_ The new base fee.
     */
    function setBaseFee(uint256 newBaseFee_) external;
}
