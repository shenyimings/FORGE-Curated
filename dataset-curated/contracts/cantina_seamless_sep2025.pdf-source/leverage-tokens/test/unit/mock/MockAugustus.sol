// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Test} from "forge-std/Test.sol";

/// @dev This implementation is copied from the original version implemented by Morpho
/// https://github.com/morpho-org/bundler3/blob/4887f33299ba6e60b54a51237b16e7392dceeb97/src/mocks/AugustusMock.sol
contract MockAugustus is Test {
    uint256 public toGive = type(uint256).max;
    uint256 public toTake = type(uint256).max;

    function setToGive(uint256 amount) external {
        toGive = amount;
    }

    function setToTake(uint256 amount) external {
        toTake = amount;
    }

    function mockBuy(address inputToken, address outputToken, uint256, uint256 outputAmount, address receiver)
        external
    {
        if (toGive != type(uint256).max) outputAmount = toGive;
        uint256 inputAmount = toTake != type(uint256).max ? toTake : outputAmount;

        IERC20(inputToken).transferFrom(msg.sender, address(this), inputAmount);
        deal(address(outputToken), address(this), outputAmount);
        IERC20(outputToken).transfer(receiver, outputAmount);

        toGive = type(uint256).max;
        toTake = type(uint256).max;
    }
}
