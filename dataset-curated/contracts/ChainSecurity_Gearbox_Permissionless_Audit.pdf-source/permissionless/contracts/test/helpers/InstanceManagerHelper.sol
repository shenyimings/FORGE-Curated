// SPDX-License-Identifier: BUSL-1.1
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2024.
pragma solidity ^0.8.23;

import {BCRHelpers} from "./BCRHelpers.sol";
import {CCGHelper} from "./CCGHelper.sol";
import {AddressProvider} from "../../../contracts/instance/AddressProvider.sol";
import {InstanceManager} from "../../../contracts/instance/InstanceManager.sol";
import {BytecodeRepository} from "../../../contracts/global/BytecodeRepository.sol";
import {
    AP_INSTANCE_MANAGER,
    AP_BYTECODE_REPOSITORY,
    AP_PRICE_FEED_STORE,
    NO_VERSION_CONTROL
} from "../../../contracts/libraries/ContractLiterals.sol";
import {CrossChainCall} from "../../../contracts/interfaces/ICrossChainMultisig.sol";
import {IBytecodeRepository} from "../../../contracts/interfaces/IBytecodeRepository.sol";
import {IPriceFeedStore} from "../../../contracts/interfaces/IPriceFeedStore.sol";
import {IAddressProvider} from "../../../contracts/interfaces/IAddressProvider.sol";

contract InstanceManagerHelper is BCRHelpers, CCGHelper {
    // Core contracts
    address internal instanceOwner;
    InstanceManager internal instanceManager;

    constructor() {
        instanceOwner = vm.rememberKey(_generatePrivateKey("INSTANCE_OWNER"));
    }

    function _setUpInstanceManager() internal {
        _setUpCCG();
        _setUpBCR();

        // Generate random private keys and derive addresses

        // Deploy InstanceManager owned by multisig
        instanceManager = new InstanceManager(address(multisig));
        bytecodeRepository = instanceManager.bytecodeRepository();
    }

    function _generateAddAuditorCall(address _auditor, string memory _name)
        internal
        view
        returns (CrossChainCall memory)
    {
        return _buildCrossChainCallDAO(
            bytecodeRepository, abi.encodeCall(IBytecodeRepository.addAuditor, (_auditor, _name))
        );
    }

    function _generateAllowSystemContractCall(bytes32 _bytecodeHash) internal view returns (CrossChainCall memory) {
        return _buildCrossChainCallDAO(
            bytecodeRepository, abi.encodeCall(IBytecodeRepository.allowSystemContract, (_bytecodeHash))
        );
    }

    function _generateDeploySystemContractCall(bytes32 _contractName, uint256 _version, bool _saveVersion)
        internal
        view
        returns (CrossChainCall memory)
    {
        return CrossChainCall({
            chainId: 0,
            target: address(instanceManager),
            callData: abi.encodeCall(InstanceManager.deploySystemContract, (_contractName, _version, _saveVersion))
        });
    }

    function _generateActivateCall(
        uint256 _chainId,
        address _instanceOwner,
        address _treasury,
        address _weth,
        address _gear
    ) internal view returns (CrossChainCall memory) {
        return CrossChainCall({
            chainId: _chainId,
            target: address(instanceManager),
            callData: abi.encodeCall(InstanceManager.activate, (_instanceOwner, _treasury, _weth, _gear))
        });
    }

    function _buildCrossChainCallDAO(address _target, bytes memory _callData)
        internal
        view
        returns (CrossChainCall memory)
    {
        return CrossChainCall({
            chainId: 0,
            target: address(instanceManager),
            callData: abi.encodeCall(InstanceManager.configureGlobal, (_target, _callData))
        });
    }

    function _allowPriceFeed(address token, address _priceFeed) internal {
        address ap = instanceManager.addressProvider();
        address priceFeedStore = IAddressProvider(ap).getAddressOrRevert(AP_PRICE_FEED_STORE, NO_VERSION_CONTROL);
        _startPrankOrBroadcast(instanceOwner);
        instanceManager.configureLocal(
            priceFeedStore, abi.encodeCall(IPriceFeedStore.allowPriceFeed, (token, _priceFeed))
        );
        _stopPrankOrBroadcast();
    }

    function _addPriceFeed(address _priceFeed, uint32 _stalenessPeriod) internal {
        address ap = instanceManager.addressProvider();
        address priceFeedStore = IAddressProvider(ap).getAddressOrRevert(AP_PRICE_FEED_STORE, NO_VERSION_CONTROL);
        _startPrankOrBroadcast(instanceOwner);
        instanceManager.configureLocal(
            priceFeedStore, abi.encodeCall(IPriceFeedStore.addPriceFeed, (_priceFeed, _stalenessPeriod))
        );
        _stopPrankOrBroadcast();
    }
}
