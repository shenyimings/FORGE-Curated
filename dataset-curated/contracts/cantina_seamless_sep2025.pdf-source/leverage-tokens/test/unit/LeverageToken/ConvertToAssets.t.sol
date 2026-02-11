// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Internal imports
import {LeverageTokenTest} from "./LeverageToken.t.sol";
import {ILeverageManager} from "src/interfaces/ILeverageManager.sol";

contract ConvertToAssetsTest is LeverageTokenTest {
    function test_convertToAssets() public {
        vm.mockCall(
            address(leverageManager),
            abi.encodeWithSelector(ILeverageManager.convertToAssets.selector, leverageToken, 100 ether),
            abi.encode(200 ether)
        );

        uint256 assets = leverageToken.convertToAssets(100 ether);
        assertEq(assets, 200 ether);
    }
}
