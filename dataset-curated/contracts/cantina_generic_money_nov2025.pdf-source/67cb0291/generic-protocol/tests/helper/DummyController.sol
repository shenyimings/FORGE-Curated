// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { IController } from "../../src/interfaces/IController.sol";

/**
 * @title Fixed Rate Controller
 * @dev A simple controller implementation that maintains a constant 1:1 exchange ratio
 * @notice This controller always returns a fixed ratio of 1:1 regardless of market conditions
 * or input parameters, providing predictable and stable rate calculations for testing purposes
 */
contract DummyController is IController {
    function vaultFor(address) external pure returns (address) {
        return address(0);
    }

    function share() external pure returns (address) {
        return address(0);
    }

    function deposit(uint256 assets, address) external pure returns (uint256 shares) {
        return assets;
    }

    function mint(uint256 shares, address) external pure returns (uint256 assets) {
        return shares;
    }

    function withdraw(uint256 assets, address, address) external pure returns (uint256 shares) {
        return assets;
    }

    function redeem(uint256 shares, address, address) external pure returns (uint256 assets) {
        return shares;
    }

    function previewDeposit(uint256 assets) external pure returns (uint256 shares) {
        return assets;
    }

    function previewMint(uint256 shares) external pure returns (uint256 assets) {
        return shares;
    }

    function previewWithdraw(uint256 assets) external pure returns (uint256 shares) {
        return assets;
    }

    function previewRedeem(uint256 shares) external pure returns (uint256 assets) {
        return shares;
    }

    function maxDeposit(address) external pure returns (uint256) {
        return type(uint256).max;
    }

    function maxMint(address) external pure returns (uint256) {
        return type(uint256).max;
    }

    function maxWithdraw(address, uint256 availableAssets) external pure returns (uint256) {
        return availableAssets;
    }

    function maxRedeem(address, uint256 availableAssets) external pure returns (uint256) {
        return availableAssets;
    }
}
