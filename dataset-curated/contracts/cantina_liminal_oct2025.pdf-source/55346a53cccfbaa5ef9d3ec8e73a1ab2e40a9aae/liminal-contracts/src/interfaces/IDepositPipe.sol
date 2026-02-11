// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

interface IDepositPipe {
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);
    function deposit(uint256 assets, address receiver, address controller) external returns (uint256 shares);
    function deposit(uint256 assets, address receiver, uint256 minShares) external returns (uint256 shares);
    function deposit(uint256 assets, address receiver, address controller, uint256 minShares)
        external
        returns (uint256 shares);
    function mint(uint256 shares, address receiver) external returns (uint256 assets);
    function mint(uint256 shares, address receiver, uint256 maxAssets) external returns (uint256 assets);
    function asset() external view returns (address);
}
