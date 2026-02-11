// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { TestDeployer } from "../deploy/TestDeployer.sol";

contract StakedCapWithdrawTest is TestDeployer {
    address user;

    function setUp() public {
        _deployCapTestEnvironment();
        _initTestVaultLiquidity(usdVault);

        user = makeAddr("test_user");
        _initTestUserStakedCapToken(usdVault, user, 4000e18);
    }

    function test_staked_cap_withdraw() public {
        vm.startPrank(user);

        uint256 outputAmount = scUSD.withdraw(100e18, user, user);

        assertEq(outputAmount, 100e18, "Should have received 100 cUSD");
        assertEq(scUSD.balanceOf(user), 4000e18 - 100e18, "Should have burned some scUSD tokens");
        assertEq(cUSD.balanceOf(user), 100e18, "Should have gained back their cUSD tokens");
    }
}
