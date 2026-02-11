// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Utils
import {Base} from "lib/euler-vault-kit/src/EVault/shared/Base.sol";
import {DeployPermit2} from "./utils/DeployPermit2.sol";
import "src/libraries/PendingLib.sol";

// Contracts
import {GenericFactory} from "lib/euler-vault-kit/src/GenericFactory/GenericFactory.sol";
import {EthereumVaultConnector} from "lib/ethereum-vault-connector/src/EthereumVaultConnector.sol";
import {ProtocolConfig} from "lib/euler-vault-kit/src/ProtocolConfig/ProtocolConfig.sol";
import {SequenceRegistry} from "lib/euler-vault-kit/src/SequenceRegistry/SequenceRegistry.sol";
import {Initialize} from "lib/euler-vault-kit/src/EVault/modules/Initialize.sol";
import {Token} from "lib/euler-vault-kit/src/EVault/modules/Token.sol";
import {Vault} from "lib/euler-vault-kit/src/EVault/modules/Vault.sol";
import {Borrowing} from "lib/euler-vault-kit/src/EVault/modules/Borrowing.sol";
import {Liquidation} from "lib/euler-vault-kit/src/EVault/modules/Liquidation.sol";
import {RiskManager} from "lib/euler-vault-kit/src/EVault/modules/RiskManager.sol";
import {BalanceForwarder} from "lib/euler-vault-kit/src/EVault/modules/BalanceForwarder.sol";
import {Governance} from "lib/euler-vault-kit/src/EVault/modules/Governance.sol";
import {EVault} from "lib/euler-vault-kit/src/EVault/EVault.sol";
import {IRMTestDefault} from "lib/euler-vault-kit/test/mocks/IRMTestDefault.sol";
import {EulerEarnFactory} from "src/EulerEarnFactory.sol";
import {PublicAllocator} from "src/PublicAllocator.sol";

// Interfaces
import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {IEVault} from "lib/euler-vault-kit/src/EVault/IEVault.sol";
import {IEulerEarn} from "src/interfaces/IEulerEarn.sol";
import {IPublicAllocator} from "src/interfaces/IPublicAllocator.sol";

// Test Contracts
import {TestERC20} from "./utils/mocks/TestERC20.sol";
import {BaseTest} from "./base/BaseTest.t.sol";
import {Actor} from "./utils/Actor.sol";
import {MockBalanceTracker} from "lib/euler-vault-kit/test/mocks/MockBalanceTracker.sol";
import {MockPriceOracle} from "lib/euler-vault-kit/test/mocks/MockPriceOracle.sol";
import {PerspectiveMock} from "test/mocks/PerspectiveMock.sol";

/// @notice Setup contract for the invariant test Suite, inherited by Tester
contract Setup is BaseTest {
    function _setUp() internal {
        // Deploy the suite assets
        _deployAssets();

        // Deploy Euler Contracts
        _deployEulerContracts();

        // Deploy core contracts of the protocol: markets
        _deployProtocolCore();

        // Deploy actors
        _setUpActors();
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                          ASSETS                                           //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function _deployAssets() internal {
        collateralToken = new TestERC20("Collateral Token", "CT", 18);
        baseAssets.push(address(collateralToken));
        allAssets.push(address(collateralToken));
        vm.label(address(collateralToken), "Collateral Token");

        loanToken = new TestERC20("Loan Token", "LT", 18);
        baseAssets.push(address(loanToken));
        allAssets.push(address(loanToken));
        vm.label(address(loanToken), "Loan Token");
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                       EULER CONTRACTS                                     //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice Deploy Euler Contracts
    function _deployEulerContracts() internal {
        // Deploy factory
        factory = new GenericFactory(OWNER);
        vm.label(address(factory), "Factory");

        // Deploy Ethereum Vault Connector
        evc = new EthereumVaultConnector();
        vm.label(address(evc), "EVC");
        protocolConfig = new ProtocolConfig(OWNER, FEE_RECIPIENT);
        balanceTracker = new MockBalanceTracker();
        oracle = new MockPriceOracle();
        vm.label(address(oracle), "Oracle");
        unitOfAccount = address(1);
        permit2 = DeployPermit2.deployPermit2();
        vm.label(address(permit2), "Permit2");
        sequenceRegistry = address(new SequenceRegistry());

        // Deploy Integrations & Modules
        integrations =
            Base.Integrations(address(evc), address(protocolConfig), sequenceRegistry, address(balanceTracker), permit2);

        modules.initialize = address(new Initialize(integrations));
        modules.token = address(new Token(integrations));
        modules.vault = address(new Vault(integrations));
        modules.borrowing = address(new Borrowing(integrations));
        modules.liquidation = address(new Liquidation(integrations));
        modules.riskManager = address(new RiskManager(integrations));
        modules.balanceForwarder = address(new BalanceForwarder(integrations));
        modules.governance = address(new Governance(integrations));

        address evaultImpl = address(new EVault(integrations, modules));
        factory.setImplementation(evaultImpl);
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                       CORE CONTRACTS                                     //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice Deploy protocol core contracts
    function _deployProtocolCore() internal {
        perspective = new PerspectiveMock();

        // DEPLOY MARKETS
        // Idle Vault
        idleVault = IERC4626(
            factory.createProxy(address(0), true, abi.encodePacked(address(loanToken), address(oracle), unitOfAccount))
        );
        IEVault(address(idleVault)).setHookConfig(address(0), 0);
        perspective.perspectiveVerify(address(idleVault));
        vm.label(address(idleVault), "IdleVault");

        // Idle Vault 2
        idleVault2 = IERC4626(
            factory.createProxy(address(0), true, abi.encodePacked(address(loanToken), address(oracle), unitOfAccount))
        );
        IEVault(address(idleVault2)).setHookConfig(address(0), 0);
        perspective.perspectiveVerify(address(idleVault2));
        vm.label(address(idleVault2), "IdleVault2");

        // Collateral Vault eTST
        eTST = IEVault(
            factory.createProxy(
                address(0), true, abi.encodePacked(address(collateralToken), address(oracle), unitOfAccount)
            )
        );
        vm.label(address(eTST), "eTST (Collateral Vault)");
        eTST.setHookConfig(address(0), 0);
        allVaults.push(IERC4626(address(eTST)));
        eVaults.push(IEVault(address(eTST)));
        allAssets.push(address(eTST));

        // Loan Vault eTST2
        eTST2 = IEVault(
            factory.createProxy(address(0), true, abi.encodePacked(address(loanToken), address(oracle), unitOfAccount))
        );
        vm.label(address(eTST2), "eTST2 (Loan Vault)");
        eTST2.setHookConfig(address(0), 0);
        eTST2.setInterestRateModel(address(new IRMTestDefault()));
        eTST2.setMaxLiquidationDiscount(0.2e4);
        eTST2.setLTV(address(eTST), 0.8e4, 0.8e4, 0);
        perspective.perspectiveVerify(address(eTST2));

        // Loan Vault eTST3
        eTST3 = IEVault(
            factory.createProxy(address(0), true, abi.encodePacked(address(loanToken), address(oracle), unitOfAccount))
        );
        vm.label(address(eTST3), "eTST3 (Loan Vault)");
        eTST3.setHookConfig(address(0), 0);
        eTST3.setInterestRateModel(address(new IRMTestDefault()));
        eTST3.setMaxLiquidationDiscount(0.2e4);
        eTST3.setLTV(address(eTST), 0.85e4, 0.85e4, 0);
        perspective.perspectiveVerify(address(eTST3));

        // Loan Vault eTST4
        eTST4 = IEVault(
            factory.createProxy(address(0), true, abi.encodePacked(address(loanToken), address(oracle), unitOfAccount))
        );
        vm.label(address(eTST4), "eTST4 (Loan Vault)");
        eTST4.setHookConfig(address(0), 0);
        eTST4.setInterestRateModel(address(new IRMTestDefault()));
        eTST4.setMaxLiquidationDiscount(0.2e4);
        eTST4.setLTV(address(eTST), 0.85e4, 0.85e4, 0);
        perspective.perspectiveVerify(address(eTST4));

        // DEPLOY EULER EARN CONTRACTS
        eulerEarnFactory = new EulerEarnFactory(OWNER, address(evc), permit2, address(perspective));

        // Deploy Euler Earn
        eulerEarn = eulerEarnFactory.createEulerEarn(
            OWNER, TIMELOCK, address(loanToken), "EulerEarn Vault", "EEV", bytes32(uint256(1))
        );
        vm.label(address(eulerEarn), "EulerEarn Vault");
        eulerEarn.setCurator(OWNER);
        eulerEarn.setIsAllocator(OWNER, true);
        eulerEarn.setFeeRecipient(FEE_RECIPIENT);
        allAssets.push(address(eulerEarn));
        allVaults.push(IERC4626(address(eulerEarn)));
        eulerEarnVaults.push(address(eulerEarn));

        // Deploy Nested Euler Earn
        eulerEarn2 = eulerEarnFactory.createEulerEarn(
            OWNER, TIMELOCK, address(loanToken), "EulerEarn2 Vault", "EEV2", bytes32(uint256(1))
        );
        vm.label(address(eulerEarn2), "EulerEarn2 Vault");
        eulerEarn2.setCurator(OWNER);
        eulerEarn2.setIsAllocator(OWNER, true);
        eulerEarn2.setFeeRecipient(FEE_RECIPIENT);
        allAssets.push(address(eulerEarn2));
        allVaults.push(IERC4626(address(eulerEarn2)));
        eulerEarnVaults.push(address(eulerEarn2));

        // STORE MARKETS & VAULTS IN STORAGE

        ///@dev: eulerEarn market
        _pushEVault(address(eulerEarn), address(eTST2), true);
        ///@dev: eulerEarn market
        _pushEVault(address(eulerEarn), address(eTST3), true);
        ///@dev: eulerEarn market
        allMarkets[address(eulerEarn)].push(IERC4626(address(eulerEarn2)));
        ///@dev: eulerEarn2 market
        _pushEVault(address(eulerEarn2), address(eTST4), true);

        // Set Infinite Cap for Idle Vault
        _setCap(eulerEarn, address(idleVault), type(uint136).max);
        _setCap(eulerEarn2, address(idleVault2), type(uint136).max);

        // Idle Vault must be pushed last
        _pushEVault(address(eulerEarn), address(idleVault), false);
        _pushEVault(address(eulerEarn2), address(idleVault2), false);

        publicAllocator = IPublicAllocator(address(new PublicAllocator(address(evc))));
        eulerEarn.setIsAllocator(address(publicAllocator), true);

        // Set initial caps for the supply markets of eulerEarn
        _setCap(eulerEarn, address(eTST2), CAP2);
        _setCap(eulerEarn, address(eTST3), CAP3);
        _setCap(eulerEarn, address(eulerEarn2), CAP1);

        // Set initial caps for the supply markets of eulerEarn2
        _setCap(eulerEarn2, address(eTST4), CAP2);

        _sortSupplyQueueIdleLast(eulerEarn, idleVault);
        _sortSupplyQueueIdleLast(eulerEarn2, idleVault2);

        // Set initial price of collateral token to 0.5 ether & loan token to 1 ether
        MockPriceOracle(address(oracle)).setPrice(address(collateralToken), address(unitOfAccount), 0.5 ether);
        MockPriceOracle(address(oracle)).setPrice(address(loanToken), address(unitOfAccount), 1 ether);
    }

    function _pushEVault(address _eulerEarn, address _eVault, bool _isLoanVault) internal {
        allMarkets[_eulerEarn].push(IERC4626(_eVault));
        allVaults.push(IERC4626(_eVault));
        eVaults.push(IEVault(_eVault));
        if (_isLoanVault) {
            loanVaults.push(IEVault(_eVault));
        }
        allAssets.push(address(_eVault));
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                           ACTORS                                          //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice Deploy protocol actors and initialize their balances
    function _setUpActors() internal {
        // Initialize the three actors of the fuzzers
        address[] memory addresses = new address[](3);
        addresses[0] = USER1;
        addresses[1] = USER2;
        addresses[2] = USER3;

        // Initialize the tokens array
        address[] memory tokens = new address[](2);
        tokens[0] = address(loanToken);
        tokens[1] = address(collateralToken);

        address[] memory contracts_ = new address[](8);
        contracts_[0] = address(idleVault);
        contracts_[1] = address(idleVault2);
        contracts_[2] = address(eTST);
        contracts_[3] = address(eTST2);
        contracts_[4] = address(eTST3);
        contracts_[5] = address(eTST4);
        contracts_[4] = address(eulerEarn);
        contracts_[5] = address(eulerEarn2);

        for (uint256 i; i < NUMBER_OF_ACTORS; i++) {
            // Deploy actor proxies and approve system contracts_
            address _actor = _setUpActor(addresses[i], tokens, contracts_);

            // Mint initial balances to actors
            for (uint256 j = 0; j < tokens.length; j++) {
                TestERC20 _token = TestERC20(tokens[j]);
                _token.mint(_actor, INITIAL_BALANCE);
            }
            actorAddresses.push(_actor);

            vm.prank(_actor);
            evc.enableCollateral(_actor, address(eTST));
        }
    }

    /// @notice Deploy an actor proxy contract for a user address
    /// @param userAddress Address of the user
    /// @param tokens Array of token addresses
    /// @param contracts_ Array of contract addresses to aprove tokens to
    /// @return actorAddress Address of the deployed actor
    function _setUpActor(address userAddress, address[] memory tokens, address[] memory contracts_)
        internal
        returns (address actorAddress)
    {
        bool success;
        Actor _actor = new Actor(tokens, contracts_);
        actors[userAddress] = _actor;
        (success,) = address(_actor).call{value: INITIAL_ETH_BALANCE}("");
        assert(success);
        actorAddress = address(_actor);

        // Enable collateral for the actor
        vm.prank(address(_actor));
        evc.enableCollateral(address(_actor), address(eTST));
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                          HELPERS                                          //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function _setCap(IEulerEarn _vault, address _id, uint256 newCap) internal {
        IERC4626 id = IERC4626(_id);
        uint256 cap = _vault.config(id).cap;
        bool isEnabled = _vault.config(id).enabled;
        if (newCap == cap) return;

        PendingUint136 memory pendingCap = _vault.pendingCap(id);
        if (pendingCap.validAt == 0 || newCap != pendingCap.value) {
            _vault.submitCap(id, newCap);
        }

        if (newCap < cap) return;

        vm.warp(block.timestamp + _vault.timelock());

        _vault.acceptCap(id);

        assertEq(_vault.config(id).cap, newCap, "_setCap");

        if (newCap > 0) {
            if (!isEnabled) {
                IERC4626[] memory newSupplyQueue = new IERC4626[](_vault.supplyQueueLength() + 1);
                for (uint256 k; k < _vault.supplyQueueLength(); k++) {
                    newSupplyQueue[k] = _vault.supplyQueue(k);
                }
                newSupplyQueue[_vault.supplyQueueLength()] = id;
                _vault.setSupplyQueue(newSupplyQueue);
            }
        }
    }

    function _sortSupplyQueueIdleLast(IEulerEarn _vault, IERC4626 _idleVault) internal {
        IERC4626[] memory supplyQueue = new IERC4626[](_vault.supplyQueueLength());

        uint256 supplyIndex;
        for (uint256 i; i < supplyQueue.length; ++i) {
            IERC4626 id = _vault.supplyQueue(i);
            if (id == _idleVault) continue;

            supplyQueue[supplyIndex] = id;
            ++supplyIndex;
        }

        supplyQueue[supplyIndex] = _idleVault;
        ++supplyIndex;

        assembly {
            mstore(supplyQueue, supplyIndex)
        }

        _vault.setSupplyQueue(supplyQueue);
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                          LOGGING                                          //
    ///////////////////////////////////////////////////////////////////////////////////////////////
}
