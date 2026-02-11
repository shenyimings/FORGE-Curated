// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Dependency imports
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

// Internal imports
import {ILeverageToken} from "src/interfaces/ILeverageToken.sol";
import {ILendingAdapter} from "src/interfaces/ILendingAdapter.sol";
import {ILeverageManager} from "src/interfaces/ILeverageManager.sol";
import {IRebalanceAdapterBase} from "src/interfaces/IRebalanceAdapterBase.sol";
import {LeverageManagerTest} from "./LeverageManager.t.sol";
import {LeverageTokenConfig} from "src/types/DataTypes.sol";
import {LeverageToken} from "src/LeverageToken.sol";
import {MockRebalanceAdapter} from "test/unit/mock/MockRebalanceAdapter.sol";

contract CreateNewLeverageTokenTest is LeverageManagerTest {
    function testFuzz_CreateNewLeverageToken(
        LeverageTokenConfig memory config,
        uint256 targetCollateralRatio,
        address collateralAsset,
        address debtAsset,
        string memory name,
        string memory symbol,
        string memory rebalanceAdapterName,
        string memory lendingAdapterName,
        address _treasury,
        uint256 defaultManagementFeeAtCreation
    ) public {
        vm.assume(_treasury != address(0));
        defaultManagementFeeAtCreation = bound(defaultManagementFeeAtCreation, 0, MAX_MANAGEMENT_FEE);

        _setTreasury(feeManagerRole, _treasury);
        _setDefaultManagementFeeAtCreation(feeManagerRole, defaultManagementFeeAtCreation);

        config.rebalanceAdapter = IRebalanceAdapterBase(makeAddr(rebalanceAdapterName));
        config.lendingAdapter = ILendingAdapter(makeAddr(lendingAdapterName));

        config.mintTokenFee = bound(config.mintTokenFee, 0, MAX_ACTION_FEE);
        config.redeemTokenFee = bound(config.redeemTokenFee, 0, MAX_ACTION_FEE);

        address expectedLeverageTokenAddress = leverageTokenFactory.computeProxyAddress(
            address(leverageManager),
            abi.encodeWithSelector(LeverageToken.initialize.selector, address(leverageManager), name, symbol),
            0
        );

        _createNewLeverageToken(manager, targetCollateralRatio, config, collateralAsset, debtAsset, name, symbol);

        // Check name of the leverage token
        assertEq(IERC20Metadata(expectedLeverageTokenAddress).name(), name);
        assertEq(IERC20Metadata(expectedLeverageTokenAddress).symbol(), symbol);

        // Check if the leverage token core is set correctly
        LeverageTokenConfig memory configAfter = leverageManager.getLeverageTokenConfig(leverageToken);
        assertEq(address(configAfter.lendingAdapter), address(config.lendingAdapter));
        assertEq(address(configAfter.rebalanceAdapter), address(config.rebalanceAdapter));

        assertEq(configAfter.mintTokenFee, config.mintTokenFee);
        assertEq(configAfter.redeemTokenFee, config.redeemTokenFee);

        assertEq(address(leverageManager.getLeverageTokenCollateralAsset(leverageToken)), collateralAsset);
        assertEq(address(leverageManager.getLeverageTokenDebtAsset(leverageToken)), debtAsset);

        assertEq(
            address(leverageManager.getLeverageTokenRebalanceAdapter(leverageToken)), address(config.rebalanceAdapter)
        );

        // We don't revert if the initial collateral ratio is less than or equal to the base ratio on LT creation, since
        // RebalanceAdapters can technically update the initial collateral ratio after creation anyway.
        if (targetCollateralRatio <= _BASE_RATIO()) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    ILeverageManager.InvalidLeverageTokenInitialCollateralRatio.selector, targetCollateralRatio
                )
            );
            leverageManager.getLeverageTokenInitialCollateralRatio(leverageToken);
        } else {
            assertEq(leverageManager.getLeverageTokenInitialCollateralRatio(leverageToken), targetCollateralRatio);
        }

        assertEq(leverageManager.getLastManagementFeeAccrualTimestamp(leverageToken), block.timestamp);
    }
}
