// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ILidoLocator} from "src/interfaces/core/ILidoLocator.sol";

contract MockLidoLocator is ILidoLocator {
    address internal _accountingOracle;
    address internal _depositSecurityModule;
    address internal _elRewardsVault;
    address internal _lido;
    address internal _oracleReportSanityChecker;
    address internal _burner;
    address internal _stakingRouter;
    address internal _treasury;
    address internal _validatorsExitBusOracle;
    address internal _withdrawalQueue;
    address internal _withdrawalVault;
    address internal _postTokenRebaseReceiver;
    address internal _oracleDaemonConfig;
    address internal _accounting;
    address internal _predepositGuarantee;
    address internal _wstETH;
    address internal _vaultHub;
    address internal _vaultFactory;
    address internal _lazyOracle;
    address internal _operatorGrid;

    constructor(address lido_, address wsteth_, address lazyOracle_, address vaultHub_, address vaultFactory_) {
        _lido = lido_;
        _wstETH = wsteth_;
        _lazyOracle = lazyOracle_;
        _vaultHub = vaultHub_;
        _vaultFactory = vaultFactory_;
    }

    // ==================== Single address getters ====================

    function accountingOracle() external view override returns (address) {
        return _accountingOracle;
    }

    function depositSecurityModule() external view override returns (address) {
        return _depositSecurityModule;
    }

    function elRewardsVault() external view override returns (address) {
        return _elRewardsVault;
    }

    function lido() external view override returns (address) {
        return _lido;
    }

    function oracleReportSanityChecker() external view override returns (address) {
        return _oracleReportSanityChecker;
    }

    function burner() external view override returns (address) {
        return _burner;
    }

    function stakingRouter() external view override returns (address) {
        return _stakingRouter;
    }

    function treasury() external view override returns (address) {
        return _treasury;
    }

    function validatorsExitBusOracle() external view override returns (address) {
        return _validatorsExitBusOracle;
    }

    function withdrawalQueue() external view override returns (address) {
        return _withdrawalQueue;
    }

    function withdrawalVault() external view override returns (address) {
        return _withdrawalVault;
    }

    function postTokenRebaseReceiver() external view override returns (address) {
        return _postTokenRebaseReceiver;
    }

    function oracleDaemonConfig() external view override returns (address) {
        return _oracleDaemonConfig;
    }

    function accounting() external view override returns (address) {
        return _accounting;
    }

    function predepositGuarantee() external view override returns (address) {
        return _predepositGuarantee;
    }

    function wstETH() external view override returns (address) {
        return _wstETH;
    }

    function vaultHub() external view override returns (address) {
        return _vaultHub;
    }

    function vaultFactory() external view override returns (address) {
        return _vaultFactory;
    }

    function lazyOracle() external view override returns (address) {
        return _lazyOracle;
    }

    function operatorGrid() external view override returns (address) {
        return _operatorGrid;
    }

    // ==================== Batched getters ====================

    function coreComponents()
        external
        view
        override
        returns (
            address elRewardsVault_,
            address oracleReportSanityChecker_,
            address stakingRouter_,
            address treasury_,
            address withdrawalQueue_,
            address withdrawalVault_
        )
    {
        elRewardsVault_ = _elRewardsVault;
        oracleReportSanityChecker_ = _oracleReportSanityChecker;
        stakingRouter_ = _stakingRouter;
        treasury_ = _treasury;
        withdrawalQueue_ = _withdrawalQueue;
        withdrawalVault_ = _withdrawalVault;
    }

    function oracleReportComponents()
        external
        view
        override
        returns (
            address accountingOracle_,
            address oracleReportSanityChecker_,
            address burner_,
            address withdrawalQueue_,
            address postTokenRebaseReceiver_,
            address stakingRouter_,
            address vaultHub_
        )
    {
        accountingOracle_ = _accountingOracle;
        oracleReportSanityChecker_ = _oracleReportSanityChecker;
        burner_ = _burner;
        withdrawalQueue_ = _withdrawalQueue;
        postTokenRebaseReceiver_ = _postTokenRebaseReceiver;
        stakingRouter_ = _stakingRouter;
        vaultHub_ = _vaultHub;
    }

    // ==================== Test helpers ====================

    function setAccountingOracle(address value) external {
        _accountingOracle = value;
    }

    function setDepositSecurityModule(address value) external {
        _depositSecurityModule = value;
    }

    function setElRewardsVault(address value) external {
        _elRewardsVault = value;
    }

    function setOracleReportSanityChecker(address value) external {
        _oracleReportSanityChecker = value;
    }

    function setBurner(address value) external {
        _burner = value;
    }

    function setStakingRouter(address value) external {
        _stakingRouter = value;
    }

    function setTreasury(address value) external {
        _treasury = value;
    }

    function setValidatorsExitBusOracle(address value) external {
        _validatorsExitBusOracle = value;
    }

    function setWithdrawalQueue(address value) external {
        _withdrawalQueue = value;
    }

    function setWithdrawalVault(address value) external {
        _withdrawalVault = value;
    }

    function setPostTokenRebaseReceiver(address value) external {
        _postTokenRebaseReceiver = value;
    }

    function setOracleDaemonConfig(address value) external {
        _oracleDaemonConfig = value;
    }

    function setAccounting(address value) external {
        _accounting = value;
    }

    function setPredepositGuarantee(address value) external {
        _predepositGuarantee = value;
    }

    function setOperatorGrid(address value) external {
        _operatorGrid = value;
    }
}

