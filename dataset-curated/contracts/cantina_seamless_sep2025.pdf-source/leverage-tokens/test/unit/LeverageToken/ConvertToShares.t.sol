// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Internal imports
import {LeverageTokenTest} from "./LeverageToken.t.sol";
import {ILeverageManager} from "src/interfaces/ILeverageManager.sol";

contract ConvertToSharesTest is LeverageTokenTest {
    function test_convertToShares() public {
        vm.mockCall(
            address(leverageManager),
            abi.encodeWithSelector(ILeverageManager.convertToShares.selector, leverageToken, 100 ether),
            abi.encode(200 ether)
        );

        uint256 shares = leverageToken.convertToShares(100 ether);
        assertEq(shares, 200 ether);
    }
}
