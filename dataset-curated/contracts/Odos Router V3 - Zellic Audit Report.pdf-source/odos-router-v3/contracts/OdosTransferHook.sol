// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @dev Simple hook that just transfers the assets back to the original msg.sender of the swap
contract OdosTransferHook {

	using SafeERC20 for IERC20;
	
	/// @dev The zero address is uniquely used to represent eth since it is already
  /// recognized as an invalid ERC20, and due to its gas efficiency
  address constant _ETH = address(0);

	receive() external payable { }

	function executeOdosHook (
	    bytes calldata hookData,
	    uint256[] memory inputAmounts,
	    address msgSender
	) 
		external
	{
		(address[] memory tokens, address to) = abi.decode(hookData, (address[], address));

		if (to == address(0)) {
			to = msgSender;
		}
		for (uint256 i; i < inputAmounts.length; i++) {
			if (tokens[i] == _ETH) {
		    (bool success,) = payable(to).call{value: inputAmounts[i]}("");
		    require(success, "ETH transfer failed");
		  } else {
		    IERC20(tokens[i]).safeTransfer(to, inputAmounts[i]);
		  }
		}
	}
}