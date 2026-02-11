// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IHandler} from "../../src/interfaces/IHandler.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockHandler is IHandler {
    address public token0;
    address public token1;
    address public positionManager;
    address public feeReceiver;
    mapping(address => uint256) public balances;

    constructor(address _token0, address _token1, address _positionManager, address _feeReceiver) {
        token0 = _token0;
        token1 = _token1;
        positionManager = _positionManager;
        feeReceiver = _feeReceiver;
    }

    function getHandlerIdentifier(bytes calldata data) external pure returns (uint256) {
        return uint256(keccak256(data));
    }

    function registerHook(address _hook, IHandler.HookPermInfo memory _info) external {
        // Do nothing
    }

    function tokensToPullForMint(bytes calldata data)
        external
        view
        returns (address[] memory tokens, uint256[] memory amounts)
    {
        (uint256 amount0, uint256 amount1) = abi.decode(data, (uint256, uint256));
        tokens = new address[](2);
        amounts = new uint256[](2);
        tokens[0] = token0;
        tokens[1] = token1;
        amounts[0] = amount0;
        amounts[1] = amount1;
    }

    function mintPositionHandler(address user, bytes calldata data) external returns (uint256) {
        (uint256 amount0, uint256 amount1) = abi.decode(data, (uint256, uint256));
        require(IERC20(token0).transferFrom(positionManager, address(this), amount0), "Transfer of token0 failed");
        require(IERC20(token1).transferFrom(positionManager, address(this), amount1), "Transfer of token1 failed");
        balances[token0] += amount0;
        balances[token1] += amount1;
        return uint256(keccak256(abi.encodePacked(user, data)));
    }

    function burnPositionHandler(address user, bytes calldata data) external returns (uint256) {
        (uint256 amount0, uint256 amount1) = abi.decode(data, (uint256, uint256));
        require(balances[token0] >= amount0, "Insufficient token0 balance");
        require(balances[token1] >= amount1, "Insufficient token1 balance");
        balances[token0] -= amount0;
        balances[token1] -= amount1;
        require(IERC20(token0).transfer(user, amount0), "Transfer of token0 failed");
        require(IERC20(token1).transfer(user, amount1), "Transfer of token1 failed");
        return uint256(keccak256(abi.encodePacked(user, data)));
    }

    function usePositionHandler(bytes calldata data)
        external
        returns (address[] memory tokens, uint256[] memory amounts, uint256 liquidityUsed)
    {
        uint256 amount = abi.decode(data, (uint256));
        require(balances[token0] >= amount, "Insufficient token0 balance");
        require(balances[token1] >= amount, "Insufficient token1 balance");
        balances[token0] -= amount;
        balances[token1] -= amount;
        require(IERC20(token0).transfer(positionManager, amount), "Transfer of token0 failed");
        require(IERC20(token1).transfer(positionManager, amount), "Transfer of token1 failed");
        tokens = new address[](2);
        amounts = new uint256[](2);
        tokens[0] = token0;
        tokens[1] = token1;
        amounts[0] = amount;
        amounts[1] = amount;
        liquidityUsed = amount * 2;
    }

    function tokensToPullForUnUse(bytes calldata data)
        external
        view
        returns (address[] memory tokens, uint256[] memory amounts)
    {
        uint256 amount = abi.decode(data, (uint256));
        tokens = new address[](2);
        amounts = new uint256[](2);
        tokens[0] = token0;
        tokens[1] = token1;
        amounts[0] = amount;
        amounts[1] = amount;
    }

    function unusePositionHandler(bytes calldata data) external returns (uint256[] memory amounts, uint256 liquidity) {
        uint256 amount = abi.decode(data, (uint256));
        require(IERC20(token0).transferFrom(positionManager, address(this), amount), "Transfer of token0 failed");
        require(IERC20(token1).transferFrom(positionManager, address(this), amount), "Transfer of token1 failed");
        balances[token0] += amount;
        balances[token1] += amount;
        amounts = new uint256[](2);
        amounts[0] = amount;
        amounts[1] = amount;
        liquidity = amount * 2;
    }

    function tokensToPullForDonate(bytes calldata data)
        external
        view
        returns (address[] memory tokens, uint256[] memory amounts)
    {
        (uint256 amount0, uint256 amount1) = abi.decode(data, (uint256, uint256));
        tokens = new address[](2);
        amounts = new uint256[](2);
        tokens[0] = token0;
        tokens[1] = token1;
        amounts[0] = amount0;
        amounts[1] = amount1;
    }

    function donateToPosition(bytes calldata data) external returns (uint256[] memory amounts, uint256 liquidity) {
        (uint256 amount0, uint256 amount1) = abi.decode(data, (uint256, uint256));
        require(
            IERC20(token0).transferFrom(positionManager, feeReceiver, amount0),
            "Transfer of token0 to feeReceiver failed"
        );
        require(
            IERC20(token1).transferFrom(positionManager, feeReceiver, amount1),
            "Transfer of token1 to feeReceiver failed"
        );
        amounts = new uint256[](2);
        amounts[0] = amount0;
        amounts[1] = amount1;
        liquidity = amount0 + amount1;
    }

    function tokensToPullForWildcard(bytes calldata)
        external
        view
        returns (address[] memory tokens, uint256[] memory amounts)
    {
        tokens = new address[](0);
        amounts = new uint256[](0);
    }

    function wildcardHandler(address, bytes calldata data) external pure returns (bytes memory) {
        return data;
    }
}
