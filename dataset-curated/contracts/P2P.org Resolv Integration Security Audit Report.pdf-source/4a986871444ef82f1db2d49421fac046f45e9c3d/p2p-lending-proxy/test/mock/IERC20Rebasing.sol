// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;
import "../../src/@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

interface IERC20Rebasing is IERC20, IERC20Metadata {
    event TransferShares(address indexed _from, address indexed _to, uint256 _shares);

    error InvalidUnderlyingTokenDecimals();
    error InvalidUnderlyingTokenAddress();

    function underlyingToken() external view returns (IERC20Metadata token);

    function transferShares(address _to, uint256 _shares) external returns (bool isSuccess);

    function transferSharesFrom(address _from, address _to, uint256 _shares) external returns (bool isSuccess);

    function totalShares() external view returns (uint256 shares);

    function sharesOf(address _account) external view returns (uint256 shares);

    function convertToShares(uint256 _underlyingTokenAmount) external view returns (uint256 shares);

    function convertToUnderlyingToken(uint256 _shares) external view returns (uint256 underlyingTokenAmount);
}