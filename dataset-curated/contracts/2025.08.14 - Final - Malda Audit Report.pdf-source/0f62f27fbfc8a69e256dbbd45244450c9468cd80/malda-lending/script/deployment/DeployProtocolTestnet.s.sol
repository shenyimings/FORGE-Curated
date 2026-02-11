// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {Deployer} from "src/utils/Deployer.sol";
import {Operator} from "src/Operator/Operator.sol";
import {BatchSubmitter} from "src/mToken/BatchSubmitter.sol";
import {RewardDistributor} from "src/rewards/RewardDistributor.sol";
import {mErc20Host} from "src/mToken/host/mErc20Host.sol";
import {mTokenGateway} from "src/mToken/extension/mTokenGateway.sol";
import {Roles} from "src/Roles.sol";
import {JumpRateModelV4} from "src/interest/JumpRateModelV4.sol";
import {mTokenConfiguration} from "src/mToken/mTokenConfiguration.sol";
import {IPauser} from "src/interfaces/IPauser.sol";
import {IOwnable} from "src/interfaces/IOwnable.sol";
import {Pauser} from "src/pauser/Pauser.sol";

import {
    DeployConfig, MarketRelease, Role, InterestConfig, OracleConfigRelease, OracleFeed
} from "../deployers/Types.sol";

import {DeployBaseRelease} from "../deployers/DeployBaseRelease.sol";
import {DeployDeployer} from "../deployers/DeployDeployer.s.sol";
import {DeployRbac} from "./generic/DeployRbac.s.sol";
import {DeployZkVerifier} from "./generic/DeployZkVerifier.s.sol";
import {DeployPauser} from "./generic/DeployPauser.s.sol";
import {DeployOperator} from "./markets/DeployOperator.s.sol";
import {DeployHostMarket} from "./markets/host/DeployHostMarket.s.sol";
import {DeployExtensionMarket} from "./markets/extension/DeployExtensionMarket.s.sol";
import {DeployJumpRateModelV4} from "./interest/DeployJumpRateModelV4.s.sol";
import {DeployRewardDistributor} from "./rewards/DeployRewardDistributor.s.sol";
import {DeployBatchSubmitter} from "./generic/DeployBatchSubmitter.s.sol";
import {DeployMixedPriceOracleV3} from "./oracles/DeployMixedPriceOracleV3.s.sol";
import {DeployMockOracle} from "./oracles/DeployMockOracle.s.sol";

import {SetOperatorInRewardDistributor} from "../configuration/SetOperatorInRewardDistributor.s.sol";
import {SetRole} from "../configuration/SetRole.s.sol";
import {SetCollateralFactor} from "../configuration/SetCollateralFactor.s.sol";
import {SupportMarket} from "../configuration/SupportMarket.s.sol";
import {SetBorrowRateMaxMantissa} from "../configuration/SetBorrowRateMaxMantissa.s.sol";
import {SetBorrowCap} from "../configuration/SetBorrowCap.s.sol";
import {SetSupplyCap} from "../configuration/SetSupplyCap.s.sol";
import {UpdateAllowedChains} from "../configuration/UpdateAllowedChains.s.sol";

import {DeployRebalancer} from "script/deployment/rebalancer/DeployRebalancer.s.sol";
import {DeployAcrossBridge} from "script/deployment/rebalancer/DeployAcrossBridge.s.sol";
import {DeployConnextBridge} from "script/deployment/rebalancer/DeployConnextBridge.s.sol";
import {DeployEverclearBridge} from "script/deployment/rebalancer/DeployEverclearBridge.s.sol";
import {DeployLZBridge} from "script/deployment/rebalancer/DeployLZBridge.s.sol";

// import {VerifyDeployment} from "./VerifyDeployment.s.sol";

contract DeployProtocolTestnet is DeployBaseRelease {
    using stdJson for string;

    error UnsupportedOracleType();

    address marketAddress;
    address[] marketAddresses;
    address[] extensionMarketAddresses;
    address owner;

    // Track deployed implementations
    address public mTokenHostImplementation;
    address public mTokenGatewayImplementation;

    Deployer deployer;

    DeployDeployer deployDeployer;
    DeployRbac deployRbac;
    DeployBatchSubmitter deployBatchSubmitter;
    DeployJumpRateModelV4 deployInterest;
    DeployOperator deployOperator;
    DeployPauser deployPauser;
    DeployMixedPriceOracleV3 deployOracle;
    DeployRewardDistributor deployReward;
    DeployHostMarket deployHost;
    DeployExtensionMarket deployExt;
    SetOperatorInRewardDistributor setOperatorInRewardDistributor;
    SetRole setRole;
    SupportMarket supportMarket;
    SetCollateralFactor setCollateralFactor;
    SetBorrowRateMaxMantissa setBorrowRateMaxMantissa;
    SetBorrowCap setBorrowCap;
    SetSupplyCap setSupplyCap;
    UpdateAllowedChains updateAllowedChains;
    DeployRebalancer deployRebalancer;
    DeployAcrossBridge deployAcrossBridge;
    DeployConnextBridge deployConnextBridge;
    DeployEverclearBridge deployEverclearBridge;
    DeployLZBridge deployLZBridge;
    DeployZkVerifier deployZkVerifier;

    function setUp() public override {
        configPath = "deployment-config-testnet.json";
        super.setUp();

        feeds.push(OracleFeed("mUSDC", 0xA5c24F2449891483f0923f0D9dC7694BDFe1bC86, "USD", 6));
        feeds.push(OracleFeed("USDC", 0xA5c24F2449891483f0923f0D9dC7694BDFe1bC86, "USD", 6));
        feeds.push(OracleFeed("mWETH", 0x2D6261dce927D5c46f7f393a897887F19F3fDf2A, "USD", 18));
        feeds.push(OracleFeed("WETH", 0x2D6261dce927D5c46f7f393a897887F19F3fDf2A, "USD", 18));
        feeds.push(OracleFeed("mUSDCMock", 0xdf0bD5072572A002ad0eeBAc58c4BCECA952A826, "USD", 6));
        feeds.push(OracleFeed("USDC-M", 0xdf0bD5072572A002ad0eeBAc58c4BCECA952A826, "USD", 6));
        feeds.push(OracleFeed("mwstETHMock", 0xa371FA57A42d9c72380e2959ceDbB21aE07AD210, "USD", 18));
        feeds.push(OracleFeed("wstETH-M", 0xa371FA57A42d9c72380e2959ceDbB21aE07AD210, "USD", 18));
    }

    function run() public {
        // Deploy to all networks
        for (uint256 i = 0; i < networks.length; i++) {
            delete marketAddresses;
            delete extensionMarketAddresses;

            string memory network = networks[i];
            console.log("\n=== Deploying to %s ===", network);

            // Create fork for this network
            forks[network] = vm.createSelectFork(network);

            // deploys or fetches the existing one
            deployDeployer = new DeployDeployer();

            // deploys or fetches the existing one
            deployRbac = new DeployRbac();
            deployZkVerifier = new DeployZkVerifier();

            deployBatchSubmitter = new DeployBatchSubmitter();
            setRole = new SetRole();

            owner = configs[network].deployer.owner;
            deployer = Deployer(payable(_deployDeployer(network)));
            address rolesContract = _deployRoles(owner);
            address zkVerifier = _deployZkVerifier(owner, configs[network].zkVerifier.verifierAddress, configs[network].zkVerifier.imageId);
            _deployBatchSubmitter(rolesContract, zkVerifier);

            deployPauser = new DeployPauser();

            address pauser;
            if (configs[network].isHost) {
                deployInterest = new DeployJumpRateModelV4();
                deployOperator = new DeployOperator();
                deployOracle = new DeployMixedPriceOracleV3();
                deployReward = new DeployRewardDistributor();
                deployHost = new DeployHostMarket();
                setOperatorInRewardDistributor = new SetOperatorInRewardDistributor();
                supportMarket = new SupportMarket();
                setCollateralFactor = new SetCollateralFactor();
                setBorrowRateMaxMantissa = new SetBorrowRateMaxMantissa();
                setBorrowCap = new SetBorrowCap();
                setSupplyCap = new SetSupplyCap();
                updateAllowedChains = new UpdateAllowedChains();

                console.log("Deploying host chain");
                pauser = _deployHostChain(network, rolesContract, zkVerifier);
            } else {
                deployExt = new DeployExtensionMarket();
                console.log("Deploying extension chain");
                pauser = _deployExtensionChain(network, rolesContract, zkVerifier);
            }

            console.log("-------------------- DONE");
        }
    }

    function _deployAndConfigRebalancerAndBridges(string memory network, address rolesContract) internal {
        console.log(" --- Deploying rebalancer");
        address rebalancer = deployRebalancer.run(rolesContract, owner, deployer);
        console.log(" --- Deployed rebalancer at ", rebalancer);

        if (spokePoolAddresses[configs[network].chainId] != address(0)) {
            console.log(" --- Deploying acrossBridge");
            address acrossBridge =
                deployAcrossBridge.run(rolesContract, spokePoolAddresses[configs[network].chainId], deployer);
            console.log(" --- Deployed acrossBridge at ", acrossBridge);
        } else {
            console.log(
                "---- AcrossBridge cannot be deployed on current chain because SpokePool is address(0). Chain: ",
                configs[network].chainId
            );
        }
        console.log(" --- Deploying connextBridge");
        address connextBridge =
            deployConnextBridge.run(rolesContract, connextAddresses[configs[network].chainId], deployer);
        console.log(" --- Deployed connextBridge at ", connextBridge);
        console.log(" --- Deploying everclearBridge");
        address everclearBridge =
            deployEverclearBridge.run(rolesContract, everclearAddresses[configs[network].chainId], deployer);
        console.log(" --- Deployed everclearBridge at ", everclearBridge);
        console.log(" --- Deploying lzBridge");
        address lzBridge = deployLZBridge.run(rolesContract, deployer);
        console.log(" --- Deployed lzBridge at ", lzBridge);

        console.log(" ---- Setting REBALANCER role for the Rebalancer contract");
        setRole.run(rolesContract, address(rebalancer), keccak256(abi.encodePacked("REBALANCER")), true);

        console.log(" --- All rebalancer contracts deployed and configured for network", network);
    }

    function _deployHostChain(string memory network, address rolesContract, address _zkVerifier)
        internal
        returns (address pauser)
    {
        address rewardDistributor = _deployRewardDistributor();
        address oracle = _deployOracle(configs[network].oracle, rolesContract);
        address operator = _deployOperator(oracle, rewardDistributor, rolesContract);

        console.log("Deploying Pauser on host chain");
        pauser = _deployPauser(rolesContract, operator);
        console.log("Pauser deployed on host chain", pauser);

        _setOperatorInRewardDistributor(operator, rewardDistributor);

        // Setup roles and chain connections
        _setRoles(rolesContract, network);

        uint256 marketsLength = configs[network].markets.length;
        for (uint256 i; i < marketsLength;) {
            _deployAndConfigureMarket(true, configs[network].markets[i], operator, rolesContract, network, pauser, _zkVerifier);
            unchecked {
                ++i;
            }
        }
    }

    function _deployExtensionChain(string memory network, address rolesContract, address _zkVerifier)
        internal
        returns (address pauser)
    {
        _setRoles(rolesContract, network);

        console.log("Deploying Pauser on extension chain");
        pauser = _deployPauser(rolesContract, address(0));
        console.log("Pauser deployed on host chain", pauser);

        uint256 marketsLength = configs[network].markets.length;
        for (uint256 i; i < marketsLength;) {
            _deployAndConfigureMarket(false, configs[network].markets[i], address(0), rolesContract, network, pauser, _zkVerifier);
            unchecked {
                ++i;
            }
        }

        //
    }

    function _deployAndConfigureMarket(
        bool isHost,
        MarketRelease memory market,
        address operator,
        address rolesContract,
        string memory network,
        address pauser,
        address _zkVerifier
    ) internal {
        address interestModel;

        // Deploy interest model only for host chain
        if (isHost) {
            interestModel = _deployInterestModel(market.interestModel);
        }
        uint256 key = vm.envUint("OWNER_PRIVATE_KEY");

        // Deploy proxy for market
        if (isHost) {
            marketAddress = _deployHostMarket(
                deployer, market, operator, interestModel, _zkVerifier, rolesContract
            );

            marketAddresses.push(marketAddress);

            console.log(" -- adding HOST market to pausable contract");
            vm.startBroadcast(key);
            Pauser(pauser).addPausableMarket(marketAddress, IPauser.PausableType.Host);
            vm.stopBroadcast();
        } else {
            marketAddress =
                _deployExtensionMarket(deployer, market, _zkVerifier, rolesContract);
            marketAddresses.push(marketAddress);
            extensionMarketAddresses.push(marketAddress);

            console.log(" -- adding EXTENSION market to pausable contract");
            vm.startBroadcast(key);
            Pauser(pauser).addPausableMarket(marketAddress, IPauser.PausableType.Extension);
            vm.stopBroadcast();
        }

        // Configure market if host chain
        if (isHost) {
            console.log("Configuring market", marketAddress);
            _configureMarket(
                operator,
                marketAddress,
                market.collateralFactor,
                market.borrowCap,
                market.supplyCap,
                market.borrowRateMaxMantissa
            );
            console.log("Market configured");

            // Setup allowed chains on host market
            _updateAllowedChains(marketAddress, network);
        }
    }

    function _deployDeployer(string memory network) internal returns (address) {
        return deployDeployer.run(configs[network].chainId, owner, configs[network].deployer.salt);
    }

    function _deployRoles(address _owner) internal returns (address) {
        return deployRbac.run(deployer, _owner);
    }

    function _deployBatchSubmitter(address rolesContract, address zkVerifier) internal returns (address) {
        address created = deployBatchSubmitter.run(deployer, rolesContract, zkVerifier, owner);

        console.log(" ---- Setting PROOF_BATCH_FORWARDER role for the BatchSubmitter contract");
        setRole.run(rolesContract, address(created), keccak256(abi.encodePacked("PROOF_BATCH_FORWARDER")), true);

        return created;
    }

    function _deployRewardDistributor() internal returns (address) {
        console.log("--- owner", owner);
        return deployReward.run(deployer, owner);
    }

    function _deployOracle(OracleConfigRelease memory oracleConfig, address rolesContract) internal returns (address) {
        return deployOracle.runWithFeeds(deployer, feeds, rolesContract, oracleConfig.stalenessPeriod);
    }

    function _deployOperator(address oracle, address rewardDistributor, address rolesContract)
        internal
        returns (address)
    {
        return deployOperator.run(deployer, oracle, rewardDistributor, rolesContract, owner);
    }

    function _deployPauser(address rolesContract, address operator) internal returns (address) {
        return deployPauser.run(deployer, rolesContract, operator, owner);
    }

    function _deployInterestModel(InterestConfig memory modelConfig) internal returns (address) {
        return deployInterest.run(
            deployer,
            DeployJumpRateModelV4.InterestData({
                kink: modelConfig.kink,
                name: modelConfig.name,
                blocksPerYear: modelConfig.blocksPerYear,
                baseRatePerYear: modelConfig.baseRate,
                multiplierPerYear: modelConfig.multiplier,
                jumpMultiplierPerYear: modelConfig.jumpMultiplier
            }),
            owner
        );
    }

    function _deployHostMarket(
        Deployer _deployer,
        MarketRelease memory market,
        address operator,
        address interestModel,
        address zkVerifier,
        address rolesContract
    ) internal returns (address) {
        return deployHost.run(
            _deployer,
            DeployHostMarket.MarketData({
                underlyingToken: market.underlying,
                operator: operator,
                interestModel: interestModel,
                exchangeRateMantissa: uint256(2e16),
                name: market.name,
                symbol: market.symbol,
                decimals: market.decimals,
                owner: owner,
                zkVerifier: zkVerifier,
                roles: rolesContract
            })
        );
    }

    function _deployExtensionMarket(
        Deployer _deployer,
        MarketRelease memory market,
        address zkVerifier,
        address rolesContract
    ) internal returns (address) {
        return deployExt.run(_deployer, market.underlying, market.name, owner, zkVerifier, rolesContract);
    }

    function _configureMarket(
        address operator,
        address market,
        uint256 collateralFactor,
        uint256 borrowCap,
        uint256 supplyCap,
        uint256 borrowRateMaxMantissa
    ) internal {
        // Support market
        _supportMarket(operator, market);

        // Set collateral factor
        _setCollateralFactor(operator, market, collateralFactor);

        // Set borrow cap
        _setBorrowCap(operator, market, borrowCap);

        // Set supply cap
        _setSupplyCap(operator, market, supplyCap);

        // Set borrow rate max mantissa
        _setBorrowRateMaxMantissa(market, borrowRateMaxMantissa);

    }

    function _setRoles(address rolesContract, string memory network) internal {
        uint256 rolesLength = configs[network].roles.length;
        for (uint256 i = 0; i < rolesLength; i++) {
            Role memory role = configs[network].roles[i];
            for (uint256 j = 0; j < role.accounts.length; j++) {
                setRole.run(rolesContract, role.accounts[j], keccak256(abi.encodePacked(role.roleName)), true);
            }
        }
    }

    function _supportMarket(address operator, address market) internal {
        supportMarket.run(operator, market);
    }

    function _setCollateralFactor(address operator, address market, uint256 collateralFactor) internal {
        setCollateralFactor.run(operator, market, collateralFactor);
    }

    function _setBorrowRateMaxMantissa(address market, uint256 borrowRateMaxMantissa) internal {
        setBorrowRateMaxMantissa.run(market, borrowRateMaxMantissa);
    }

    function _setBorrowCap(address operator, address market, uint256 borrowCap) internal {
        setBorrowCap.run(operator, market, borrowCap);
    }

    function _setSupplyCap(address operator, address market, uint256 supplyCap) internal {
        setSupplyCap.run(operator, market, supplyCap);
    }

    function _updateAllowedChains(address market, string memory network) internal {
        // Allow chains in host market
        for (uint256 i = 0; i < configs[network].allowedChains.length; i++) {
            vm.startBroadcast(key);
            mErc20Host(market).updateAllowedChain(configs[network].allowedChains[i], true);
            vm.stopBroadcast();
        }
    }

    function _setOperatorInRewardDistributor(address operator, address rewardDistributor) internal {
        setOperatorInRewardDistributor.run(operator, rewardDistributor);
    }

    
    function _deployZkVerifier(address _owner, address _risc0Verifier, bytes32 _imageId) internal returns (address) {
        return deployZkVerifier.run(deployer, _owner, _risc0Verifier, _imageId);
    }
}
