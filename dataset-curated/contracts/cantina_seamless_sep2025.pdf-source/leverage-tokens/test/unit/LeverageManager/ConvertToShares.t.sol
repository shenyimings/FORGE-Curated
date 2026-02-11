// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Dependency imports
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Internal imports
import {ILendingAdapter} from "src/interfaces/ILendingAdapter.sol";
import {LeverageManagerTest} from "test/unit/LeverageManager/LeverageManager.t.sol";

contract ConvertToSharesTest is LeverageManagerTest {
    function setUp() public override {
        super.setUp();

        _createDummyLeverageToken();
    }

    function test_convertToShares() public {
        vm.mockCall(
            address(lendingAdapter),
            abi.encodeWithSelector(ILendingAdapter.getEquityInCollateralAsset.selector),
            abi.encode(150)
        );

        vm.mockCall(address(leverageToken), abi.encodeWithSelector(IERC20.totalSupply.selector), abi.encode(100));

        uint256 shares = leverageManager.convertToShares(leverageToken, 10);
        assertEq(shares, 6); // 10 * 100 / 150 = 6.666666666666666666, rounded down to 6

        vm.mockCall(
            address(lendingAdapter),
            abi.encodeWithSelector(ILendingAdapter.getEquityInCollateralAsset.selector),
            abi.encode(100)
        );

        vm.mockCall(address(leverageToken), abi.encodeWithSelector(IERC20.totalSupply.selector), abi.encode(150));

        shares = leverageManager.convertToShares(leverageToken, 1);
        assertEq(shares, 1); // 1 * 150 / 100 = 1.5, rounded down to 1
    }

    function testFuzz_convertToShares_ZeroTotalEquityInCollateralAsset(
        uint256 equityInCollateralAsset,
        uint256 totalSupply
    ) public {
        vm.mockCall(
            address(lendingAdapter),
            abi.encodeWithSelector(ILendingAdapter.getEquityInCollateralAsset.selector),
            abi.encode(0)
        );

        vm.mockCall(
            address(leverageToken), abi.encodeWithSelector(IERC20.totalSupply.selector), abi.encode(totalSupply)
        );

        uint256 shares = leverageManager.convertToShares(leverageToken, equityInCollateralAsset);
        assertEq(shares, 0);
    }
}
