// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {MockAugustusRegistry} from "../mock/MockAugustusRegistry.sol";
import {MockAugustus} from "../mock/MockAugustus.sol";
import {IVeloraAdapter} from "src/interfaces/periphery/IVeloraAdapter.sol";
import {VeloraAdapter} from "src/periphery/VeloraAdapter.sol";
import {MockERC20} from "../mock/MockERC20.sol";

contract VeloraAdapterTest is Test {
    uint256 public constant bytesLength = 1024;

    MockAugustusRegistry public augustusRegistry;
    MockAugustus public augustus;
    IVeloraAdapter public veloraAdapter;

    MockERC20 public collateralToken;
    MockERC20 public debtToken;

    function setUp() public {
        augustusRegistry = new MockAugustusRegistry();
        augustus = new MockAugustus();

        augustusRegistry.setValid(address(augustus), true);

        collateralToken = new MockERC20();
        debtToken = new MockERC20();

        veloraAdapter = new VeloraAdapter(address(augustusRegistry));
    }

    function _boundOffset(uint256 offset) internal pure returns (uint256) {
        return bound(offset, 0, bytesLength - 32 * 3);
    }

    function _makeEmptyAccountCallable(address account) internal {
        assumeNotPrecompile(account);
        assumeNotForgeAddress(account);
        assumeNotZeroAddress(account);
        vm.assume(account != 0x000000000000000000000000000000000000000A);
        vm.assume(account.code.length == 0);
        vm.etch(account, hex"5f5ff3"); // always return null
    }

    function _receiver(address account) internal view {
        assumeNotZeroAddress(account);
        vm.assume(account != address(veloraAdapter));
        vm.assume(account != address(augustus));
        vm.assume(account != address(this));
    }

    function _swapCalldata(uint256 offset, uint256 exactAmount, uint256 limitAmount, uint256 quotedAmount)
        internal
        pure
        returns (bytes memory)
    {
        return bytes.concat(
            new bytes(offset),
            bytes32(exactAmount),
            bytes32(limitAmount),
            bytes32(quotedAmount),
            new bytes(bytesLength - 32 * 3 - offset)
        );
    }
}
