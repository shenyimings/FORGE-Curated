// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {AssetManagerBase} from "./AssetManagerBase.sol";
import {Globals} from "../library/Globals.sol";
import {SettingsUpdater} from "../library/SettingsUpdater.sol";
import {RedemptionTimeExtension} from "../library/data/RedemptionTimeExtension.sol";
import {LibDiamond} from "../../diamond/library/LibDiamond.sol";
import {AssetManagerSettings} from "../../userInterfaces/data/AssetManagerSettings.sol";
import {IAssetManagerEvents} from "../../userInterfaces/IAssetManagerEvents.sol";
import {IRedemptionTimeExtension} from "../../userInterfaces/IRedemptionTimeExtension.sol";


contract RedemptionTimeExtensionFacet is AssetManagerBase, IRedemptionTimeExtension {

    error ValueMustBeNonzero();
    error DecreaseTooBig();
    error IncreaseTooBig();
    error AlreadyInitialized();
    error DiamondNotInitialized();

    constructor() {
        // implementation initialization - to prevent reinitialization
        RedemptionTimeExtension.setRedemptionPaymentExtensionSeconds(1);
    }

    // this method is not accessible through diamond proxy
    // it is only used for initialization when the contract is added after proxy deploy
    function initRedemptionTimeExtensionFacet(uint256 _redemptionPaymentExtensionSeconds)
        external
    {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        require(ds.supportedInterfaces[type(IERC165).interfaceId], DiamondNotInitialized());
        ds.supportedInterfaces[type(IRedemptionTimeExtension).interfaceId] = true;
        require(RedemptionTimeExtension.redemptionPaymentExtensionSeconds() == 0, AlreadyInitialized());
        // init settings
        RedemptionTimeExtension.setRedemptionPaymentExtensionSeconds(_redemptionPaymentExtensionSeconds);
    }

    function setRedemptionPaymentExtensionSeconds(uint256 _value)
        external
        onlyAssetManagerController
    {
        SettingsUpdater.checkEnoughTimeSinceLastUpdate();
        // validate
        AssetManagerSettings.Data storage settings = Globals.getSettings();
        uint256 currentValue = RedemptionTimeExtension.redemptionPaymentExtensionSeconds();
        require(_value <= currentValue * 4 + settings.averageBlockTimeMS / 1000, IncreaseTooBig());
        require(_value >= currentValue / 4, DecreaseTooBig());
        require(_value > 0, ValueMustBeNonzero());
        // update
        RedemptionTimeExtension.setRedemptionPaymentExtensionSeconds(_value);
        emit IAssetManagerEvents.SettingChanged("redemptionPaymentExtensionSeconds", _value);
    }

    function redemptionPaymentExtensionSeconds()
        external view
        returns (uint256)
    {
        return RedemptionTimeExtension.redemptionPaymentExtensionSeconds();
    }
}