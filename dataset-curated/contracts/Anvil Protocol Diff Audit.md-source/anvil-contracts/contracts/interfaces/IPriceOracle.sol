// SPDX-License-Identifier: ISC
pragma solidity 0.8.25;

import "../Pricing.sol";

/**
 * @title Defines the interface that PriceOracles must implement to be used within the LOC ecosystem.
 */
interface IPriceOracle {
    /**
     * @notice Gets the existing price to trade the provided input token for the provided output token.
     * @param _inputTokenAddress The address of the token to be [hypothetically] sent in a trade.
     * @param _outputTokenAddress The address of the token to be [hypothetically] received in a trade.
     * @return _price The `OraclePrice` for the specified trading pair.
     */
    function getPrice(
        address _inputTokenAddress,
        address _outputTokenAddress
    ) external returns (Pricing.OraclePrice memory _price);

    /*
     * @notice Pushes an oracle price update to the oracle update logic for a trading pair, returning updated price.
     * @dev Under the hood, return price should come from `getPrice(...)` to ensure that this returned price _always_
     * matches the price that a caller would get by immediately calling `getPrice(...)` after update.
     * @dev If the update is invalid or does not work for some reason, the transaction should revert, except in the case
     * in which a newer price already exists. In that case, the update should succeed as a no-op.
     * @param _inputTokenAddress The address of the token to be [hypothetically] sent in a trade.
     * @param _outputTokenAddress The address of the token to be [hypothetically] received in a trade.
     * @param _oracleData The oracle price data necessary for the implementation to verify content and update price.
     * @return _price The updated price set by the `_oracleData`.
     */
    function updatePrice(
        address _inputTokenAddress,
        address _outputTokenAddress,
        bytes calldata _oracleData
    ) external payable returns (Pricing.OraclePrice memory _price);

    /**
     * @notice Gets the fee required to use the provided `_oracleData` in a call to `updatePrice`.
     * @param _oracleData The oracle data bytes that may be passed to updatePrice.
     * @return _feeAmount The fee that must be passed as msg.value to `updatePrice` to submit the provided oracle data.
     */
    function getUpdateFee(bytes calldata _oracleData) external view returns (uint256 _feeAmount);
}
