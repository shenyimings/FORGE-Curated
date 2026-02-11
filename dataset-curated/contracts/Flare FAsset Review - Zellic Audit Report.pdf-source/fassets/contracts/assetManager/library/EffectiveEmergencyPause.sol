// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {AssetManagerState} from "./data/AssetManagerState.sol";
import {EmergencyPause} from "../../userInterfaces/data/EmergencyPause.sol";


library EffectiveEmergencyPause {
    function level() internal view returns (EmergencyPause.Level) {
        EmergencyPause.Level externalPauseLevel = externalLevel();
        EmergencyPause.Level governancePauseLevel = governanceLevel();
        return governancePauseLevel > externalPauseLevel ? governancePauseLevel : externalPauseLevel;
    }

    function externalLevel() internal view returns (EmergencyPause.Level) {
        AssetManagerState.State storage state = AssetManagerState.get();
        bool pauseActive = state.emergencyPausedUntil > block.timestamp;
        return pauseActive ? state.emergencyPauseLevel : EmergencyPause.Level.NONE;
    }

    function externalEndTime() internal view returns (uint256) {
        AssetManagerState.State storage state = AssetManagerState.get();
        return externalLevel() != EmergencyPause.Level.NONE ? state.emergencyPausedUntil : 0;
    }

    function governanceLevel() internal view returns (EmergencyPause.Level) {
        AssetManagerState.State storage state = AssetManagerState.get();
        bool pauseActive = state.governanceEmergencyPausedUntil > block.timestamp;
        return pauseActive ? state.governanceEmergencyPauseLevel : EmergencyPause.Level.NONE;
    }

    function governanceEndTime() internal view returns (uint256) {
        AssetManagerState.State storage state = AssetManagerState.get();
        return governanceLevel() != EmergencyPause.Level.NONE ? state.governanceEmergencyPausedUntil : 0;
    }
}
