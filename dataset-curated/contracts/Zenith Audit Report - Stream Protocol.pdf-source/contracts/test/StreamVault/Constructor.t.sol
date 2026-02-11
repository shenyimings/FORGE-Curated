// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {Base} from "./Base.t.sol";
import {Vault} from "../../src/lib/Vault.sol";

/************************************************
 *  CONSTRUCTOR TESTS
 ***********************************************/
contract StreamVaultConstructorTest is Base {
    function test_initializesCorrectly() public {
        assertEq(streamVault.name(), "Stream Yield Bearing USDC");
        assertEq(streamVault.symbol(), "syUSDC");
        assertEq(streamVault.decimals(), 6);
        assertEq(streamVault.totalSupply(), 0);
        assertEq(address(streamVault.endpoint()), address(endpoints[1]));
        assertEq(streamVault.owner(), owner);
        assertEq(streamVault.stableWrapper(), address(stableWrapper));
        verifyVaultState(Vault.VaultState(uint16(1), uint128(0)));
    }
}
