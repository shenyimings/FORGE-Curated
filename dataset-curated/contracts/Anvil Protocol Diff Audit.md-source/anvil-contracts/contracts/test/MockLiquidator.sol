// SPDX-License-Identifier: ISC
pragma solidity 0.8.25;

import "../interfaces/ILiquidator.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title Liquidator that can be used to demonstrate liquidations via liquidator.
 */
contract MockLiquidator is ILiquidator {
    using SafeERC20 for IERC20;

    /**
     * @inheritdoc ILiquidator
     */
    function liquidate(
        address /*_initiator*/,
        address _inputTokenAddress,
        uint256 _inputTokenAmount,
        address _outputTokenAddress,
        uint256 _outputTokenAmount,
        bytes calldata /* not used */
    ) external {
        require(_inputTokenAmount > 0 && _outputTokenAmount > 0, "invalid input and/or output amount");

        // Transfer input tokens from the source to the Liquidator
        IERC20(_inputTokenAddress).safeTransferFrom(msg.sender, address(this), _inputTokenAmount);

        // Transfer sufficient amount of output tokens to the caller.
        IERC20(_outputTokenAddress).safeTransfer(msg.sender, _outputTokenAmount);
    }
}
