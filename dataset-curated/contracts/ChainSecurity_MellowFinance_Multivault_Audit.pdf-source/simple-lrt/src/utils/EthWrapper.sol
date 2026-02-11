// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "../interfaces/utils/IEthWrapper.sol";

contract EthWrapper is IEthWrapper {
    using SafeERC20 for IERC20;

    /// @inheritdoc IEthWrapper
    address public immutable WETH;
    /// @inheritdoc IEthWrapper
    address public immutable wstETH;
    /// @inheritdoc IEthWrapper
    address public immutable stETH;
    /// @inheritdoc IEthWrapper
    address public constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    constructor(address WETH_, address wstETH_, address stETH_) {
        WETH = WETH_;
        wstETH = wstETH_;
        stETH = stETH_;
    }

    /**
     * @notice Wraps the specified `depositToken` into `wstETH` if applicable.
     * @param depositToken The address of the token being deposited, which must be one of: ETH, WETH, stETH, or wstETH.
     * @param amount The amount of `depositToken` to be wrapped.
     * @return The resulting amount of `wstETH` after the wrapping process.
     *
     * @custom:requirements
     * - `depositToken` MUST be one of the following: ETH, WETH, stETH, or wstETH.
     * - `amount` MUST be greater than 0.
     *
     * @dev The function handles the wrapping of different types of tokens into `wstETH`. If the token is ETH, it is first converted
     *      to stETH and then wrapped into `wstETH`. If the token is WETH, it is unwrapped to ETH first, and if the token is stETH,
     *      it is directly wrapped into `wstETH`.
     *
     * @dev `msg.value` is expected only when the deposit token is ETH. The function enforces that no ETH is sent for other deposit tokens.
     */
    function _wrap(address depositToken, uint256 amount) internal returns (uint256) {
        require(amount > 0, "EthWrapper: amount must be greater than 0");
        require(
            depositToken == ETH || depositToken == WETH || depositToken == stETH
                || depositToken == wstETH,
            "EthWrapper: invalid depositToken"
        );

        // If the deposit token is not ETH, ensure no ETH is sent and transfer the deposit tokens from the sender
        if (depositToken != ETH) {
            require(msg.value == 0, "EthWrapper: cannot send ETH with depositToken");
            IERC20(depositToken).safeTransferFrom(msg.sender, address(this), amount);
        } else {
            // If the deposit token is ETH, ensure the correct ETH amount is sent
            require(msg.value == amount, "EthWrapper: incorrect amount of ETH");
        }

        // Unwrap WETH to ETH if the deposit token is WETH
        if (depositToken == WETH) {
            IWETH(WETH).withdraw(amount);
            depositToken = ETH;
        }

        // Convert ETH to stETH and wrap it to wstETH
        if (depositToken == ETH) {
            (bool success,) = payable(wstETH).call{value: amount}("");
            require(success, "EthWrapper: ETH transfer failed");
            amount = IERC20(wstETH).balanceOf(address(this));
        }

        // Wrap stETH to wstETH
        if (depositToken == stETH) {
            IERC20(stETH).safeIncreaseAllowance(wstETH, amount);
            amount = IWSTETH(wstETH).wrap(amount);
        }

        return amount;
    }

    receive() external payable {
        require(msg.sender == WETH, "EthWrapper: invalid sender");
    }

    /// @inheritdoc IEthWrapper
    function deposit(
        address depositToken,
        uint256 amount,
        address vault,
        address receiver,
        address referral
    ) public payable virtual returns (uint256 shares) {
        amount = _wrap(depositToken, amount);
        IERC20(wstETH).safeIncreaseAllowance(vault, amount);
        return IERC4626Vault(vault).deposit(amount, receiver, referral);
    }
}
