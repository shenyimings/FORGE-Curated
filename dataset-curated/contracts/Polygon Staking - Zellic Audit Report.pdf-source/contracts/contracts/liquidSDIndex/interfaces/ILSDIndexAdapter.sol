// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

interface ILSDIndexAdapter {
    /**
     * @notice returns the total amount deposits of this token in the index pool
     * @return total deposits amount
     */
    function getTotalDeposits() external view returns (uint256);

    /**
     * @notice returns the underlying amount that corresponds to the total deposits of this adapter's
     * token in the index pool
     * @return total underlying amount
     */
    function getTotalDepositsValue() external view returns (uint256);

    /**
     * @notice returns the underlying amount that corresponds to an LSD amount
     * @param _lsdAmount amount of LSD tokens
     * @return underlying amount
     */
    function getUnderlyingByLSD(uint256 _lsdAmount) external view returns (uint256);

    /**
     * @notice returns the LSD amount that corresponds to an underlying amount
     * @param _underlyingAmount underlying amount
     * @return LSD amount
     */
    function getLSDByUnderlying(uint256 _underlyingAmount) external view returns (uint256);

    /**
     * @notice returns the exchange rate between this token and the underlying token
     * @return exchange rate
     */
    function getExchangeRate() external view returns (uint256);
}
