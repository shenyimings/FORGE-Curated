// SPDX-License-Identifier: ISC
pragma solidity 0.8.25;

import "./interfaces/ILiquidator.sol";

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router01.sol";

/**
 * @notice ILiquidator implementation that liquidates through Uniswap and
 * sends any remaining tokens to the beneficiary if there is one and the original caller if not.
 */
contract UniswapLiquidator is ILiquidator, Ownable2Step {
    IUniswapV2Router01 public uniswapRouter;
    address public beneficiary;

    event Liquidation(
        address indexed inputTokenAddress,
        uint256 inputTokenAmount,
        address indexed outputTokenAddress,
        uint256 outputTokenAmount,
        uint256 excessInputTokens
    );

    event LiquidationBenficiaryUpdate(address oldBeneficiary, address newBeneficiary);

    constructor(address _owner, address _beneficiary, IUniswapV2Router01 _uniswapRouter) Ownable(_owner) {
        beneficiary = _beneficiary;
        uniswapRouter = _uniswapRouter;
    }

    /**
     * @notice Called to provide input token in exchange for output token in the specified amounts.
     * @dev It is assumed that caller has approved the Liquidator to transfer the `_inputTokenAmount`.
     * @dev At a minimum, the implementer must send output token to `initiator`.
     * @param _initiator The address that originally initiated this liquidation (may not be the caller).
     * @param _inputTokenAddress The address of the token the liquidator will receive from the caller.
     * @param _maxInputTokenAmount The maximum amount of the input token the liquidator may transfer from the caller.
     * @param _outputTokenAddress The address of the token the caller will receive as a result of this call.
     * @param _exactOutputTokenAmount The exact amount of the token the caller will receive as a result of this call.
     * @param [unused].
     */
    function liquidate(
        address _initiator,
        address _inputTokenAddress,
        uint256 _maxInputTokenAmount,
        address _outputTokenAddress,
        uint256 _exactOutputTokenAmount,
        bytes calldata
    ) external {
        IERC20 inputToken = IERC20(_inputTokenAddress);

        // The next two calls may return `false` on failure. Instead of asserting `true`, we'll save gas in the
        // happy path at the expense of gas in the failure path, which will revert in the swap below.

        /*** Obtain collateral tokens from msg.sender ***/
        // NB: This will fail without sufficient allowance provided by msg.sender
        inputToken.transferFrom(msg.sender, address(this), _maxInputTokenAmount);

        /*** Approve the UniV2 router so it may retrieve the funds to trade ***/
        // NB: Allowance will likely remain after the swap, but this contract will not have any tokens.
        inputToken.approve(address(uniswapRouter), _maxInputTokenAmount);

        /*** Swap input tokens for output tokens, sending proceeds to msg.sender ***/
        // NB: A maximum of `_maxInputTokenAmount` input tokens will be used in this swap.
        // Any excess input tokens will be sent to the beneficiary.
        address[] memory path = new address[](2);
        path[0] = _inputTokenAddress;
        path[1] = _outputTokenAddress;
        uint256[] memory amounts = uniswapRouter.swapTokensForExactTokens(
            _exactOutputTokenAmount,
            _maxInputTokenAmount,
            path,
            msg.sender, // Send requisite number of tokens directly to the caller
            block.timestamp
        );
        // NB: If somehow swapTokensForExactTokens does not send required amount to msg.sender, it is up to the caller to revert.

        uint256 excessInputTokens = _maxInputTokenAmount - amounts[0];
        /*** Remaining input tokens paid out to the beneficiary to avoid keeping a balance here ***/
        if (excessInputTokens > 0) {
            address _target = beneficiary;
            if (_target == address(0)) {
                _target = _initiator;
            }
            require(inputToken.transfer(_target, excessInputTokens), "transfer to target failed");
        }

        emit Liquidation(
            _inputTokenAddress,
            _maxInputTokenAmount,
            _outputTokenAddress,
            _exactOutputTokenAmount,
            excessInputTokens
        );
    }

    /**
     * @notice Change the beneficiary to receive any remaining output tokens after paying back the liquidation initiator.
     * @param _newBeneficiary The new recipient of remaining output tokens.
     */
    function setBeneficiary(address _newBeneficiary) external onlyOwner {
        emit LiquidationBenficiaryUpdate(beneficiary, _newBeneficiary);

        beneficiary = _newBeneficiary;
    }

    /**
     * @notice Enable the contract owner to send erroneously received tokens to a specified recipient
     * @param _token The token to transfer
     * @param _recipient The recipient of the transferred tokens
     * @param _amount The amount of tokens to transfer
     */
    function retrieveTokens(IERC20 _token, address _recipient, uint256 _amount) external onlyOwner {
        _token.transfer(_recipient, _amount);
    }
}
