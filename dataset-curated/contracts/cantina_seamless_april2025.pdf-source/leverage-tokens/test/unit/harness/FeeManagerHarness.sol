// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Dependency imports
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Internal imports
import {ExternalAction} from "src/types/DataTypes.sol";
import {ILeverageToken} from "src/interfaces/ILeverageToken.sol";
import {FeeManager} from "src/FeeManager.sol";

/// @notice Wrapper contract that exposes all internal functions ofFeeManager
contract FeeManagerHarness is FeeManager {
    function initialize(address defaultAdmin) external initializer {
        __FeeManager_init(defaultAdmin);
    }

    function exposed_getFeeManagerStorageSlot() external pure returns (bytes32 slot) {
        FeeManager.FeeManagerStorage storage $ = _getFeeManagerStorage();

        assembly {
            slot := $.slot
        }
    }

    function exposed_computeEquityFees(ILeverageToken token, uint256 equityAmount, ExternalAction action)
        external
        view
        returns (uint256, uint256, uint256, uint256)
    {
        return _computeEquityFees(token, equityAmount, action);
    }

    function exposed_chargeTreasuryFee(IERC20 collateralAsset, uint256 amount) external {
        _chargeTreasuryFee(collateralAsset, amount);
    }

    function exposed_setLeverageTokenActionFee(ILeverageToken token, ExternalAction action, uint256 fee) external {
        _setLeverageTokenActionFee(token, action, fee);
    }
}
