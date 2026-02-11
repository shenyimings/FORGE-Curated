// SPDX-License-Identifier: ISC
pragma solidity 0.8.25;

interface ILiquidator {
    /**
     * @notice Called to provide input token in exchange for output token in the specified amounts.
     * @dev It is assumed that caller has approved the Liquidator to transfer the `_inputTokenAmount`.
     * @dev At a minimum, the implementer must send output token to `initiator`.
     * @param _initiator The original initiator of the liquidation, if necessary for payment by the ILiquidator.
     * @param _inputTokenAddress The address of the token the liquidator will receive from the caller.
     * @param _inputTokenAmount The amount of the token the liquidator will receive from the caller.
     * @param _outputTokenAddress The address of the token the caller will receive as a result of this call.
     * @param _outputTokenAmount The amount of the token the caller will receive as a result of this call.
     * @param _liquidatorParams Parameters, if any, to be parsed and used by the ILiquidator implementation contract.
     */
    function liquidate(
        address _initiator,
        address _inputTokenAddress,
        uint256 _inputTokenAmount,
        address _outputTokenAddress,
        uint256 _outputTokenAmount,
        bytes calldata _liquidatorParams
    ) external;
}
