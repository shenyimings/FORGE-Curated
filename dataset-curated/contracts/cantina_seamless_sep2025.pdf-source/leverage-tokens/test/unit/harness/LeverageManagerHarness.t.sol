// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Dependency imports
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Internal imports
import {IFeeManager} from "src/interfaces/IFeeManager.sol";
import {ILeverageToken} from "src/interfaces/ILeverageToken.sol";
import {FeeManagerHarness} from "test/unit/harness/FeeManagerHarness.sol";
import {LeverageManager} from "src/LeverageManager.sol";
import {ActionData, ActionType, ExternalAction, LeverageTokenState} from "src/types/DataTypes.sol";

/// @notice Wrapper contract that exposes all internal functions of LeverageManager
contract LeverageManagerHarness is LeverageManager, FeeManagerHarness {
    function exposed_getLeverageManagerStorageSlot() external pure returns (bytes32 slot) {
        LeverageManager.LeverageManagerStorage storage $ = _getLeverageManagerStorage();

        assembly {
            slot := $.slot
        }
    }

    function exposed_authorizeUpgrade(address newImplementation) external {
        _authorizeUpgrade(newImplementation);
    }

    function exposed_transferTokens(IERC20 token, address from, address to, uint256 amount) external {
        _transferTokens(token, from, to, amount);
    }

    function exposed_executeLendingAdapterAction(ILeverageToken leverageToken, ActionType actionType, uint256 amount)
        external
    {
        _executeLendingAdapterAction(leverageToken, actionType, amount);
    }

    function exposed_getReentrancyGuardTransientStorage() external view returns (bool) {
        // slot used in OZ's ReentrancyGuardTransient
        bytes32 slot = 0x9b779b17422d0df92223018b32b4d1fa46e071723d6817e2486d003becc55f00;

        bool value;
        assembly {
            value := tload(slot)
        }

        return value;
    }
}
