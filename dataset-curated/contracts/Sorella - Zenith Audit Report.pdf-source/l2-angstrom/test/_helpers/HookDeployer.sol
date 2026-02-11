// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {Hooks, IHooks} from "v4-core/src/libraries/Hooks.sol";

/// @author philogy <https://github.com/philogy>
abstract contract HookDeployer is Test {
    using Hooks for IHooks;

    function _newFactory() internal returns (address) {
        return address(new Create2Factory());
    }

    struct Create2Params {
        uint256 packedFactoryLeadByte;
        uint256 salt;
        bytes32 initcodeHash;
    }

    function mineAngstromL2Salt(
        bytes memory initcode,
        address factory,
        Hooks.Permissions memory requiredPermissions
    ) internal view returns (address addr, bytes32 salt) {
        Create2Params memory params = Create2Params(
            (uint256(0xff) << 160) | uint256(uint160(factory)), 0, keccak256(initcode)
        );

        while (true) {
            assembly ("memory-safe") {
                addr :=
                    and(keccak256(add(params, 11), 85), 0xffffffffffffffffffffffffffffffffffffffff)
            }

            if (validateHookPermissions(addr, requiredPermissions)) {
                return (addr, bytes32(params.salt));
            }

            unchecked {
                params.salt++;
            }
        }
    }

    function deployHook(
        bytes memory initcode,
        address factory,
        Hooks.Permissions memory requiredPermissions
    ) internal returns (bool success, address addr, bytes memory retdata) {
        bytes32 salt;
        (addr, salt) = mineAngstromL2Salt(initcode, factory, requiredPermissions);

        (success, retdata) = factory.call(abi.encodePacked(salt, initcode));
        if (success) {
            assertEq(
                retdata,
                abi.encodePacked(addr),
                "Sanity check: factory returned data is not mined address"
            );
        } else {
            assembly ("memory-safe") {
                revert(add(retdata, 0x20), mload(retdata))
            }
        }
    }

    function validateHookPermissions(address addr, Hooks.Permissions memory requiredPermissions)
        internal
        view
        returns (bool)
    {
        try this.__validateHookPermissions(addr, requiredPermissions) {
            return true;
        } catch (bytes memory data) {
            if (bytes4(data) != Hooks.HookAddressNotValid.selector) {
                assembly ("memory-safe") {
                    revert(add(data, 0x20), mload(data))
                }
            }
            return false;
        }
    }

    function __validateHookPermissions(address addr, Hooks.Permissions memory perms)
        external
        pure
    {
        IHooks(addr).validateHookPermissions(perms);
        if (!IHooks(addr).isValidHookAddress(0)) revert Hooks.HookAddressNotValid(addr);
    }
}

contract Create2Factory {
    fallback() external payable {
        _create();
    }

    function _create() internal {
        assembly {
            if iszero(gt(calldatasize(), 31)) { revert(0, 0) }
            let salt := calldataload(0x00)
            let size := sub(calldatasize(), 0x20)
            calldatacopy(0x00, 0x20, size)
            let result := create2(callvalue(), 0x00, size, salt)
            if iszero(result) {
                returndatacopy(0, 0, returndatasize())
                revert(0, returndatasize())
            }
            mstore(0, result)
            return(12, 20)
        }
    }
}
