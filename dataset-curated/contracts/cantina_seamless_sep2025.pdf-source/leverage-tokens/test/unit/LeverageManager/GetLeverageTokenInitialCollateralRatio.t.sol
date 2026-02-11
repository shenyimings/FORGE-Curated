// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Internal imports
import {ILeverageManager} from "src/interfaces/ILeverageManager.sol";
import {IRebalanceAdapterBase} from "src/interfaces/IRebalanceAdapterBase.sol";
import {LeverageManagerTest} from "./LeverageManager.t.sol";

contract GetLeverageTokenInitialCollateralRatioTest is LeverageManagerTest {
    function setUp() public override {
        super.setUp();

        _createDummyLeverageToken();
    }

    function testFuzz_getLeverageTokenInitialCollateralRatio(uint256 initialCollateralRatio) public {
        initialCollateralRatio = bound(initialCollateralRatio, _BASE_RATIO() + 1, type(uint256).max);

        vm.mockCall(
            address(rebalanceAdapter),
            abi.encodeWithSelector(IRebalanceAdapterBase.getLeverageTokenInitialCollateralRatio.selector, leverageToken),
            abi.encode(initialCollateralRatio)
        );

        assertEq(leverageManager.getLeverageTokenInitialCollateralRatio(leverageToken), initialCollateralRatio);
    }

    function testFuzz_getLeverageTokenInitialCollateralRatio_RevertIf_InitialCollateralRatioIsLessThanOrEqualToBaseRatio(
        uint256 initialCollateralRatio
    ) public {
        initialCollateralRatio = bound(initialCollateralRatio, 0, _BASE_RATIO());

        vm.mockCall(
            address(rebalanceAdapter),
            abi.encodeWithSelector(IRebalanceAdapterBase.getLeverageTokenInitialCollateralRatio.selector, leverageToken),
            abi.encode(initialCollateralRatio)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                ILeverageManager.InvalidLeverageTokenInitialCollateralRatio.selector, initialCollateralRatio
            )
        );
        leverageManager.getLeverageTokenInitialCollateralRatio(leverageToken);
    }
}
