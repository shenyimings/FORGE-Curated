// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {IIAddressUpdater}
    from "@flarenetwork/flare-periphery-contracts/flare/addressUpdater/interfaces/IIAddressUpdater.sol";
import {IWNat} from "../../flareSmartContracts/interfaces/IWNat.sol";
import {IISettingsManagement} from "../../assetManager/interfaces/IISettingsManagement.sol";
import {IIAssetManagerController} from "../interfaces/IIAssetManagerController.sol";
import {GovernedProxyImplementation} from "../../governance/implementation/GovernedProxyImplementation.sol";
import {AddressUpdatable} from "../../flareSmartContracts/implementation/AddressUpdatable.sol";
import {IIAssetManager} from "../../assetManager/interfaces/IIAssetManager.sol";
import {IGovernanceSettings} from "@flarenetwork/flare-periphery-contracts/flare/IGovernanceSettings.sol";
import {IAssetManager} from "../../userInterfaces/IAssetManager.sol";
import {IUUPSUpgradeable} from "../../utils/interfaces/IUUPSUpgradeable.sol";
import {CollateralType} from "../../userInterfaces/data/CollateralType.sol";
import {EmergencyPause} from "../../userInterfaces/data/EmergencyPause.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IGoverned} from "../../governance/interfaces/IGoverned.sol";
import {IAssetManagerController} from "../../userInterfaces/IAssetManagerController.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IIAddressUpdatable}
    from "@flarenetwork/flare-periphery-contracts/flare/addressUpdater/interfaces/IIAddressUpdatable.sol";
import {IAddressUpdatable} from "../../flareSmartContracts/interfaces/IAddressUpdatable.sol";
import {IRedemptionTimeExtension} from "../../userInterfaces/IRedemptionTimeExtension.sol";
import {GovernedBase} from "../../governance/implementation/GovernedBase.sol";


contract AssetManagerController is
    UUPSUpgradeable,
    GovernedProxyImplementation,
    AddressUpdatable,
    IIAssetManagerController
{
    using EnumerableSet for EnumerableSet.AddressSet;

    error AssetManagerNotManaged();
    error OnlyGovernanceOrEmergencyPauseSenders();
    error AddressZero();

    /**
     * New address in case this controller was replaced.
     * Note: this code contains no checks that replacedBy==0, because when replaced,
     * all calls to AssetManager's updateSettings/pause will fail anyway
     * since they will arrive from wrong controller address.
     */
    address public replacedBy;

    mapping(address => uint256) private assetManagerIndex;
    IIAssetManager[] private assetManagers;

    EnumerableSet.AddressSet private emergencyPauseSenders;

    constructor()
        GovernedProxyImplementation()
        AddressUpdatable(address(0))
    {
    }

    /**
     * Proxyable initialization method. Can be called only once, from the proxy constructor
     * (single call is assured by GovernedBase.initialise).
     */
    function initialize(
        IGovernanceSettings _governanceSettings,
        address _initialGovernance,
        address _addressUpdater
    )
        external
    {
        GovernedBase.initialise(_governanceSettings, _initialGovernance);
        AddressUpdatable.setAddressUpdaterValue(_addressUpdater);
    }

    /**
     * Add an asset manager to this controller. The asset manager controller address in the settings of the
     * asset manager must match this. This method automatically marks the asset manager as attached.
     */
    function addAssetManager(IIAssetManager _assetManager)
        external
        onlyGovernance
    {
        if (assetManagerIndex[address(_assetManager)] != 0) return;
        assetManagers.push(_assetManager);
        assetManagerIndex[address(_assetManager)] = assetManagers.length;  // 1+index, so that 0 means empty
        // have to check, otherwise it fails when the controller is replaced
        if (_assetManager.assetManagerController() == address(this)) {
            _assetManager.attachController(true);
        }
    }

    /**
     * Remove an asset manager from this controller, if it is attached to this controller.
     * The asset manager won't be attached any more, so it will be unusable.
     */
    function removeAssetManager(IIAssetManager _assetManager)
        external
        onlyGovernance
    {
        uint256 position = assetManagerIndex[address(_assetManager)];
        if (position == 0) return;
        uint256 index = position - 1;   // the real index, can be 0
        uint256 lastIndex = assetManagers.length - 1;
        if (index < lastIndex) {
            assetManagers[index] = assetManagers[lastIndex];
            assetManagerIndex[address(assetManagers[index])] = index + 1;
        }
        assetManagers.pop();
        assetManagerIndex[address(_assetManager)] = 0;
        // have to check, otherwise it fails when the controller is replaced
        if (_assetManager.assetManagerController() == address(this)) {
            _assetManager.attachController(false);
        }
    }

    /**
     * Return the list of all asset managers managed by this controller.
     */
    function getAssetManagers()
        external view
        returns (IAssetManager[] memory _assetManagers)
    {
        uint256 length = assetManagers.length;
        _assetManagers = new IAssetManager[](length);
        for (uint256 i = 0; i < length; i++) {
            _assetManagers[i] = assetManagers[i];
        }
    }

    /**
     * Check whether the asset manager is managed by this controller.
     * @param _assetManager an asset manager address
     */
    function assetManagerExists(address _assetManager)
        external view
        returns (bool)
    {
        return assetManagerIndex[_assetManager] != 0;
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    // UUPS Proxy

    /**
     * See UUPSUpgradeable.upgradeTo
     */
    function upgradeTo(address newImplementation)
        public override (IUUPSUpgradeable, UUPSUpgradeable)
        onlyGovernance
        onlyProxy
    {
        _upgradeToAndCallUUPS(newImplementation, new bytes(0), false);
    }

    /**
     * See UUPSUpgradeable.upgradeToAndCall
     */
    function upgradeToAndCall(address newImplementation, bytes memory data)
        public payable override (IUUPSUpgradeable, UUPSUpgradeable)
        onlyGovernance
        onlyProxy
    {
        _upgradeToAndCallUUPS(newImplementation, data, true);
    }

    /**
     * Unused. Only present to satisfy UUPSUpgradeable requirement.
     * The real check is in onlyGovernance modifier on upgradeTo and upgradeToAndCall.
     */
    function _authorizeUpgrade(address /* _newImplementation */)
        internal pure override
    {
        assert(false);
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    // Setters

    function setAgentOwnerRegistry(IIAssetManager[] memory _assetManagers, address _value)
        external
        onlyGovernance
    {
        _setValueOnManagers(_assetManagers,
            IISettingsManagement.setAgentOwnerRegistry.selector, _value);
    }

    function setAgentVaultFactory(IIAssetManager[] memory _assetManagers, address _value)
        external
        onlyGovernance
    {
        _setValueOnManagers(_assetManagers,
            IISettingsManagement.setAgentVaultFactory.selector, _value);
    }

    function setCollateralPoolFactory(IIAssetManager[] memory _assetManagers, address _value)
        external
        onlyGovernance
    {
        _setValueOnManagers(_assetManagers,
            IISettingsManagement.setCollateralPoolFactory.selector, _value);
    }

    function setCollateralPoolTokenFactory(IIAssetManager[] memory _assetManagers, address _value)
        external
        onlyGovernance
    {
        _setValueOnManagers(_assetManagers,
            IISettingsManagement.setCollateralPoolTokenFactory.selector, _value);
    }

    function upgradeAgentVaultsAndPools(IIAssetManager[] memory _assetManagers, uint256 _start, uint256 _end)
        external
        onlyImmediateGovernance
    {
        _callOnManagers(_assetManagers,
            abi.encodeCall(IIAssetManager.upgradeAgentVaultsAndPools, (_start, _end)));
    }

    function setPriceReader(IIAssetManager[] memory _assetManagers, address _value)
        external
        onlyGovernance
    {
        _setValueOnManagers(_assetManagers,
            IISettingsManagement.setPriceReader.selector, _value);
    }

    function setFdcVerification(IIAssetManager[] memory _assetManagers, address _value)
        external
        onlyGovernance
    {
        _setValueOnManagers(_assetManagers,
            IISettingsManagement.setFdcVerification.selector, _value);
    }

    function setCleanerContract(IIAssetManager[] memory _assetManagers, address _value)
        external
        onlyImmediateGovernance
    {
        _setValueOnManagers(_assetManagers,
            IISettingsManagement.setCleanerContract.selector, _value);
    }

    function setCleanupBlockNumberManager(IIAssetManager[] memory _assetManagers, address _value)
        external
        onlyGovernance
    {
        _setValueOnManagers(_assetManagers,
            IISettingsManagement.setCleanupBlockNumberManager.selector, _value);
    }

    // if callData is not empty, it is abi encoded call to init function in the new proxy implementation
    function upgradeFAssetImplementation(
        IIAssetManager[] memory _assetManagers,
        address _implementation,
        bytes memory _callData
    )
        external
        onlyGovernance
    {
        _callOnManagers(_assetManagers,
            abi.encodeCall(IISettingsManagement.upgradeFAssetImplementation, (_implementation, _callData)));
    }

    function setMinUpdateRepeatTimeSeconds(IIAssetManager[] memory _assetManagers, uint256 _value)
        external
        onlyGovernance
    {
        _setValueOnManagers(_assetManagers,
            IISettingsManagement.setMinUpdateRepeatTimeSeconds.selector, _value);
    }

    function setLotSizeAmg(IIAssetManager[] memory _assetManagers, uint256 _value)
        external
        onlyGovernance
    {
        _setValueOnManagers(_assetManagers,
            IISettingsManagement.setLotSizeAmg.selector, _value);
    }

    function setTimeForPayment(
        IIAssetManager[] memory _assetManagers,
        uint256 _underlyingBlocks,
        uint256 _underlyingSeconds
    )
        external
        onlyGovernance
    {
        _callOnManagers(_assetManagers,
            abi.encodeCall(IISettingsManagement.setTimeForPayment, (_underlyingBlocks, _underlyingSeconds)));
    }

    function setPaymentChallengeReward(
        IIAssetManager[] memory _assetManagers,
        uint256 _rewardVaultCollateralUSD5,
        uint256 _rewardBIPS
    )
        external
        onlyImmediateGovernance
    {
        _callOnManagers(_assetManagers,
            abi.encodeCall(IISettingsManagement.setPaymentChallengeReward, (_rewardVaultCollateralUSD5, _rewardBIPS)));
    }

    function setMaxTrustedPriceAgeSeconds(IIAssetManager[] memory _assetManagers, uint256 _value)
        external
        onlyImmediateGovernance
    {
        _setValueOnManagers(_assetManagers,
            IISettingsManagement.setMaxTrustedPriceAgeSeconds.selector, _value);
    }

    function setCollateralReservationFeeBips(IIAssetManager[] memory _assetManagers, uint256 _value)
        external
        onlyImmediateGovernance
    {
        _setValueOnManagers(_assetManagers,
            IISettingsManagement.setCollateralReservationFeeBips.selector, _value);
    }

    function setRedemptionFeeBips(IIAssetManager[] memory _assetManagers, uint256 _value)
        external
        onlyImmediateGovernance
    {
        _setValueOnManagers(_assetManagers,
            IISettingsManagement.setRedemptionFeeBips.selector, _value);
    }

    function setRedemptionDefaultFactorVaultCollateralBIPS(IIAssetManager[] memory _assetManagers, uint256 _value)
        external
        onlyImmediateGovernance
    {
        _setValueOnManagers(_assetManagers,
            IISettingsManagement.setRedemptionDefaultFactorVaultCollateralBIPS.selector, _value);
    }

    function setConfirmationByOthersAfterSeconds(IIAssetManager[] memory _assetManagers, uint256 _value)
        external
        onlyImmediateGovernance
    {
        _setValueOnManagers(_assetManagers,
            IISettingsManagement.setConfirmationByOthersAfterSeconds.selector, _value);
    }

    function setConfirmationByOthersRewardUSD5(IIAssetManager[] memory _assetManagers, uint256 _value)
        external
        onlyImmediateGovernance
    {
        _setValueOnManagers(_assetManagers,
            IISettingsManagement.setConfirmationByOthersRewardUSD5.selector, _value);
    }

    function setMaxRedeemedTickets(IIAssetManager[] memory _assetManagers, uint256 _value)
        external
        onlyImmediateGovernance
    {
        _setValueOnManagers(_assetManagers,
            IISettingsManagement.setMaxRedeemedTickets.selector, _value);
    }

    function setWithdrawalOrDestroyWaitMinSeconds(IIAssetManager[] memory _assetManagers, uint256 _value)
        external
        onlyImmediateGovernance
    {
        _setValueOnManagers(_assetManagers,
            IISettingsManagement.setWithdrawalOrDestroyWaitMinSeconds.selector, _value);
    }

    function setAttestationWindowSeconds(IIAssetManager[] memory _assetManagers, uint256 _value)
        external
        onlyImmediateGovernance
    {
        _setValueOnManagers(_assetManagers,
            IISettingsManagement.setAttestationWindowSeconds.selector, _value);
    }

    function setAverageBlockTimeMS(IIAssetManager[] memory _assetManagers, uint256 _value)
        external
        onlyImmediateGovernance
    {
        _setValueOnManagers(_assetManagers,
            IISettingsManagement.setAverageBlockTimeMS.selector, _value);
    }

    function setMintingPoolHoldingsRequiredBIPS(IIAssetManager[] memory _assetManagers, uint256 _value)
        external
        onlyImmediateGovernance
    {
        _setValueOnManagers(_assetManagers,
            IISettingsManagement.setMintingPoolHoldingsRequiredBIPS.selector, _value);
    }

    function setMintingCapAmg(IIAssetManager[] memory _assetManagers, uint256 _value)
        external
        onlyImmediateGovernance
    {
        _setValueOnManagers(_assetManagers,
            IISettingsManagement.setMintingCapAmg.selector, _value);
    }

    function setVaultCollateralBuyForFlareFactorBIPS(IIAssetManager[] memory _assetManagers, uint256 _value)
        external
        onlyGovernance
    {
        _setValueOnManagers(_assetManagers,
            IISettingsManagement.setVaultCollateralBuyForFlareFactorBIPS.selector, _value);
    }

    function setAgentExitAvailableTimelockSeconds(IIAssetManager[] memory _assetManagers, uint256 _value)
        external
        onlyImmediateGovernance
    {
        _setValueOnManagers(_assetManagers,
            IISettingsManagement.setAgentExitAvailableTimelockSeconds.selector, _value);
    }

    function setAgentFeeChangeTimelockSeconds(IIAssetManager[] memory _assetManagers, uint256 _value)
        external
        onlyImmediateGovernance
    {
        _setValueOnManagers(_assetManagers,
            IISettingsManagement.setAgentFeeChangeTimelockSeconds.selector, _value);
    }

    function setAgentMintingCRChangeTimelockSeconds(IIAssetManager[] memory _assetManagers, uint256 _value)
        external
        onlyImmediateGovernance
    {
        _setValueOnManagers(_assetManagers,
            IISettingsManagement.setAgentMintingCRChangeTimelockSeconds.selector, _value);
    }

    function setPoolExitCRChangeTimelockSeconds(IIAssetManager[] memory _assetManagers, uint256 _value)
        external
        onlyImmediateGovernance
    {
        _setValueOnManagers(_assetManagers,
            IISettingsManagement.setPoolExitCRChangeTimelockSeconds.selector, _value);
    }

    function setAgentTimelockedOperationWindowSeconds(IIAssetManager[] memory _assetManagers, uint256 _value)
        external
        onlyImmediateGovernance
    {
        _setValueOnManagers(_assetManagers,
            IISettingsManagement.setAgentTimelockedOperationWindowSeconds.selector, _value);
    }

    function setCollateralPoolTokenTimelockSeconds(IIAssetManager[] memory _assetManagers, uint256 _value)
        external
        onlyImmediateGovernance
    {
        _setValueOnManagers(_assetManagers,
            IISettingsManagement.setCollateralPoolTokenTimelockSeconds.selector, _value);
    }

    function setLiquidationStepSeconds(IIAssetManager[] memory _assetManagers, uint256 _value)
        external
        onlyGovernance
    {
        _setValueOnManagers(_assetManagers,
            IISettingsManagement.setLiquidationStepSeconds.selector, _value);
    }

    function setLiquidationPaymentFactors(
        IIAssetManager[] memory _assetManagers,
        uint256[] memory _paymentFactors,
        uint256[] memory _vaultCollateralFactors
    )
        external
        onlyGovernance
    {
        _callOnManagers(_assetManagers,
            abi.encodeCall(IISettingsManagement.setLiquidationPaymentFactors,
                (_paymentFactors, _vaultCollateralFactors)));
    }

    function setRedemptionPaymentExtensionSeconds(
        IIAssetManager[] memory _assetManagers,
        uint256 _value
    )
        external
        onlyImmediateGovernance
    {
        _setValueOnManagers(_assetManagers,
            IRedemptionTimeExtension.setRedemptionPaymentExtensionSeconds.selector, _value);
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    // Collateral tokens

    function addCollateralType(
        IIAssetManager[] memory _assetManagers,
        CollateralType.Data calldata _data
    )
        external
        onlyImmediateGovernance
    {
        _callOnManagers(_assetManagers,
            abi.encodeCall(IIAssetManager.addCollateralType, (_data)));
    }

    function setCollateralRatiosForToken(
        IIAssetManager[] memory _assetManagers,
        CollateralType.Class _class,
        IERC20 _token,
        uint256 _minCollateralRatioBIPS,
        uint256 _safetyMinCollateralRatioBIPS
    )
        external
        onlyGovernance
    {
        _callOnManagers(_assetManagers,
            abi.encodeCall(IIAssetManager.setCollateralRatiosForToken,
                (_class, _token, _minCollateralRatioBIPS, _safetyMinCollateralRatioBIPS)));
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    // Upgrade (second phase)

    /**
     * When asset manager is paused, no new minting can be made.
     * All other operations continue normally.
     */
    function pauseMinting(IIAssetManager[] calldata _assetManagers)
        external
        onlyImmediateGovernance
    {
        _callOnManagers(_assetManagers, abi.encodeCall(IIAssetManager.pauseMinting, ()));
    }

    /**
     * Minting can continue.
     */
    function unpauseMinting(IIAssetManager[] calldata _assetManagers)
        external
        onlyImmediateGovernance
    {
        _callOnManagers(_assetManagers, abi.encodeCall(IIAssetManager.unpauseMinting, ()));
    }

    ////////////////////////////////////////////////////////////////////////////////////
    // ERC 165

    /**
     * Implementation of ERC-165 interface.
     */
    function supportsInterface(bytes4 _interfaceId)
        external pure override
        returns (bool)
    {
        return _interfaceId == type(IERC165).interfaceId
            || _interfaceId == type(IAddressUpdatable).interfaceId
            || _interfaceId == type(IIAddressUpdatable).interfaceId
            || _interfaceId == type(IAssetManagerController).interfaceId
            || _interfaceId == type(IIAssetManagerController).interfaceId
            || _interfaceId == type(IGoverned).interfaceId;
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    // Update contracts

    /**
     * Can be called to update address updater managed contracts if there are too many asset managers
     * to update in one block. In such a case, running AddressUpdater.updateContractAddresses will fail
     * and there will be no way to update contracts. This method allow the update to only change some
     * of the asset managers.
     */
    function updateContracts(IIAssetManager[] calldata _assetManagers)
        external
    {
        // read contract addresses
        IIAddressUpdater addressUpdater = IIAddressUpdater(getAddressUpdater());
        address newAddressUpdater = addressUpdater.getContractAddress("AddressUpdater");
        address assetManagerController = addressUpdater.getContractAddress("AssetManagerController");
        address wNat = addressUpdater.getContractAddress("WNat");
        require(newAddressUpdater != address(0) && assetManagerController != address(0) && wNat != address(0),
            AddressZero());
        _updateContracts(_assetManagers, newAddressUpdater, assetManagerController, wNat);
    }

    // called by AddressUpdater.update or AddressUpdater.updateContractAddresses
    function _updateContractAddresses(
        bytes32[] memory _contractNameHashes,
        address[] memory _contractAddresses
    )
        internal override
    {
        address addressUpdater =
            _getContractAddress(_contractNameHashes, _contractAddresses, "AddressUpdater");
        address assetManagerController =
            _getContractAddress(_contractNameHashes, _contractAddresses, "AssetManagerController");
        address wNat =
            _getContractAddress(_contractNameHashes, _contractAddresses, "WNat");
        _updateContracts(assetManagers, addressUpdater, assetManagerController, wNat);
    }

    function _updateContracts(
        IIAssetManager[] memory _assetManagers,
        address addressUpdater,
        address assetManagerController,
        address wNat
    )
        private
    {
        // update address updater if necessary
        if (addressUpdater != getAddressUpdater()) {
            setAddressUpdaterValue(addressUpdater);
        }
        // update contracts on asset managers
        _callOnManagers(_assetManagers,
            abi.encodeCall(IISettingsManagement.updateSystemContracts,
                (assetManagerController, IWNat(wNat))));
        // if this controller was replaced, set forwarding address
        if (assetManagerController != address(this)) {
            replacedBy = assetManagerController;
        }
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    // Emergency pause

    function emergencyPauseStartOperations(IIAssetManager[] memory _assetManagers, uint256 _duration)
        external
    {
        _emergencyPause(_assetManagers, EmergencyPause.Level.START_OPERATIONS, _duration);
    }

    function emergencyPauseFull(IIAssetManager[] memory _assetManagers, uint256 _duration)
        external
    {
        _emergencyPause(_assetManagers, EmergencyPause.Level.FULL, _duration);
    }

    function emergencyPauseFullAndTransfer(IIAssetManager[] memory _assetManagers, uint256 _duration)
        external
    {
        _emergencyPause(_assetManagers, EmergencyPause.Level.FULL_AND_TRANSFER, _duration);
    }

    function cancelEmergencyPause(IIAssetManager[] memory _assetManagers)
        external
    {
        _emergencyPause(_assetManagers, EmergencyPause.Level.NONE, 0);
    }

    // cancel pause triggered by non-governance pause senders
    function cancelExternalEmergencyPause(IIAssetManager[] memory _assetManagers)
        external
        onlyImmediateGovernance
    {
        _callOnManagers(_assetManagers,
            abi.encodeCall(IIAssetManager.emergencyPause, (EmergencyPause.Level.NONE, false, 0)));
    }

    function resetEmergencyPauseTotalDuration(IIAssetManager[] memory _assetManagers)
        external
        onlyImmediateGovernance
    {
        _callOnManagers(_assetManagers,
            abi.encodeCall(IIAssetManager.resetEmergencyPauseTotalDuration, ()));
    }

    function addEmergencyPauseSender(address _address)
        external
        onlyImmediateGovernance
    {
        emergencyPauseSenders.add(_address);
    }

    function removeEmergencyPauseSender(address _address)
        external
        onlyImmediateGovernance
    {
        emergencyPauseSenders.remove(_address);
    }

    function setMaxEmergencyPauseDurationSeconds(IIAssetManager[] memory _assetManagers, uint256 _value)
        external
        onlyGovernance
    {
        _setValueOnManagers(_assetManagers,
            IISettingsManagement.setMaxEmergencyPauseDurationSeconds.selector, _value);
    }

    function setEmergencyPauseDurationResetAfterSeconds(IIAssetManager[] memory _assetManagers, uint256 _value)
        external
        onlyGovernance
    {
        _setValueOnManagers(_assetManagers,
            IISettingsManagement.setEmergencyPauseDurationResetAfterSeconds.selector, _value);
    }

    function getEmergencyPauseSenders()
        external view
        returns (address[] memory)
    {
        return emergencyPauseSenders.values();
    }

    function _emergencyPause(IIAssetManager[] memory _assetManagers, EmergencyPause.Level _level, uint256 _duration)
        private
    {
        bool byGovernance = msg.sender == governance();
        require(byGovernance || emergencyPauseSenders.contains(msg.sender),
            OnlyGovernanceOrEmergencyPauseSenders());
        _callOnManagers(_assetManagers,
            abi.encodeCall(IIAssetManager.emergencyPause, (_level, byGovernance, _duration)));
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    // Helpers

    function _setValueOnManagers(IIAssetManager[] memory _assetManagers, bytes4 _selector, address _value) private {
        _callOnManagers(_assetManagers, abi.encodeWithSelector(_selector, (_value)));
    }

    function _setValueOnManagers(IIAssetManager[] memory _assetManagers, bytes4 _selector, uint256 _value) private {
        _callOnManagers(_assetManagers, abi.encodeWithSelector(_selector, (_value)));
    }

    function _callOnManagers(IIAssetManager[] memory _assetManagers, bytes memory _calldata) private {
        for (uint256 i = 0; i < _assetManagers.length; i++) {
            address assetManager = address(_assetManagers[i]);
            require(assetManagerIndex[assetManager] != 0, AssetManagerNotManaged());
            Address.functionCall(assetManager, _calldata);
        }
    }
}