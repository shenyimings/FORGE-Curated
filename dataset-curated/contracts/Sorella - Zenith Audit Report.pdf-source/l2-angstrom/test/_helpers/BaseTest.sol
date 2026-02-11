// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {Test} from "forge-std/Test.sol";
import {HookDeployer} from "./HookDeployer.sol";
import {stdError} from "forge-std/StdError.sol";
import {HookDeployer} from "./HookDeployer.sol";
import {Hooks, IHooks} from "v4-core/src/libraries/Hooks.sol";
import {POOLS_MUST_HAVE_DYNAMIC_FEE} from "src/hook-config.sol";
import {LPFeeLibrary} from "v4-core/src/libraries/LPFeeLibrary.sol";
import {IFlashBlockNumber} from "src/interfaces/IFlashBlockNumber.sol";

import {MockERC20} from "super-sol/mocks/MockERC20.sol";

import {FormatLib} from "super-sol/libraries/FormatLib.sol";

/// @author philogy <https://github.com/philogy>
contract BaseTest is Test, HookDeployer {
    using FormatLib for *;

    struct Random {
        bytes32 state;
    }

    bool constant DEBUG = false;

    uint256 internal constant REAL_TIMESTAMP = 1721652639;

    bytes32 internal constant ANG_CONTROLLER_SLOT = bytes32(uint256(0x0));
    bytes32 internal constant ANG_CONFIG_STORE_SLOT = bytes32(uint256(0x3));
    bytes32 internal constant ANG_BALANCES_SLOT = bytes32(uint256(0x5));

    function pm(address addr) internal pure returns (IPoolManager) {
        return IPoolManager(addr);
    }

    function mineAngstromL2Salt(
        address factory,
        bytes memory initcode,
        IPoolManager uniV4,
        IFlashBlockNumber flashBlockNumberProvider,
        address owner,
        Hooks.Permissions memory requiredPermissions
    ) internal view returns (bytes32 salt) {
        (, salt) = mineAngstromL2Salt(
            bytes.concat(initcode, abi.encode(uniV4, flashBlockNumberProvider, owner)),
            factory,
            requiredPermissions
        );
    }

    function poolKey(address hook, address token, int24 tickSpacing)
        internal
        pure
        returns (PoolKey memory pk)
    {
        pk.hooks = IHooks(hook);
        pk.currency0 = Currency.wrap(address(0));
        pk.currency1 = Currency.wrap(token);
        pk.tickSpacing = tickSpacing;
        pk.fee = address(hook) != address(0) && POOLS_MUST_HAVE_DYNAMIC_FEE
            ? LPFeeLibrary.DYNAMIC_FEE_FLAG
            : 0;
    }

    function computeDomainSeparator(address angstrom) internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256(
                    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                ),
                keccak256("Angstrom"),
                keccak256("v1"),
                block.chainid,
                address(angstrom)
            )
        );
    }

    function randomI24(Random memory r) internal pure returns (int24) {
        r.state = keccak256(abi.encode(r.state));
        return int24(int256(uint256(r.state)));
    }

    function pythonRunCmd() internal pure returns (string[] memory args) {
        args = new string[](1);
        args[0] = ".venv/bin/python3";
    }

    function ffiPython(string[] memory args) internal returns (bytes memory) {
        string[] memory runArgs = pythonRunCmd();
        string[] memory all = new string[](runArgs.length + args.length);
        for (uint256 i = 0; i < runArgs.length; i++) {
            all[i] = runArgs[i];
        }

        for (uint256 i = 0; i < args.length; i++) {
            all[runArgs.length + i] = args[i];
        }

        return vm.ffi(all);
    }

    function i24(uint256 x) internal pure returns (int24 y) {
        assertLe(x, uint24(type(int24).max), "Unsafe cast to int24");
        y = int24(int256(x));
    }

    function u128(uint256 x) internal pure returns (uint128 y) {
        assertLe(x, type(uint128).max, "Unsafe cast to uint128");
        y = uint128(x);
    }

    function u16(uint256 x) internal pure returns (uint16 y) {
        assertLe(x, type(uint16).max, "Unsafe cast to uint16");
        y = uint16(x);
    }

    function u64(uint256 x) internal pure returns (uint64 y) {
        assertLe(x, type(uint64).max, "Unsafe cast to uint64");
        y = uint64(x);
    }

    function u40(uint256 x) internal pure returns (uint40 y) {
        assertLe(x, type(uint40).max, "Unsafe cast to uint40");
        y = uint40(x);
    }

    function tryAdd(uint256 x, uint256 y) internal view returns (bool, bytes memory, uint256) {
        return tryFn(this.__safeAdd, x, y);
    }

    function trySub(uint256 x, uint256 y) internal view returns (bool, bytes memory, uint256) {
        return tryFn(this.__safeSub, x, y);
    }

    function tryMul(uint256 x, uint256 y) internal view returns (bool, bytes memory, uint256) {
        return tryFn(this.__safeMul, x, y);
    }

    function tryDiv(uint256 x, uint256 y) internal view returns (bool, bytes memory, uint256) {
        return tryFn(this.__safeDiv, x, y);
    }

    function tryMod(uint256 x, uint256 y) internal view returns (bool, bytes memory, uint256) {
        return tryFn(this.__safeMod, x, y);
    }

    function tryFn(function(uint, uint) external pure returns (uint) op, uint256 x, uint256 y)
        internal
        pure
        returns (bool hasErr, bytes memory err, uint256 z)
    {
        try op(x, y) returns (uint256 result) {
            hasErr = false;
            z = result;
        } catch (bytes memory errorData) {
            err = errorData;
            assertEq(err, stdError.arithmeticError);
            hasErr = true;
            z = 0;
        }
    }

    function __safeAdd(uint256 x, uint256 y) external pure returns (uint256) {
        return x + y;
    }

    function __safeSub(uint256 x, uint256 y) external pure returns (uint256) {
        return x - y;
    }

    function __safeMul(uint256 x, uint256 y) external pure returns (uint256) {
        return x * y;
    }

    function __safeDiv(uint256 x, uint256 y) external pure returns (uint256) {
        return x / y;
    }

    function __safeMod(uint256 x, uint256 y) external pure returns (uint256) {
        return x / y;
    }

    function freePtr() internal pure returns (uint256 ptr) {
        assembly ("memory-safe") {
            ptr := mload(0x40)
        }
    }

    function _brutalize(uint256 seed, uint256 freeWordsToBrutalize)
        internal
        pure
        returns (uint256 newBrutalizeSeed)
    {
        assembly ("memory-safe") {
            mstore(0x00, seed)
            let free := mload(0x40)
            for { let i := 0 } lt(i, freeWordsToBrutalize) { i := add(i, 1) } {
                let newGarbage := keccak256(0x00, 0x20)
                mstore(add(free, mul(i, 0x20)), newGarbage)
                mstore(0x01, newGarbage)
            }
            mstore(0x20, keccak256(0x00, 0x20))
            mstore(0x00, keccak256(0x10, 0x20))
            newBrutalizeSeed := keccak256(0x00, 0x40)
        }
    }

    function uintArray(bytes memory encoded) internal pure returns (uint256[] memory) {
        uint256 length = encoded.length / 32;
        return
            abi.decode(bytes.concat(bytes32(uint256(0x20)), bytes32(length), encoded), (uint256[]));
    }

    function addressArray(bytes memory encoded) internal pure returns (address[] memory) {
        uint256 length = encoded.length / 32;
        return
            abi.decode(bytes.concat(bytes32(uint256(0x20)), bytes32(length), encoded), (address[]));
    }

    function bumpBlock() internal {
        vm.roll(block.number + 1);
    }

    function deployTokensSorted() internal returns (address, address) {
        address asset0 = address(new MockERC20());
        address asset1 = address(new MockERC20());
        return asset0 < asset1 ? (asset0, asset1) : (asset1, asset0);
    }

    function addrs(bytes memory encoded) internal pure returns (address[] memory) {
        return abi.decode(
            bytes.concat(bytes32(uint256(0x20)), bytes32(encoded.length / 0x20), encoded),
            (address[])
        );
    }

    function setPriorityFee(uint256 fee) internal {
        vm.txGasPrice(block.basefee + fee);
    }

    function min(uint256 x, uint256 y) internal pure returns (uint256) {
        return x < y ? x : y;
    }

    function max(uint256 x, uint256 y) internal pure returns (uint256) {
        return x > y ? x : y;
    }

    function min(int256 x, int256 y) internal pure returns (int256) {
        return x < y ? x : y;
    }

    function min(int24 x, int24 y) internal pure returns (int24) {
        return x < y ? x : y;
    }

    function max(int24 x, int24 y) internal pure returns (int24) {
        return x > y ? x : y;
    }

    function boundE6(uint24 fee) internal pure returns (uint24) {
        return boundE6(fee, 1e6);
    }

    function boundE6(uint24 fee, uint24 upperBound) internal pure returns (uint24) {
        return uint24(bound(fee, 0, upperBound));
    }

    function sort(address asset0, address asset1) internal pure returns (address, address) {
        if (asset0 > asset1) return (asset1, asset0);
        return (asset0, asset1);
    }
}
