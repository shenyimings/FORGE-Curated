// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { TestDeployer } from "../deploy/TestDeployer.sol";

contract StakedCapStakeTest is TestDeployer {
    address user;

    function setUp() public {
        _deployCapTestEnvironment();
        _initTestVaultLiquidity(usdVault);

        user = makeAddr("test_user");
        _initTestUserMintCapToken(usdVault, user, 4000e18);
    }

    function test_staked_cap_stake() public {
        vm.startPrank(user);

        uint256 cUSDStakedBefore = cUSD.balanceOf(address(scUSD));

        // Now stake the cUSD tokens
        cUSD.approve(address(scUSD), 100e18);
        scUSD.deposit(100e18, user);

        assertEq(scUSD.balanceOf(user), 100e18, "Should have staked cUSD tokens");
        assertEq(cUSD.balanceOf(address(scUSD)), cUSDStakedBefore + 100e18, "Vault should have received cUSD");
        assertEq(cUSD.balanceOf(user), 3900e18, "User must have transferred the cUSD");
    }
}
