// Copyright (c) 2025 Merge Layers Inc.
//
// This source code is licensed under the Business Source License 1.1
// (the "License"); you may not use this file except in compliance with the
// License. You may obtain a copy of the License at
//
//     https://github.com/malda-protocol/malda-lending/blob/main/LICENSE-BSL
//
// See the License for the specific language governing permissions and
// limitations under the License.
//
// This file contains code derived from or inspired by Compound V2,
// originally licensed under the BSD 3-Clause License. See LICENSE-COMPOUND-V2
// for original license terms and attributions.

// SPDX-License-Identifier: BSL-1.1
pragma solidity =0.8.28;

/*
 _____ _____ __    ____  _____ 
|     |  _  |  |  |    \|  _  |
| | | |     |  |__|  |  |     |
|_|_|_|__|__|_____|____/|__|__|                           
*/

// contracts
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

// interfaces
import {IRoles} from "src/interfaces/IRoles.sol";
import {IPauser} from "src/interfaces/IPauser.sol";
import {IOperator} from "src/interfaces/IOperator.sol";
import {ImTokenOperationTypes} from "src/interfaces/ImToken.sol";
import {ImTokenGateway} from "src/interfaces/ImTokenGateway.sol";

contract Pauser is Ownable, IPauser {
    // ----------- STORAGE ------------
    IRoles public immutable roles;
    IOperator public immutable operator;

    PausableContract[] public pausableContracts;
    mapping(address _contract => bool _registered) public registeredContracts;
    mapping(address _contract => PausableType _type) public contractTypes;

    constructor(address _roles, address _operator, address _owner) Ownable(_owner) {
        require(_roles != address(0), Pauser_AddressNotValid());
        require(_operator != address(0), Pauser_AddressNotValid());
        roles = IRoles(_roles);
        operator = IOperator(_operator);
    }

    // ----------- OWNER ------------
    /**
     * @notice add pauable contract
     * @param _contract the pausable contract
     * @param _contractType the pausable contract type
     */
    function addPausableMarket(address _contract, PausableType _contractType) external onlyOwner {
        require(_contract != address(0), Pauser_AddressNotValid());
        if (registeredContracts[_contract]) return;
        registeredContracts[_contract] = true;
        pausableContracts.push(PausableContract(_contract, _contractType));
        contractTypes[_contract] = _contractType;
        emit MarketAdded(_contract, _contractType);
    }

    /**
     * @notice removes pauable contract
     * @param _contract the pausable contract
     */
    function removePausableMarket(address _contract) external onlyOwner {
        if (!registeredContracts[_contract]) revert Pauser_EntryNotFound();
        uint256 index = _findIndex(_contract);
        pausableContracts[index] = pausableContracts[pausableContracts.length - 1];
        pausableContracts.pop();
        registeredContracts[_contract] = false;
        contractTypes[_contract] = PausableType.NonPausable;
        emit MarketRemoved(_contract);
    }
    // ----------- PUBLIC ------------
    /**
     * @inheritdoc IPauser
     */

    function emergencyPauseMarket(address _market) external {
        _pauseAllMarketOperations(_market);
    }

    /**
     * @inheritdoc IPauser
     */
    function emergencyPauseMarketFor(address _market, ImTokenOperationTypes.OperationType _pauseType) external {
        _pauseMarketOperation(_market, _pauseType);
    }

    /**
     * @inheritdoc IPauser
     */
    function emergencyPauseAll() external {
        uint256 len = pausableContracts.length;
        for (uint256 i; i < len;) {
            _pauseAllMarketOperations(pausableContracts[i].market);

            unchecked {
                ++i;
            }
        }
        emit PauseAll();
    }

    // ----------- PRIVATE ------------
    function _pauseAllMarketOperations(address _market) private {
        _pauseMarketOperation(_market, OperationType.AmountIn);
        _pauseMarketOperation(_market, OperationType.AmountOut);
        _pauseMarketOperation(_market, OperationType.AmountInHere);
        _pauseMarketOperation(_market, OperationType.AmountOutHere);
        _pauseMarketOperation(_market, OperationType.Mint);
        _pauseMarketOperation(_market, OperationType.Borrow);
        _pauseMarketOperation(_market, OperationType.Transfer);
        _pauseMarketOperation(_market, OperationType.Seize);
        _pauseMarketOperation(_market, OperationType.Repay);
        _pauseMarketOperation(_market, OperationType.Redeem);
        _pauseMarketOperation(_market, OperationType.Liquidate);
        _pauseMarketOperation(_market, OperationType.Rebalancing);
        emit MarketPaused(_market);
    }

    function _pauseMarketOperation(address _market, ImTokenOperationTypes.OperationType _pauseType) private {
        _pause(_market, _pauseType);
        emit MarketPausedFor(_market, _pauseType);
    }

    function _pause(address _market, ImTokenOperationTypes.OperationType _pauseType) private {
        require(roles.isAllowedFor(msg.sender, roles.PAUSE_MANAGER()), Pauser_NotAuthorized());
        PausableType _type = contractTypes[_market];
        if (_type == PausableType.Host) {
            operator.setPaused(_market, _pauseType, true);
        } else if (_type == PausableType.Extension) {
            ImTokenGateway(_market).setPaused(_pauseType, true);
        } else {
            revert Pauser_ContractNotEnabled();
        }
    }

    function _findIndex(address _address) private view returns (uint256) {
        uint256 len = pausableContracts.length;
        for (uint256 i; i < len;) {
            if (pausableContracts[i].market == _address) {
                return i;
            }

            unchecked {
                ++i;
            }
        }
        revert Pauser_EntryNotFound();
    }
}
