// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

interface IShareManager {
    function mintFeesShares(address to, uint256 amount) external;
    function mintShares(address to, uint256 amount) external;
    function burnShares(address from, uint256 amount) external;
    function burnSharesFromSelf(uint256 amount) external;
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function isOperator(address controller, address operator) external view returns (bool);
    function isBlacklisted(address account) external view returns (bool);
    function maxDeposit() external view returns (uint256);
    function maxSupply() external view returns (uint256);
    function maxWithdraw() external view returns (uint256);
}
