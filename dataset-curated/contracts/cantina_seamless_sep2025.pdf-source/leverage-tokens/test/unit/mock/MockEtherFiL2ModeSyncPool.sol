// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {MockERC20} from "./MockERC20.sol";

contract MockEtherFiL2ModeSyncPool {
    /// @notice The ETH address per the EtherFi L2 Mode Sync Pool contract
    address public constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    MockERC20 public weETH;

    uint256 mockAmountOut;

    constructor(MockERC20 _weETH) {
        weETH = _weETH;
    }

    function mockSetAmountOut(uint256 _amountOut) external {
        mockAmountOut = _amountOut;
    }

    function deposit(address tokenIn, uint256 amountIn, uint256 minAmountOut, address /*referral*/ )
        external
        payable
        returns (uint256 amountOut)
    {
        if (tokenIn != ETH_ADDRESS) {
            revert("Invalid token");
        }
        if (msg.value != amountIn) {
            revert("Invalid ETH amount");
        }
        if (mockAmountOut < minAmountOut) {
            revert("Amount out is less than min amount out");
        }

        weETH.mint(msg.sender, mockAmountOut);
        return mockAmountOut;
    }
}
