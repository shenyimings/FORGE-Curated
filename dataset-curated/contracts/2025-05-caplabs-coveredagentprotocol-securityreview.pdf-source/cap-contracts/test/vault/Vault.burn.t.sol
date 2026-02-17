// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { TestDeployer } from "../deploy/TestDeployer.sol";

contract VaultBurnTest is TestDeployer {
    address user;

    function setUp() public {
        _deployCapTestEnvironment();
        _initTestVaultLiquidity(usdVault);

        user = makeAddr("test_user");
        _initTestUserMintCapToken(usdVault, user, 4000e18);
    }

    function test_vault_burn() public {
        vm.startPrank(user);

        // burn the cUSD tokens we own
        uint256 burnAmount = 100e18;
        uint256 minOutputAmount = 95e6; // Expect at least 95% back accounting for potential fees
        uint256 deadline = block.timestamp + 1 hours;

        uint256 outputAmount = cUSD.burn(address(usdt), burnAmount, minOutputAmount, user, deadline);

        // Verify final balances
        assertEq(cUSD.balanceOf(user), 4000e18 - burnAmount, "Should have burned their cUSD tokens");
        assertEq(outputAmount, usdt.balanceOf(user), "Should have received minOutputAmount back");
        assertGt(outputAmount, 0, "Should have received more than 0 USDT back");
    }
}
