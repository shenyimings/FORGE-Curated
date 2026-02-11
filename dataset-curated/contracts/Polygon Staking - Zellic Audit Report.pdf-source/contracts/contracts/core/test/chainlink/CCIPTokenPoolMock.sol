// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";

/**
 * @title CCIP Token Pool Mock
 * @notice Mocks CCIP token pool contract for testing
 */
contract CCIPTokenPoolMock {
    using SafeERC20 for IERC20;

    IERC20 public token;

    constructor(address _token) {
        token = IERC20(_token);
    }

    function lockOrBurn() external {}

    function releaseOrMint(address _receiver, uint256 _amount) external {
        token.safeTransfer(_receiver, _amount);
    }
}
