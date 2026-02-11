// SPDX-License-Identifier: MIT
pragma solidity >=0.8.18;

// Balancer v3 Router interface
interface IRouter {
	function addLiquidityProportional(
		address pool,
		uint256[] memory maxAmountsIn,
		uint256 exactBptAmountOut,
		bool wethIsEth,
		bytes memory userData
	) external payable returns (uint256[] memory amountsIn);
}
