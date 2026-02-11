// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IWETH.sol";

/// @dev Simple executor that only supports wrapping and unwrapping ETH
contract OdosWETHExecutor {
	IWETH public immutable WETH;

	constructor(address _weth) {
	    WETH = IWETH(_weth);
	}
	receive() external payable { }

	function executePath (
	    bytes calldata bytecode,
	    uint256[] memory inputAmounts,
	    address msgSender
	) 
		external payable
	{
	  if (uint8(bytecode[0]) == 1) {
        WETH.deposit{value: inputAmounts[0]}();
        WETH.transfer(msg.sender, inputAmounts[0]);
      }
      else {
        WETH.withdraw(inputAmounts[0]);
        payable(msg.sender).transfer(inputAmounts[0]);
      }
	}
}