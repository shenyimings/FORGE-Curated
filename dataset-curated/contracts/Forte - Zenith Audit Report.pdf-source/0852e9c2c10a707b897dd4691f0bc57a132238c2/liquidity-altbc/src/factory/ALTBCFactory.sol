// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "lib/liquidity-base/src/common/IErrors.sol";
import {ALTBCPool, FeeInfo, IERC20} from "src/amm/ALTBCPool.sol";
import {ALTBCFactoryDeployed} from "src/common/IALTBCEvents.sol";
import {ALTBCInput} from "src/amm/ALTBC.sol";
import {FactoryBase} from "lib/liquidity-base/src/factory/FactoryBase.sol";
import "lib/liquidity-base/src/common/IEvents.sol";

/**
 * @title Pool Factory
 * @dev creates the pools in an automated and permissioned fashion
 * @author  @oscarsernarosero @mpetersoCode55 @cirsteve
 */

contract ALTBCFactory is FactoryBase {
    bytes altbcBytecode;

    /**
     * @dev constructor receives and saves the ALTBCPool byte code to bypass contract side limit
     * @param _altbcBytecode the bytecode of the ALTBC
     */
    constructor(bytes memory _altbcBytecode) {
        altbcBytecode = _altbcBytecode;
        emit ALTBCFactoryDeployed(VERSION);
    }

    /**
     * @dev deploys an ALTBC pool
     * @param _xToken address of the X token (x axis)
     * @param _yToken address of the Y token (y axis)
     * @param _lpFee percentage of the fees in percentage basis points
     * @param _tbcInput input data for the pool
     * @param _xAdd the initial liquidity of xTokens that will be transferred to the pool
     *
     * @return deployedPool the address of the deployed pool
     * @notice Only allowed deployers can deploy pools and only allowed yTokens are allowed
     */
    function createPool(
        address _xToken,
        address _yToken,
        uint16 _lpFee,
        ALTBCInput memory _tbcInput,
        uint256 _xAdd,
        string memory _name,
        string memory _symbol
    ) external onlyAllowedDeployers onlyAllowedYTokens(_yToken) returns (address deployedPool) {
        if (protocolFeeCollector == address(0)) revert NoProtocolFeeCollector();

        bytes memory _constructor = abi.encode(
            _xToken,
            _yToken,
            FeeInfo(_lpFee, protocolFee, protocolFeeCollector),
            _tbcInput,
            _name,
            _symbol
        );
        bytes memory deployBytecode = abi.encodePacked(altbcBytecode, _constructor);

        assembly {
            deployedPool := create(0, add(deployBytecode, 0x20), mload(deployBytecode))
            if iszero(deployedPool) {
                returndatacopy(0, 0, returndatasize())
                revert(0, returndatasize())
            }
        }
        emit PoolCreated(deployedPool);

        IERC20(_xToken).transferFrom(_msgSender(), address(deployedPool), _xAdd);
        ALTBCPool(deployedPool).initializePool(_msgSender());
        emit IPoolEvents.LiquidityXTokenAdded(_xToken, _xAdd);
    }
}
