// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2025.
pragma solidity ^0.8.23;

import {IStateSerializer} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IStateSerializer.sol";
import {IVersion} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IVersion.sol";
import {IStateSerializerLegacy} from "../interfaces/IStateSerializerLegacy.sol";
import {BaseParams, BaseState} from "../types/BaseState.sol";

library BaseLib {
    function getBaseParams(address addr, bytes32 defaultContractType, address legacySerializer)
        internal
        view
        returns (BaseParams memory baseParams)
    {
        baseParams.addr = addr;

        try IVersion(addr).version() returns (uint256 version) {
            baseParams.version = version;
        } catch {}

        try IVersion(addr).contractType() returns (bytes32 contractType) {
            baseParams.contractType = contractType;
        } catch {
            baseParams.contractType = defaultContractType;
        }

        try IStateSerializer(addr).serialize() returns (bytes memory serializedParams) {
            baseParams.serializedParams = serializedParams;
        } catch {
            if (legacySerializer != address(0)) {
                try IStateSerializerLegacy(legacySerializer).serialize(addr) returns (bytes memory serializedParams) {
                    baseParams.serializedParams = serializedParams;
                } catch {}
            }
        }
    }

    function getBaseState(address addr, bytes32 defaultContractType, address legacySerializer)
        internal
        view
        returns (BaseState memory baseState)
    {
        baseState.baseParams = getBaseParams(addr, defaultContractType, legacySerializer);
    }
}
