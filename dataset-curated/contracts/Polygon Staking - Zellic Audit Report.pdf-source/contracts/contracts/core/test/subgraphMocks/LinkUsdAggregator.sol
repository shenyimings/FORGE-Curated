// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract MockLinkUsdAggregator {
    /**
     * @notice Reads the current answer from aggregator delegated to.
     * @dev overridden function to add the checkAccess() modifier
     *
     * @dev #[deprecated] Use latestRoundData instead. This does not error if no
     * answer has been reached, it will simply return 0. Either wait to point to
     * an already answered Aggregator or use the recommended latestRoundData
     * instead which includes better verification information.
     */
    function latestAnswer() public view checkAccess returns (int256) {
        return 1110908500;
    }

    // Mock of checkAccess modifier to allow compilation
    modifier checkAccess() {
        _;
    }
}
