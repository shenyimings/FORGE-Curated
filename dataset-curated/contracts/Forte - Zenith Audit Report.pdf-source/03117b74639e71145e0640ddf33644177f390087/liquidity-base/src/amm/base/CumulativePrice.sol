// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

/**
 * @title Cumulative Price Contract
 * @dev This contract tracks the price of the contract at the end of every block
 * @author  @oscarsernarosero @cirsteve @Palmerg4
 */
contract CumulativePrice {
    uint256 public cumulativePrice;
    uint256 public lastBlockTimestamp;

    /**
     * @dev This function updates the cumulativePrice and lastBlockTimestamp.
     * @param _price the current spot price 
     * @param _timestamp the current block timestamp
     */
    function _updateCumulativePrice(uint256 _price, uint256 _timestamp) internal {
        uint256 timeElapsed = _timestamp  - lastBlockTimestamp;
        if (timeElapsed >= 0 ) {
            cumulativePrice += _price * timeElapsed;
        }
        lastBlockTimestamp = block.timestamp;
    }
}