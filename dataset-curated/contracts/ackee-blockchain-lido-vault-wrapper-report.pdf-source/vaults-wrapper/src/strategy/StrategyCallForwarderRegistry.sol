// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {IStrategyCallForwarder} from "src/interfaces/IStrategyCallForwarder.sol";

abstract contract StrategyCallForwarderRegistry {
    error CallForwarderZeroArgument(string name);

    /// @dev WARNING: STRATEGY_ID and STRATEGY_CALL_FORWARDER_IMPL are used to calculate user proxy addresses
    /// Changing either value will break user proxy address calculations.
    bytes32 public immutable STRATEGY_ID;
    address public immutable STRATEGY_CALL_FORWARDER_IMPL;

    /// @custom:storage-location erc7201:pool.storage.StrategyCallForwarderRegistry
    struct CallForwarderStorage {
        mapping(bytes32 salt => IStrategyCallForwarder callForwarder) userCallForwarder;
    }

    // keccak256(abi.encode(uint256(keccak256("pool.storage.StrategyCallForwarderRegistry")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant CALL_FORWARDER_STORAGE_LOCATION =
        0x3074294e9a887c21033ca796133e603629c1fad03ac5b84cce0cfe20ad599d00;

    function _getCallForwarderRegistryStorage() internal pure returns (CallForwarderStorage storage $) {
        assembly {
            $.slot := CALL_FORWARDER_STORAGE_LOCATION
        }
    }

    constructor(bytes32 _strategyId, address _strategyCallForwarderImpl) {
        if (_strategyId == bytes32(0)) revert CallForwarderZeroArgument("_strategyId");
        if (_strategyCallForwarderImpl == address(0)) revert CallForwarderZeroArgument("_strategyCallForwarderImpl");

        STRATEGY_ID = _strategyId;
        STRATEGY_CALL_FORWARDER_IMPL = _strategyCallForwarderImpl;
    }

    /**
     * @notice Returns the address of the strategy call forwarder for a given user
     * @param _user The user for which to get the strategy call forwarder address
     * @return callForwarder The address of the strategy call forwarder
     */
    function getStrategyCallForwarderAddress(address _user) public view returns (IStrategyCallForwarder callForwarder) {
        bytes32 salt = _generateSalt(_user);
        callForwarder = IStrategyCallForwarder(Clones.predictDeterministicAddress(STRATEGY_CALL_FORWARDER_IMPL, salt));
    }

    function _getOrCreateCallForwarder(address _user) internal returns (IStrategyCallForwarder callForwarder) {
        if (_user == address(0)) revert CallForwarderZeroArgument("_user");

        CallForwarderStorage storage $ = _getCallForwarderRegistryStorage();

        bytes32 salt = _generateSalt(_user);
        callForwarder = $.userCallForwarder[salt];
        if (address(callForwarder) != address(0)) return callForwarder;

        callForwarder = IStrategyCallForwarder(Clones.cloneDeterministic(STRATEGY_CALL_FORWARDER_IMPL, salt));
        callForwarder.initialize(address(this));

        $.userCallForwarder[salt] = callForwarder;
    }

    function _generateSalt(address _user) internal view returns (bytes32 salt) {
        salt = keccak256(abi.encode(block.chainid, STRATEGY_ID, address(this), _user));
    }
}
