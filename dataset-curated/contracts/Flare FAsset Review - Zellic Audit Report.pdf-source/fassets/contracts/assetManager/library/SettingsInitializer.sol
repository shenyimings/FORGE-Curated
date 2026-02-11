// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {SafePct} from "../../utils/library/SafePct.sol";
import {Globals} from "./Globals.sol";
import {SettingsValidators} from "./SettingsValidators.sol";
import {AssetManagerSettings} from "../../userInterfaces/data/AssetManagerSettings.sol";


library SettingsInitializer {

    struct SettingsWrapper {
        AssetManagerSettings.Data settings;
    }

    error CannotBeZero();
    error MustBeZero();
    error WindowTooSmall();
    error ValueTooSmall();
    error BipsValueTooHigh();
    error BipsValueTooLow();
    error MustBeTwoHours();
    error ZeroAddress();
    error MintingCapTooSmall();

    function validateAndSet(
        AssetManagerSettings.Data memory _settings
    )
        internal
    {
        _validateSettings(_settings);
        _setAllSettings(_settings);
    }

    function _setAllSettings(
        AssetManagerSettings.Data memory _settings
    )
        private
    {
        // cannot set value at pointer structure received by Globals.getSettings() due to Solidity limitation,
        // so we need to create wrapper structure at the same address and then set member
        SettingsWrapper storage wrapper;
        bytes32 position = Globals.ASSET_MANAGER_SETTINGS_POSITION;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            wrapper.slot := position
        }
        wrapper.settings = _settings;
    }

    function _validateSettings(
        AssetManagerSettings.Data memory _settings
    )
        private pure
    {
        require(_settings.fAsset != address(0), ZeroAddress());
        require(_settings.agentVaultFactory != address(0), ZeroAddress());
        require(_settings.collateralPoolFactory != address(0), ZeroAddress());
        require(_settings.collateralPoolTokenFactory != address(0), ZeroAddress());
        require(_settings.fdcVerification != address(0), ZeroAddress());
        require(_settings.priceReader != address(0), ZeroAddress());
        require(_settings.agentOwnerRegistry != address(0), ZeroAddress());

        require(_settings.assetUnitUBA > 0, CannotBeZero());
        require(_settings.assetMintingGranularityUBA > 0, CannotBeZero());
        require(_settings.underlyingBlocksForPayment > 0, CannotBeZero());
        require(_settings.underlyingSecondsForPayment > 0, CannotBeZero());
        require(_settings.redemptionFeeBIPS > 0, CannotBeZero());
        require(_settings.collateralReservationFeeBIPS > 0, CannotBeZero());
        require(_settings.confirmationByOthersRewardUSD5 > 0, CannotBeZero());
        require(_settings.maxRedeemedTickets > 0, CannotBeZero());
        require(_settings.maxTrustedPriceAgeSeconds > 0, CannotBeZero());
        require(_settings.minUpdateRepeatTimeSeconds > 0, CannotBeZero());
        require(_settings.withdrawalWaitMinSeconds > 0, CannotBeZero());
        require(_settings.averageBlockTimeMS > 0, CannotBeZero());
        SettingsValidators.validateTimeForPayment(_settings.underlyingBlocksForPayment,
            _settings.underlyingSecondsForPayment, _settings.averageBlockTimeMS);
        require(_settings.lotSizeAMG > 0, CannotBeZero());
        require(_settings.mintingCapAMG == 0 || _settings.mintingCapAMG >= _settings.lotSizeAMG,
            MintingCapTooSmall());
        require(_settings.collateralReservationFeeBIPS <= SafePct.MAX_BIPS, BipsValueTooHigh());
        require(_settings.redemptionFeeBIPS <= SafePct.MAX_BIPS, BipsValueTooHigh());
        require(_settings.redemptionDefaultFactorVaultCollateralBIPS > SafePct.MAX_BIPS, BipsValueTooLow());
        require(_settings.attestationWindowSeconds >= 1 days, WindowTooSmall());
        require(_settings.confirmationByOthersAfterSeconds >= 2 hours, MustBeTwoHours());
        require(_settings.vaultCollateralBuyForFlareFactorBIPS >= SafePct.MAX_BIPS, ValueTooSmall());
        require(_settings.agentTimelockedOperationWindowSeconds >= 1 hours, ValueTooSmall());
        require(_settings.collateralPoolTokenTimelockSeconds >= 1 minutes, ValueTooSmall());
        require(_settings.liquidationStepSeconds > 0, CannotBeZero());
        SettingsValidators.validateLiquidationFactors(_settings.liquidationCollateralFactorBIPS,
            _settings.liquidationFactorVaultCollateralBIPS);
        // removed settings
        require(_settings.__whitelist == address(0), MustBeZero());
        require(_settings.__requireEOAAddressProof == false, MustBeZero());
        require(_settings.__ccbTimeSeconds == 0, MustBeZero());
        require(_settings.__announcedUnderlyingConfirmationMinSeconds == 0, MustBeZero());
        require(_settings.__buybackCollateralFactorBIPS == 0, MustBeZero());
        require(_settings.__tokenInvalidationTimeMinSeconds == 0, MustBeZero());
        require(_settings.__minUnderlyingBackingBIPS == 0, MustBeZero());
        require(_settings.__redemptionDefaultFactorPoolBIPS == 0, MustBeZero());
        require(_settings.__cancelCollateralReservationAfterSeconds == 0, MustBeZero());
        require(_settings.__rejectOrCancelCollateralReservationReturnFactorBIPS == 0, MustBeZero());
        require(_settings.__rejectRedemptionRequestWindowSeconds == 0, MustBeZero());
        require(_settings.__takeOverRedemptionRequestWindowSeconds == 0, MustBeZero());
        require(_settings.__rejectedRedemptionDefaultFactorVaultCollateralBIPS == 0, MustBeZero());
        require(_settings.__rejectedRedemptionDefaultFactorPoolBIPS == 0, MustBeZero());
    }
}