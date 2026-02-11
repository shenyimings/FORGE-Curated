// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Internal imports
import {LeverageManagerTest} from "test/unit/LeverageManager/LeverageManager.t.sol";

contract ConvertToSharesTest is LeverageManagerTest {
    function setUp() public override {
        super.setUp();

        _createDummyLeverageToken();
    }

    function test_convertToShares_RoundedDown() public {
        uint128 equity = 1;
        uint128 sharesTotalSupply = 99;
        uint128 totalEquity = 100;

        _mockState_ConvertToShares(
            ConvertToSharesState({totalEquity: totalEquity, sharesTotalSupply: sharesTotalSupply})
        );

        uint256 shares = leverageManager.exposed_convertToShares(leverageToken, equity);
        assertEq(shares, 0);
    }

    function testFuzz_convertToShares(uint128 equity, uint128 totalEquity, uint128 sharesTotalSupply) public {
        _mockState_ConvertToShares(
            ConvertToSharesState({totalEquity: totalEquity, sharesTotalSupply: sharesTotalSupply})
        );

        uint256 shares = leverageManager.exposed_convertToShares(leverageToken, equity);
        uint256 expectedShares = equity * (uint256(sharesTotalSupply) + 1) / (uint256(totalEquity) + 1);

        assertEq(shares, expectedShares);
    }
}
