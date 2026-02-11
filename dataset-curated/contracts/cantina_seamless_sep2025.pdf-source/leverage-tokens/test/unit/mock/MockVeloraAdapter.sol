// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Forge imports
import {Test} from "forge-std/Test.sol";

// Dependency imports
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IVeloraAdapter} from "src/interfaces/periphery/IVeloraAdapter.sol";

contract MockVeloraAdapter is Test {
    mapping(address inputToken => uint256 mockedInputAmount) public mockedBuy;

    function mockNextBuy(address inputToken, uint256 mockedInputAmount) public {
        mockedBuy[inputToken] = mockedInputAmount;
    }

    function buy(
        address, /* augustus */
        bytes memory, /* callData */
        address inputToken,
        address outputToken,
        uint256 newOutputAmount,
        IVeloraAdapter.Offsets calldata, /* offsets */
        address receiver
    ) public returns (uint256) {
        uint256 requiredInputAmount = mockedBuy[inputToken];
        uint256 balance = IERC20(inputToken).balanceOf(address(this));

        if (balance < requiredInputAmount) {
            revert("MockVeloraAdapter: Insufficient balance for buy");
        }

        deal(outputToken, address(this), newOutputAmount);
        IERC20(outputToken).transfer(receiver, newOutputAmount);

        uint256 excessInputAmount = balance - requiredInputAmount;
        IERC20(inputToken).transfer(msg.sender, excessInputAmount);

        return excessInputAmount;
    }
}
