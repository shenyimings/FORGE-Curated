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
import {DeployTimelockController} from "./generic/DeployTimelockController.s.sol";
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
import {SetReserveFactor} from "../configuration/SetReserveFactor.s.sol";
import {SetLiquidationBonus} from "../configuration/SetLiquidationBonus.s.sol";
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

import "forge-std/console2.sol";
contract DeployProtocolRelease is DeployBaseRelease {
    using stdJson for string;

    error UnsupportedOracleType();

    address marketAddress;
    address[] marketAddresses;
    address[] extensionMarketAddresses;
    address owner;

    // Track deployed implementations
    address public mTokenHostImplementation;
    address public mTokenGatewayImplementation;

    mapping(string=>uint256) public collateralFactors;
    mapping(string=>uint256) public reserveFactors;
    mapping(string=>uint256) public liquidationBonuses;
    mapping(string=>uint256) public borrowCaps;

    mapping(string=>MarketRelease) public fullConfigs;

    address public batchSubmitter;

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
    SetReserveFactor setReserveFactor;
    SetLiquidationBonus setLiquidationBonus;
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
    DeployTimelockController deployTimelockController;

    function setUp() public override {
        configPath = "deployment-config-release.json";
        super.setUp();

        feeds.push(OracleFeed("mUSDC", 0x874b4573B30629F696653EE101528C7426FFFb6b, "USD", 6));
        feeds.push(OracleFeed("USDC", 0x874b4573B30629F696653EE101528C7426FFFb6b, "USD", 6));
        feeds.push(OracleFeed("mWETH", 0x2284eC83978Fe21A0E667298d9110bbeaED5E9B4, "USD", 18));
        feeds.push(OracleFeed("WETH", 0x2284eC83978Fe21A0E667298d9110bbeaED5E9B4, "USD", 18));
        feeds.push(OracleFeed("mUSDT", 0x0c547EC8B69F50d023D52391b8cB82020c46b848, "USD", 6));
        feeds.push(OracleFeed("USDT", 0x0c547EC8B69F50d023D52391b8cB82020c46b848, "USD", 6));
        feeds.push(OracleFeed("mWBTC", 0xa34Aa6654A7E45fB000F130453Ba967Fd57851C1, "USD", 8));
        feeds.push(OracleFeed("WBTC", 0xa34Aa6654A7E45fB000F130453Ba967Fd57851C1, "USD", 8));
        feeds.push(OracleFeed("mwstETH", 0x043F8c576154E19E05cD53b21Baab86deC75c728, "USD", 18));
        feeds.push(OracleFeed("wstETH", 0x043F8c576154E19E05cD53b21Baab86deC75c728, "USD", 18));
        feeds.push(OracleFeed("mezETH", 0x01600fE800B9a1c3638F24c1408F2d177133074C, "USD", 18));
        feeds.push(OracleFeed("ezETH", 0x01600fE800B9a1c3638F24c1408F2d177133074C, "USD", 18));
        feeds.push(OracleFeed("mweETH", 0x6Bd45e0f0adaAE6481f2B4F3b867911BF5f8321b, "USD", 18));
        feeds.push(OracleFeed("weETH", 0x6Bd45e0f0adaAE6481f2B4F3b867911BF5f8321b, "USD", 18));
        feeds.push(OracleFeed("mwrsETH", 0xB7b25D8e8490a138c854426e7000C7E114C2DebF, "USD", 18));
        feeds.push(OracleFeed("wrsETH", 0xB7b25D8e8490a138c854426e7000C7E114C2DebF, "USD", 18));

        // borrow caps
        borrowCaps["mUSDC"] = 0;
        borrowCaps["mWETH"] = 0;
        borrowCaps["mUSDT"] = 0;
        borrowCaps["mDAI"] = 0;
        borrowCaps["mWBTC"] = 0;
        borrowCaps["mwstETH"] = 0;
        borrowCaps["mezETH"] = 0;
        borrowCaps["mweETH"] = 0;
        borrowCaps["mwrsETH"] = 0;

        // collateral factors
        collateralFactors["mUSDC"] = 900000000000000000;
        collateralFactors["mWETH"] = 830000000000000000;
        collateralFactors["mUSDT"] = 900000000000000000;
        collateralFactors["mDAI"] = 900000000000000000;
        collateralFactors["mWBTC"] = 780000000000000000;
        collateralFactors["mwstETH"] = 810000000000000000;
        collateralFactors["mezETH"] = 750000000000000000;
        collateralFactors["mweETH"] = 800000000000000000;
        collateralFactors["mwrsETH"] = 750000000000000000;

        // reserve factors
        reserveFactors["mUSDC"] =   100000000000000000;
        reserveFactors["mWETH"] =   150000000000000000;
        reserveFactors["mUSDT"] =   100000000000000000;
        reserveFactors["mDAI"] =    100000000000000000;
        reserveFactors["mWBTC"] =   500000000000000000;
        reserveFactors["mwstETH"] = 50000000000000000;
        reserveFactors["mezETH"] =  450000000000000000;
        reserveFactors["mweETH"] =  450000000000000000;
        reserveFactors["mwrsETH"] = 450000000000000000;

        // liquidation bonuses
        liquidationBonuses["mUSDC"] = 1050000000000000000;
        liquidationBonuses["mWETH"] = 1050000000000000000;
        liquidationBonuses["mUSDT"] = 1050000000000000000;
        liquidationBonuses["mDAI"] = 1050000000000000000;
        liquidationBonuses["mWBTC"] = 1050000000000000000;
        liquidationBonuses["mwstETH"] = 1060000000000000000;
        liquidationBonuses["mezETH"] = 1070000000000000000;
        liquidationBonuses["mweETH"] = 1070000000000000000;
        liquidationBonuses["mwrsETH"] = 1070000000000000000;

        // full configs
        fullConfigs["mUSDC"] = MarketRelease({
            borrowCap: borrowCaps["mUSDC"],
            borrowRateMaxMantissa: 0.0005e16,
            collateralFactor: collateralFactors["mUSDC"],
            decimals: 6,
            interestModel: InterestConfig({
                baseRate: 0,
                blocksPerYear: 31536000,
                jumpMultiplier: 11092659363,
                kink: 920000000000000000,
                multiplier: 1902587485,
                name: "mUSDC Interest Model"
            }),
            name: "mUSDC",
            supplyCap: 0,
            symbol: "mUSDC",
            underlying: 0x176211869cA2b568f2A7D4EE941E073a821EE1ff,
            reserveFactor: reserveFactors["mUSDC"],
            liquidationBonus: liquidationBonuses["mUSDC"]
        });

        fullConfigs["mWETH"] = MarketRelease({
            borrowCap: borrowCaps["mWETH"],
            borrowRateMaxMantissa: 0.0005e16,
            collateralFactor: collateralFactors["mWETH"],
            decimals: 18,
            interestModel: InterestConfig({
                baseRate: 0,
                blocksPerYear: 31536000,
                jumpMultiplier: 2537211589,
                kink: 800000000000000000,
                multiplier: 856118368,
                name: "mWETH Interest Model"
            }),
            name: "mWETH",
            supplyCap: 0,
            symbol: "mWETH",
            underlying: 0xe5D7C2a44FfDDf6b295A15c148167daaAf5Cf34f,
            reserveFactor: reserveFactors["mWETH"],
            liquidationBonus: liquidationBonuses["mWETH"]
        });

        fullConfigs["mUSDT"] = MarketRelease({
            borrowCap: borrowCaps["mUSDT"],
            borrowRateMaxMantissa: 0.0005e16,
            collateralFactor: collateralFactors["mUSDT"],
            decimals: 6,
            interestModel: InterestConfig({
                baseRate: 0,
                blocksPerYear: 31536000,
                jumpMultiplier: 11092659363,
                kink: 920000000000000000,
                multiplier: 1902587485,
                name: "mUSDT Interest Model"
            }),
            name: "mUSDT",
            supplyCap: 0,
            symbol: "mUSDT",
            underlying: 0xA219439258ca9da29E9Cc4cE5596924745e12B93,
            reserveFactor: reserveFactors["mUSDT"],
            liquidationBonus: liquidationBonuses["mUSDT"]
        });

        fullConfigs["mWBTC"] = MarketRelease({
            borrowCap: borrowCaps["mWBTC"],
            borrowRateMaxMantissa: 0.0005e16,
            collateralFactor: collateralFactors["mWBTC"],
            decimals: 8,
            interestModel: InterestConfig({
                baseRate: 0,
                blocksPerYear: 31536000,
                jumpMultiplier: 95111963546,
                kink: 800000000000000000,
                multiplier: 1268391657,
                name: "mWBTC Interest Model"
            }),
            name: "mWBTC",
            supplyCap: 0,
            symbol: "mWBTC",
            underlying: 0x3aAB2285ddcDdaD8edf438C1bAB47e1a9D05a9b4,
            reserveFactor: reserveFactors["mWBTC"],
            liquidationBonus: liquidationBonuses["mWBTC"]
        });

        fullConfigs["mwstETH"] = MarketRelease({
            borrowCap: borrowCaps["mwstETH"],
            borrowRateMaxMantissa: 0.0005e16,
            collateralFactor: collateralFactors["mwstETH"],
            decimals: 18,
            interestModel: InterestConfig({
                baseRate: 0,
                blocksPerYear: 31536000,
                jumpMultiplier: 26953011055,
                kink: 700000000000000000,
                multiplier: 507413996,
                name: "mwstETH Interest Model"
            }),
            name: "mwstETH",
            supplyCap: 0,
            symbol: "mwstETH",
            underlying: 0xB5beDd42000b71FddE22D3eE8a79Bd49A568fC8F,
            reserveFactor: reserveFactors["mwstETH"],
            liquidationBonus: liquidationBonuses["mwstETH"]
        });

        fullConfigs["mezETH"] = MarketRelease({
            borrowCap: borrowCaps["mezETH"],
            borrowRateMaxMantissa: 0.0005e16,
            collateralFactor: collateralFactors["mezETH"],
            decimals: 18,
            interestModel: InterestConfig({
                baseRate: 0,
                blocksPerYear: 31536000,
                jumpMultiplier: 251900000000,
                kink: 400000000000000000,
                multiplier: 1981000000,
                name: "mezETH Interest Model"
            }),
            name: "mezETH",
            supplyCap: 0,
            symbol: "mezETH",
            underlying: 0x2416092f143378750bb29b79eD961ab195CcEea5,
            reserveFactor: reserveFactors["mezETH"],
            liquidationBonus: liquidationBonuses["mezETH"]
        });

        fullConfigs["mweETH"] = MarketRelease({
            borrowCap: borrowCaps["mweETH"],
            borrowRateMaxMantissa: 0.0005e16,
            collateralFactor: collateralFactors["mweETH"],
            decimals: 18,
            interestModel: InterestConfig({
                baseRate: 317091247,
                blocksPerYear: 31536000,
                jumpMultiplier: 95111963546,
                kink: 400000000000000000,
                multiplier: 2219638722,
                name: "mweETH Interest Model"
            }),
            name: "mweETH",
            supplyCap: 0,
            symbol: "mweETH",
            underlying: 0x1Bf74C010E6320bab11e2e5A532b5AC15e0b8aA6,
            reserveFactor: reserveFactors["mweETH"],
            liquidationBonus: liquidationBonuses["mweETH"]
        });

        fullConfigs["mwrsETH"] = MarketRelease({
            borrowCap: borrowCaps["mwrsETH"],
            borrowRateMaxMantissa: 0.0005e16,
            collateralFactor: collateralFactors["mwrsETH"],
            decimals: 18,
            interestModel: InterestConfig({
                baseRate: 0,
                blocksPerYear: 31536000,
                jumpMultiplier: 276300000000,
                kink: 400000000000000000,
                multiplier: 1585000000,
                name: "mwrsETH Interest Model"
            }),
            name: "mwrsETH",
            supplyCap: 0,
            symbol: "mwrsETH",
            underlying: 0xD2671165570f41BBB3B0097893300b6EB6101E6C,
            reserveFactor: reserveFactors["mwrsETH"],
            liquidationBonus: liquidationBonuses["mwrsETH"]
        });


        spokePoolAddresses[1] = 0x5c7BCd6E7De5423a257D81B442095A1a6ced35C5;
        spokePoolAddresses[10] = 0x6f26Bf09B1C792e3228e5467807a900A503c0281;
        spokePoolAddresses[8453] = 0x09aea4b2242abC8bb4BB78D537A67a245A7bEC64;
        spokePoolAddresses[59144] = address(0);

        connextAddresses[1] = 0x8898B472C54c31894e3B9bb83cEA802a5d0e63C6;
        connextAddresses[10] = 0x8f7492DE823025b4CfaAB1D34c58963F2af5DEDA;
        connextAddresses[8453] = 0xB8448C6f7f7887D36DcA487370778e419e9ebE3F;
        connextAddresses[59144] = 0xa05eF29e9aC8C75c530c2795Fa6A800e188dE0a9;

        everclearAddresses[1] = 0xa05A3380889115bf313f1Db9d5f335157Be4D816;
        everclearAddresses[10] = 0xa05A3380889115bf313f1Db9d5f335157Be4D816;
        everclearAddresses[8453] = 0xa05A3380889115bf313f1Db9d5f335157Be4D816;
        everclearAddresses[59144] = 0xc24dC29774fD2c1c0c5FA31325Bb9cbC11D8b751;
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

            deployTimelockController = new DeployTimelockController();

            deployBatchSubmitter = new DeployBatchSubmitter();
            setRole = new SetRole();

            owner = configs[network].deployer.owner;
            deployer = Deployer(payable(_deployDeployer(network)));
            address rolesContract = _deployRoles(owner);
            address zkVerifier = _deployZkVerifier(owner, configs[network].zkVerifier.verifierAddress, configs[network].zkVerifier.imageId);
            
            _deployBatchSubmitter(rolesContract, zkVerifier);

            address timelock = _deployTimelock(owner);

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
                setReserveFactor = new SetReserveFactor();
                setLiquidationBonus = new SetLiquidationBonus();
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

            deployRebalancer = new DeployRebalancer();
            deployAcrossBridge = new DeployAcrossBridge();
            deployConnextBridge = new DeployConnextBridge();
            deployEverclearBridge = new DeployEverclearBridge();
            deployLZBridge = new DeployLZBridge();
            //_deployAndConfigRebalancerAndBridges(network, rolesContract);

            // Transfer ownerhip
            // console.log("Transfer ownership to", configs[network].ownership);
            // uint256 key = vm.envUint("OWNER_PRIVATE_KEY");
            // vm.startBroadcast(key);

            // console.log(" -- for ZkVerifier");
            // IOwnable(zkVerifier).transferOwnership(configs[network].ownership);
            // console.log(" -- for Pauser");
            // IOwnable(pauser).transferOwnership(configs[network].ownership);
            // console.log(" -- for Roles");
            // IOwnable(rolesContract).transferOwnership(configs[network].ownership);
            // console.log(" -- for mTokenGateway addresses [count]", extensionMarketAddresses.length);
            // for (uint256 j; j < extensionMarketAddresses.length;) {
            //     IOwnable(extensionMarketAddresses[j]).transferOwnership(configs[network].ownership);
            //     unchecked {
            //         ++j;
            //     }
            // }
            //vm.stopBroadcast();
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
            market = fullConfigs[market.name];
            interestModel = _deployInterestModel(market.interestModel);
        }
        uint256 key = vm.envUint("OWNER_PRIVATE_KEY");

        // Deploy proxy for market
        if (isHost) {
            market.collateralFactor = collateralFactors[market.name];
            market.reserveFactor = reserveFactors[market.name];
            market.liquidationBonus = liquidationBonuses[market.name];
            market.borrowCap = borrowCaps[market.name];
            console.log(" - market params: ");
            console.log(" --- name");
            console.logString(market.name);
            console.log(" --- collateralFactor %s", market.collateralFactor);
            console.log(" --- reserveFactor %s", market.reserveFactor);
            console.log(" --- liquidationBonus %s", market.liquidationBonus);
            console.log(" --- borrowCap %s", market.borrowCap);
            console.log(" --- _zkVerifier %s", _zkVerifier);
            console.log(" --- rolesContract %s", rolesContract);
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
                market.reserveFactor,
                market.liquidationBonus,
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
        uint256 reserveFactor,
        uint256 liquidationBonus,
        uint256 borrowCap,
        uint256 supplyCap,
        uint256 borrowRateMaxMantissa
    ) internal {
        // Support market
        _supportMarket(operator, market);

        // Set collateral factor
        _setCollateralFactor(operator, market, collateralFactor);
        
        // Set reserve factor
        //_setReserveFactor(market, reserveFactor);

        // Set liquidation incentives
        _setLiquidationIncentive(operator, market, liquidationBonus);

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

    function _setReserveFactor(address market, uint256 reserveFactor) internal {
        setReserveFactor.run(market, reserveFactor);
    }

    function _setLiquidationIncentive(address operator, address market, uint256 liquidationBonus) internal {
        setLiquidationBonus.run(operator, market, liquidationBonus);
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

    function _deployTimelock(address _owner) internal returns (address) {
        return deployTimelockController.run(deployer, _owner);
    }
}
