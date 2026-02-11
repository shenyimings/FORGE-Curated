// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2025 Steakhouse Financial
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Box} from "./../Box.sol";
import {IBox} from "./../interfaces/IBox.sol";
import {IBoxFactory} from "./../interfaces/IBoxFactory.sol";

contract BoxFactory is IBoxFactory {
    /* STORAGE */
    mapping(address => bool) public isBox;

    /* FUNCTIONS */

    /// @dev Returns the address of the deployed Box
    function createBox(
        IERC20 _asset,
        address _owner,
        address _curator,
        string memory _name,
        string memory _symbol,
        uint256 _maxSlippage,
        uint256 _slippageEpochDuration,
        uint256 _shutdownSlippageDuration,
        uint256 _shutdownWarmup,
        bytes32 salt
    ) external returns (IBox) {
        IBox _box = new Box{salt: salt}(
            address(_asset),
            _owner,
            _curator,
            _name,
            _symbol,
            _maxSlippage,
            _slippageEpochDuration,
            _shutdownSlippageDuration,
            _shutdownWarmup
        );

        isBox[address(_box)] = true;

        emit BoxCreated(
            _box,
            _asset,
            _owner,
            _curator,
            _name,
            _symbol,
            _maxSlippage,
            _slippageEpochDuration,
            _shutdownSlippageDuration,
            _shutdownWarmup
        );

        return _box;
    }
}
