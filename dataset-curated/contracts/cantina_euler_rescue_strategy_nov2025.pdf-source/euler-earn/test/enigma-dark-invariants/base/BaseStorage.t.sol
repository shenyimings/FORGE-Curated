// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Libraries
import {Base} from "lib/euler-vault-kit/src/EVault/shared/Base.sol";
import {Dispatch} from "lib/euler-vault-kit/src/EVault/Dispatch.sol";

// Contracts
import {EthereumVaultConnector} from "lib/ethereum-vault-connector/src/EthereumVaultConnector.sol";
import {ProtocolConfig} from "lib/euler-vault-kit/src/ProtocolConfig/ProtocolConfig.sol";
import {MockBalanceTracker} from "lib/euler-vault-kit/test/mocks/MockBalanceTracker.sol";
import {PerspectiveMock} from "test/mocks/PerspectiveMock.sol";
import {GenericFactory} from "lib/euler-vault-kit/src/GenericFactory/GenericFactory.sol";

// Interfaces
import {IERC4626, IERC20} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {IEulerEarn} from "src/interfaces/IEulerEarn.sol";
import {IEulerEarnFactory} from "src/interfaces/IEulerEarnFactory.sol";
import {IEVault} from "lib/euler-vault-kit/src/EVault/IEVault.sol";
import {IPublicAllocator} from "src/interfaces/IPublicAllocator.sol";

// Mock Contracts
import {TestERC20} from "../utils/mocks/TestERC20.sol";
import {MockPriceOracle} from "lib/euler-vault-kit/test/mocks/MockPriceOracle.sol";

// Utils
import {Actor} from "../utils/Actor.sol";

/// @notice BaseStorage contract for all test contracts, works in tandem with BaseTest
abstract contract BaseStorage {
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                       CONSTANTS                                           //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    uint256 constant MAX_TOKEN_AMOUNT = 1e29;

    uint256 constant ONE_DAY = 1 days;
    uint256 constant ONE_MONTH = ONE_YEAR / 12;
    uint256 constant ONE_YEAR = 365 days;

    uint256 internal constant NUMBER_OF_ACTORS = 3;
    uint256 internal constant INITIAL_ETH_BALANCE = 1e26;
    uint256 internal constant INITIAL_COLL_BALANCE = 1e21;

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                          ACTORS                                           //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice Stores the actor during a handler call
    Actor internal actor;

    /// @notice Mapping of fuzzer user addresses to actors
    mapping(address => Actor) internal actors;

    /// @notice Array of all actor addresses
    address[] internal actorAddresses;

    /// @notice The address that is targeted when executing an action
    address internal targetActor;

    /// @notice The address that is targeted when executing an action
    address internal target;

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                     RELEVANT ADDRESSES                                    //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    address internal OWNER = address(this);

    address payable internal FEE_RECIPIENT = payable(address(this));

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                       SUITE STORAGE                                       //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice Vault Hierarchy:
    ///
    ///                                      ┌─────────────────┐
    ///                                      │   eulerEarn     │  ← Main Euler Earn vault
    ///                                      │  (Top Level)    │
    ///                                      └─────────────────┘
    ///                                              │
    ///                                              ▼
    ///           ┌───────────────────────────────────┬─────────────────┬─────────────────┐
    ///           │                                   │                 │                 │
    ///           │                                   │                 │                 │
    ///           ▼                                   ▼                 ▼                 ▼
    ///    ┌─────────────┐                   ┌──────────────    ┌──────────────┐   ┌─────────────┐
    ///    │ eulerEarn2  │                   │    eTST2     │   │    eTST3     │   │  idleVault  │
    ///    │  (Nested)   │                   │ (Loan Vault) │   │ (Loan Vault) │   │   (Idle)    │
    ///    └─────────────┘                   └──────────────┘   └──────────────┘   └─────────────┘
    ///           │ ──────────┐                │                  │
    ///           │           │                │                  │
    ///           ▼           ▼                │                  │
    ///    ┌─────────────┐  ┌─────────────┐    │                  │
    ///    │   eTST4     │  │  idleVault2 │    │                  │
    ///    │ (Loan Vault)│  │   (Idle)    │    │                  │
    ///    └─────────────┘  └─────────────┘    │                  │
    ///           │                            │                  │
    ///           │                            │                  │
    ///           └────────────┐               │         ┌────────┘
    ///                        ▼               ▼         ▼
    ///                   ┌─────────────────────────────────┐
    ///                   │           eTST                  │  ← Collateral vault
    ///                   │    (Collateral Vault)           │     (acts as collateral vault for eTST2, eTST3 and eTST4)
    ///                   └─────────────────────────────────┘
    ///
    ///

    /// EULER EARN VAULTS

    /// @notice Euler Earn vault top level contract
    IEulerEarn internal eulerEarn;
    /// @notice Nested Euler Earn vault contract
    IEulerEarn internal eulerEarn2;
    /// @notice Euler Earn vault factory
    IEulerEarnFactory internal eulerEarnFactory;

    /// @notice Public allocator
    IPublicAllocator internal publicAllocator;

    // TEST ASSETS

    /// @notice Collateral token, only used for collateral vault eTST
    TestERC20 internal collateralToken;
    /// @notice Loan token, only used for loan vault eTST
    TestERC20 internal loanToken;

    // MARKETS

    /// @notice Idle vault: eulerEarn
    IERC4626 internal idleVault;
    /// @notice Idle vault: eulerEarn2
    IERC4626 internal idleVault2;

    /// @notice Collateral vault
    IEVault eTST;
    /// @notice Loan vault: eulerEarn
    IEVault eTST2;
    /// @notice Loan vault: eulerEarn
    IEVault eTST3;
    /// @notice Loan vault: eulerEarn2
    IEVault eTST4;

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                       EULER CONTRACTS                                     //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice Euler Earn factory
    EthereumVaultConnector internal evc;

    /// @notice Protocol config
    ProtocolConfig protocolConfig;

    /// @notice Balance tracker
    MockBalanceTracker balanceTracker;

    /// @notice Perspective contract
    PerspectiveMock internal perspective;

    /// @notice Oracle contract
    MockPriceOracle internal oracle;

    /// @notice Unit of account
    address unitOfAccount;

    /// @notice Permit2 contract
    address permit2;

    /// @notice Sequence registry
    address sequenceRegistry;

    /// @notice Euler Earn factory
    GenericFactory public factory;

    /// @notice Integrations
    Base.Integrations integrations;

    /// @notice Deployed modules
    Dispatch.DeployedModules modules;

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                       EXTRA VARIABLES                                     //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    // VAULTS

    /// @notice Array of all vaults on the suite; EVaults & EulerEarn
    IERC4626[] internal allVaults;

    /// @notice Array of supply markets by Euler Earn vault
    mapping(address => IERC4626[]) internal allMarkets;

    /// @notice Array of all EVaults on the suite: eTST, eTST2, eTST3, eTST4, idleVault, idleVault2
    IEVault[] internal eVaults;

    /// @notice Array of all borrowable loan EVaults on the suite: eTST2, eTST3, eTST4
    IEVault[] internal loanVaults;

    /// @notice Array of all Euler Earn vaults on the suite: eulerEarn, eulerEarn2
    address[] internal eulerEarnVaults;

    /// @notice Target market
    address targetMarket;

    // SUITE ASSETS

    /// @notice Loan and collateral assets
    address[] baseAssets;

    /// @notice All ERC20 assets on the suite including vaults share tokens and loan and collateral assets
    address[] allAssets;

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                          STRUCTS                                          //
    ///////////////////////////////////////////////////////////////////////////////////////////////
}
