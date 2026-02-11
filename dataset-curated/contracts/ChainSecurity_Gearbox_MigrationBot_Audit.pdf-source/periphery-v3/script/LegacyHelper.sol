// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {console} from "forge-std/console.sol";

import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {LibString} from "@solady/utils/LibString.sol";

import {IContractsRegister} from "@gearbox-protocol/permissionless/contracts/interfaces/IContractsRegister.sol";
import {IInstanceManager} from "@gearbox-protocol/permissionless/contracts/interfaces/IInstanceManager.sol";
import {IMarketConfiguratorFactory} from
    "@gearbox-protocol/permissionless/contracts/interfaces/IMarketConfiguratorFactory.sol";
import {CrossChainCall} from "@gearbox-protocol/permissionless/contracts/interfaces/Types.sol";
import {
    LegacyParams,
    MarketConfiguratorLegacy,
    PeripheryContract
} from "@gearbox-protocol/permissionless/contracts/market/legacy/MarketConfiguratorLegacy.sol";

// TODO: make sure pausableAdmins, unpausableAdmins and emergencyLiquidators are set properly
// e.g., in some cases multipause is not added to pausable admins, etc.

contract LegacyHelper {
    using LibString for bytes32;

    struct ChainInfo {
        uint256 chainId;
        string name;
        address weth;
        address gear;
        address usdt;
        address treasury;
        address router;
    }

    function _getChains() internal pure returns (ChainInfo[] memory chains) {
        ChainInfo[4] memory chains_ = [
            ChainInfo({
                chainId: 1,
                name: "Ethereum",
                weth: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
                gear: 0xBa3335588D9403515223F109EdC4eB7269a9Ab5D,
                usdt: 0xdAC17F958D2ee523a2206206994597C13D831ec7,
                treasury: 0x3E965117A51186e41c2BB58b729A1e518A715e5F,
                router: 0xA6FCd1fE716aD3801C71F2DE4E7A15f3a6994835
            }),
            ChainInfo({
                chainId: 10,
                name: "Optimism",
                weth: 0x4200000000000000000000000000000000000006,
                gear: 0x39E6C2E1757ae4354087266E2C3EA9aC4257C1eb,
                usdt: 0x0000000000000000000000000000000000000000,
                treasury: 0x1ACc5BC353f23B901801f3Ba48e1E51a14263808,
                router: 0x89f2E8F1c8d6D7cb276c81dd89128D08fc8E3363
            }),
            ChainInfo({
                chainId: 146,
                name: "Sonic",
                weth: 0x039e2fB66102314Ce7b64Ce5Ce3E5183bc94aD38,
                gear: 0x0fDbce271bea0d9819034cd09021e0bBE94be3Fd,
                usdt: 0x0000000000000000000000000000000000000000,
                treasury: 0x74028Cf1cBa6A4513c9a27137E7d0F3847833795,
                router: 0x9Fae6aA45aF0fcf94819fCE4f40416C76ce0928b
            }),
            ChainInfo({
                chainId: 42161,
                name: "Arbitrum",
                weth: 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1,
                gear: 0x2F26337576127efabEEc1f62BE79dB1bcA9148A4,
                usdt: 0x0000000000000000000000000000000000000000,
                treasury: 0x2c31eFFE426765E68A43163A96DD13DF70B53C14,
                router: 0xF26186465964ED3564EdFE0046eE65502a6Ac34D
            })
        ];
        chains = new ChainInfo[](chains_.length);
        for (uint256 i; i < chains_.length; ++i) {
            chains[i] = chains_[i];
        }
    }

    function _getActivateInstanceCalls(address instanceManager, address instanceOwner, ChainInfo memory chainInfo)
        internal
        pure
        returns (CrossChainCall[] memory calls)
    {
        calls = new CrossChainCall[](1);
        calls[0] = CrossChainCall({
            chainId: chainInfo.chainId,
            target: instanceManager,
            callData: abi.encodeCall(
                IInstanceManager.activate, (instanceOwner, chainInfo.treasury, chainInfo.weth, chainInfo.gear)
            )
        });
    }

    // --------------------------- //
    // LEGACY MARKET CONFIGURATORS //
    // --------------------------- //

    struct CuratorInfo {
        uint256 chainId;
        string chainName;
        string name;
        address admin;
        address emergencyAdmin;
        address feeSplitterAdmin;
        bool deployGovernor;
        LegacyParams legacyParams;
    }

    function _getCurators(address admin, address emergencyAdmin)
        internal
        pure
        returns (CuratorInfo[] memory curators)
    {
        CuratorInfo[5] memory curators_ = [
            CuratorInfo({
                chainId: 1,
                chainName: "Ethereum",
                name: "Chaos Labs",
                admin: admin,
                emergencyAdmin: emergencyAdmin,
                feeSplitterAdmin: address(0),
                deployGovernor: false,
                legacyParams: _getChaosLabsMainnetLegacyParams()
            }),
            CuratorInfo({
                chainId: 1,
                chainName: "Ethereum",
                name: "Nexo",
                admin: admin,
                emergencyAdmin: emergencyAdmin,
                feeSplitterAdmin: 0x349e22baeB15Da6fad00093b3873D5E16d5Bb842,
                deployGovernor: false,
                legacyParams: _getNexoMainnetLegacyParams()
            }),
            CuratorInfo({
                chainId: 10,
                chainName: "Optimism",
                name: "Chaos Labs",
                admin: admin,
                emergencyAdmin: emergencyAdmin,
                feeSplitterAdmin: address(0),
                deployGovernor: false,
                legacyParams: _getChaosLabsOptimismLegacyParams()
            }),
            CuratorInfo({
                chainId: 146,
                chainName: "Sonic",
                name: "Chaos Labs",
                admin: admin,
                emergencyAdmin: emergencyAdmin,
                feeSplitterAdmin: address(0),
                deployGovernor: false,
                legacyParams: _getChaosLabsSonicLegacyParams()
            }),
            CuratorInfo({
                chainId: 42161,
                chainName: "Arbitrum",
                name: "Chaos Labs",
                admin: admin,
                emergencyAdmin: emergencyAdmin,
                feeSplitterAdmin: address(0),
                deployGovernor: false,
                legacyParams: _getChaosLabsArbitrumLegacyParams()
            })
        ];
        curators = new CuratorInfo[](curators_.length);
        for (uint256 i; i < curators_.length; ++i) {
            curators[i] = curators_[i];
        }
    }

    function _getAddLegacyMarketConfiguratorCalls(
        address addressProvider,
        address marketConfiguratorFactory,
        CuratorInfo memory curatorInfo
    ) internal pure returns (CrossChainCall[] memory calls) {
        calls = new CrossChainCall[](1);
        address marketConfigurator = _computeLegacyMarketConfiguratorAddress(addressProvider, curatorInfo);
        calls[0] = CrossChainCall({
            chainId: curatorInfo.chainId,
            target: marketConfiguratorFactory,
            callData: abi.encodeCall(IMarketConfiguratorFactory.addMarketConfigurator, (marketConfigurator))
        });
    }

    function _computeLegacyMarketConfiguratorAddress(address addressProvider, CuratorInfo memory curatorInfo)
        internal
        pure
        returns (address)
    {
        bytes32 salt = bytes32("SALT");
        bytes memory initCode = abi.encodePacked(
            type(MarketConfiguratorLegacy).creationCode,
            abi.encode(
                addressProvider,
                curatorInfo.admin,
                curatorInfo.emergencyAdmin,
                curatorInfo.feeSplitterAdmin,
                curatorInfo.name,
                curatorInfo.deployGovernor,
                curatorInfo.legacyParams
            )
        );
        bytes32 bytecodeHash = keccak256(initCode);
        return Create2.computeAddress(salt, bytecodeHash, 0x4e59b44847b379578588920cA78FbF26c0B4956C);
    }

    function _deployLegacyMarketConfigurator(address addressProvider, CuratorInfo memory curatorInfo) internal {
        MarketConfiguratorLegacy marketConfigurator = new MarketConfiguratorLegacy{salt: "SALT"}({
            addressProvider_: addressProvider,
            admin_: curatorInfo.admin,
            emergencyAdmin_: curatorInfo.emergencyAdmin,
            feeSplitterAdmin_: curatorInfo.feeSplitterAdmin,
            curatorName_: curatorInfo.name,
            deployGovernor_: curatorInfo.deployGovernor,
            legacyParams_: curatorInfo.legacyParams
        });

        address contractsRegister = marketConfigurator.contractsRegister();
        address[] memory pools = IContractsRegister(contractsRegister).getPools();
        uint256 numPools = pools.length;
        for (uint256 i; i < numPools; ++i) {
            address pool = pools[i];
            marketConfigurator.initializeMarket(pool);
        }
        address[] memory creditManagers = IContractsRegister(contractsRegister).getCreditManagers();
        uint256 numCreditManagers = creditManagers.length;
        for (uint256 i; i < numCreditManagers; ++i) {
            address creditManager = creditManagers[i];
            marketConfigurator.initializeCreditSuite(creditManager);
        }

        console.log(
            string.concat(
                "Deployed legacy market configurator for ", curatorInfo.name, " on ", curatorInfo.chainName, " at"
            ),
            address(marketConfigurator)
        );
    }

    function _getChaosLabsMainnetLegacyParams() internal pure returns (LegacyParams memory) {
        address acl = 0x523dA3a8961E4dD4f6206DBf7E6c749f51796bb3;
        address contractsRegister = 0xA50d4E7D8946a7c90652339CDBd262c375d54D99;
        address gearStaking = 0x2fcbD02d5B1D52FC78d4c02890D7f4f47a459c33;
        address priceOracle = 0x599f585D1042A14aAb194AC8031b2048dEFdFB85;
        address zapperRegister = 0x3E75276548a7722AbA517a35c35FB43CF3B0E723;

        address[] memory pausableAdmins = new address[](16);
        pausableAdmins[0] = 0xA7D5DDc1b8557914F158076b228AA91eF613f1D5;
        pausableAdmins[1] = 0x65b384cEcb12527Da51d52f15b4140ED7FaD7308;
        pausableAdmins[2] = 0xD7b069517246edB58Ce670485b4931E0a86Ab6Ff;
        pausableAdmins[3] = 0xD5C96E5c1E1C84dFD293473fC195BbE7FC8E4840;
        pausableAdmins[4] = 0xa133C9A92Fb8dDB962Af1cbae58b2723A0bdf23b;
        pausableAdmins[5] = 0xd4fe3eD38250C38A0094224C4B0224b5D5d0e7d9;
        pausableAdmins[6] = 0x8d2f33d168cca6D2436De16c27d3f1cEa30aC245;
        pausableAdmins[7] = 0x67479449b2cf25AEE2fB6EF6f0aEc54591154F62;
        pausableAdmins[8] = 0x4Ae3EDbDf1C42e3560Cc2D52B8F353F026F67b44;
        pausableAdmins[9] = 0x700De428aa940000259B1c58F3E44445d360303c;
        pausableAdmins[10] = 0xf4ecc4e950b563F113b17C5606B31a314B99BFe3;
        pausableAdmins[11] = 0xFaCADE00dc661bfBE736e2F0f72b4Ee59017d5fb;
        pausableAdmins[12] = 0xc9E3453E212A13169AaA66aa39DCcE82aE6966B7;
        pausableAdmins[13] = 0x34EE4eed88BCd2B5cDC3eF9A9DD0582EE538E541;
        pausableAdmins[14] = 0x3F185f4ec14fCfB522bC499d790a9608A05E64F6;
        pausableAdmins[15] = 0xbb803559B4D58b75E12dd74641AB955e8B0Df40E;

        address[] memory unpausableAdmins = new address[](3);
        unpausableAdmins[0] = 0xA7D5DDc1b8557914F158076b228AA91eF613f1D5;
        unpausableAdmins[1] = 0xbb803559B4D58b75E12dd74641AB955e8B0Df40E;
        unpausableAdmins[2] = 0xa133C9A92Fb8dDB962Af1cbae58b2723A0bdf23b;

        address[] memory emergencyLiquidators = new address[](2);
        emergencyLiquidators[0] = 0x7BD9c8161836b1F402233E80F55E3CaE0Fde4d87;
        emergencyLiquidators[1] = 0x16040e932b5Ac7A3aB23b88a2f230B4185727b0d;

        PeripheryContract[] memory peripheryContracts = new PeripheryContract[](7);
        peripheryContracts[0] = PeripheryContract("DEGEN_NFT", 0xB829a5b349b01fc71aFE46E50dD6Ec0222A6E599);
        peripheryContracts[1] = PeripheryContract("MULTI_PAUSE", 0x3F185f4ec14fCfB522bC499d790a9608A05E64F6);
        peripheryContracts[2] = PeripheryContract("DEGEN_DISTRIBUTOR", 0x6cA68adc7eC07a4bD97c97e8052510FBE6b67d10);
        peripheryContracts[3] = PeripheryContract("BOT", 0x0f06c2bD612Ee7D52d4bC76Ce3BD7E95247AF2a9);
        peripheryContracts[4] = PeripheryContract("BOT", 0x53fDA9a509020Fc534EfF938Fd01dDa5fFe8560c);
        peripheryContracts[5] = PeripheryContract("BOT", 0x82b0adfA8f09b20BB4ed066Bcd4b2a84BEf73D5E);
        peripheryContracts[6] = PeripheryContract("BOT", 0x519906cD00222b4a81bf14A7A11fA5FCF455Af42);

        return LegacyParams({
            acl: acl,
            contractsRegister: contractsRegister,
            gearStaking: gearStaking,
            priceOracle: priceOracle,
            zapperRegister: zapperRegister,
            pausableAdmins: pausableAdmins,
            unpausableAdmins: unpausableAdmins,
            emergencyLiquidators: emergencyLiquidators,
            peripheryContracts: peripheryContracts
        });
    }

    function _getChaosLabsOptimismLegacyParams() internal pure returns (LegacyParams memory) {
        address acl = 0x6a2994Af133e0F87D9b665bFCe821dC917e8347D;
        address contractsRegister = 0x949F9899bDaDcC7831Ca422f115fe61f4211a30b;
        address gearStaking = 0x8D2622f1CA3B42b637e2ff6753E6b69D3ab9Adfd;
        address priceOracle = 0xbb3970A9E68ce2e2Dc39fE702A3ad82cfD0eDE7F;
        address zapperRegister = 0x5f49A919d67378290f5aeb359928E0020cD90Bae;

        address[] memory pausableAdmins = new address[](6);
        pausableAdmins[0] = 0x148DD932eCe1155c11006F5650c6Ff428f8D374A;
        pausableAdmins[1] = 0x44c01002ef0955A4DBD86D90dDD27De6eeE37aA3;
        pausableAdmins[2] = 0x65b384cEcb12527Da51d52f15b4140ED7FaD7308;
        pausableAdmins[3] = 0xD5C96E5c1E1C84dFD293473fC195BbE7FC8E4840;
        pausableAdmins[4] = 0x8bA8cd6D00919ceCc19D9B4A2c8669a524883C4c;
        pausableAdmins[5] = 0x9744f76dc5239Eb4DC2CE8D5538e1BA89C8FA90f;

        address[] memory unpausableAdmins = new address[](4);
        unpausableAdmins[0] = 0x148DD932eCe1155c11006F5650c6Ff428f8D374A;
        unpausableAdmins[1] = 0x44c01002ef0955A4DBD86D90dDD27De6eeE37aA3;
        unpausableAdmins[2] = 0x8bA8cd6D00919ceCc19D9B4A2c8669a524883C4c;
        unpausableAdmins[3] = 0x9744f76dc5239Eb4DC2CE8D5538e1BA89C8FA90f;

        address[] memory emergencyLiquidators = new address[](2);
        emergencyLiquidators[0] = 0x7BD9c8161836b1F402233E80F55E3CaE0Fde4d87;
        emergencyLiquidators[1] = 0x16040e932b5Ac7A3aB23b88a2f230B4185727b0d;

        PeripheryContract[] memory peripheryContracts = new PeripheryContract[](7);
        peripheryContracts[0] = PeripheryContract("DEGEN_NFT", 0xC07aA1e2D2a262E5DA35D21d01b6C5f372226dBC);
        peripheryContracts[1] = PeripheryContract("MULTI_PAUSE", 0x44c01002ef0955A4DBD86D90dDD27De6eeE37aA3);
        peripheryContracts[2] = PeripheryContract("DEGEN_DISTRIBUTOR", 0x0106b15Dd9FB263B76d6F917cB19555d2a25cd76);
        peripheryContracts[3] = PeripheryContract("BOT", 0x0A12a15F359FdefD36c9fA8bd3193940A8B344eF);
        peripheryContracts[4] = PeripheryContract("BOT", 0x383562873F3c3A75ec5CEC6F9b91B5F04d44465c);
        peripheryContracts[5] = PeripheryContract("BOT", 0x7B84Db149430fbB158c67E0F08B162a746A757bd);
        peripheryContracts[6] = PeripheryContract("BOT", 0x08952Ea9cEA25781C5b7F9B5fD8a534aC614DD37);

        return LegacyParams({
            acl: acl,
            contractsRegister: contractsRegister,
            gearStaking: gearStaking,
            priceOracle: priceOracle,
            zapperRegister: zapperRegister,
            pausableAdmins: pausableAdmins,
            unpausableAdmins: unpausableAdmins,
            emergencyLiquidators: emergencyLiquidators,
            peripheryContracts: peripheryContracts
        });
    }

    function _getChaosLabsSonicLegacyParams() internal pure returns (LegacyParams memory) {
        address acl = 0xAd131da4BDdb40EbB5CEeaea87067553D4313895;
        address contractsRegister = 0xF2b8E0f4705ceC47a8B8Eb7Dbc29B3322198058b;
        address gearStaking = 0xe88846b6C85AA67688e453c7eaeeeb40F51e1F0a;
        address priceOracle = 0x39Be03d0275292dF39439722C610E7db3F155d05;
        address zapperRegister = 0x7e10482eEF36dA8e732e86C5de6282fF13B71Fe1;

        address[] memory pausableAdmins = new address[](5);
        pausableAdmins[0] = 0xAdbF876ce58CB65c99b18078353e1DCB16E69e84;
        pausableAdmins[1] = 0x65b384cEcb12527Da51d52f15b4140ED7FaD7308;
        pausableAdmins[2] = 0xD5C96E5c1E1C84dFD293473fC195BbE7FC8E4840;
        pausableAdmins[3] = 0xacEB9dc6a81f1C9E2d8a86c3bFec3f6EF584139D;
        pausableAdmins[4] = 0x393eC629b90389F957c5a2E4FC2F8F488e735BFC;

        address[] memory unpausableAdmins = new address[](3);
        unpausableAdmins[0] = 0xAdbF876ce58CB65c99b18078353e1DCB16E69e84;
        unpausableAdmins[1] = 0xacEB9dc6a81f1C9E2d8a86c3bFec3f6EF584139D;
        unpausableAdmins[2] = 0x393eC629b90389F957c5a2E4FC2F8F488e735BFC;

        address[] memory emergencyLiquidators = new address[](2);
        emergencyLiquidators[0] = 0x7BD9c8161836b1F402233E80F55E3CaE0Fde4d87;
        emergencyLiquidators[1] = 0x16040e932b5Ac7A3aB23b88a2f230B4185727b0d;

        PeripheryContract[] memory peripheryContracts = new PeripheryContract[](7);
        peripheryContracts[0] = PeripheryContract("DEGEN_NFT", 0xf24411cB47918057587b793e98aC7fA9A8a710c2);
        peripheryContracts[1] = PeripheryContract("MULTI_PAUSE", 0xaF1470dED2BE116dbBE6A5090078feC21B02F78E);
        peripheryContracts[2] = PeripheryContract("DEGEN_DISTRIBUTOR", 0x1998956732cD652FF3d35134294Ad20aCB2CDA80);
        peripheryContracts[3] = PeripheryContract("BOT", 0x47d2a88f32b630f6C8b107c37d0AF58a861d3406);
        peripheryContracts[4] = PeripheryContract("BOT", 0x2A8446D5305499F5A9C8f3768104562eBD45e941);
        peripheryContracts[5] = PeripheryContract("BOT", 0xEF74B1273FD4cb49109230EDa9b72f0B50031f5b);
        peripheryContracts[6] = PeripheryContract("BOT", 0xd2D1E5afeE34abf1CfA27eA94af25d3AF8fFe31A);

        return LegacyParams({
            acl: acl,
            contractsRegister: contractsRegister,
            gearStaking: gearStaking,
            priceOracle: priceOracle,
            zapperRegister: zapperRegister,
            pausableAdmins: pausableAdmins,
            unpausableAdmins: unpausableAdmins,
            emergencyLiquidators: emergencyLiquidators,
            peripheryContracts: peripheryContracts
        });
    }

    function _getChaosLabsArbitrumLegacyParams() internal pure returns (LegacyParams memory) {
        address acl = 0xb2FA6c1a629Ed72BF99fbB24f75E5D130A5586F1;
        address contractsRegister = 0xc3e00cdA97D5779BFC8f17588d55b4544C8a6c47;
        address gearStaking = 0xf3599BEfe8E79169Afd5f0b7eb0A1aA322F193D9;
        address priceOracle = 0xF6C709a419e18819dea30248f59c95cA20fd83d5;
        address zapperRegister = 0xFFadb168E3ACB881DE164aDdfc77d92dbc2D4C16;

        address[] memory pausableAdmins = new address[](5);
        pausableAdmins[0] = 0x148DD932eCe1155c11006F5650c6Ff428f8D374A;
        pausableAdmins[1] = 0xf9E344ADa2181A4104a7DC6092A92A1bC67A52c9;
        pausableAdmins[2] = 0x65b384cEcb12527Da51d52f15b4140ED7FaD7308;
        pausableAdmins[3] = 0xD5C96E5c1E1C84dFD293473fC195BbE7FC8E4840;
        pausableAdmins[4] = 0x746fb3AcAfF6Bfe246206EC2E51F587d2E57abb6;

        address[] memory unpausableAdmins = new address[](3);
        unpausableAdmins[0] = 0x148DD932eCe1155c11006F5650c6Ff428f8D374A;
        unpausableAdmins[1] = 0xf9E344ADa2181A4104a7DC6092A92A1bC67A52c9;
        unpausableAdmins[2] = 0x746fb3AcAfF6Bfe246206EC2E51F587d2E57abb6;

        address[] memory emergencyLiquidators = new address[](2);
        emergencyLiquidators[0] = 0x7BD9c8161836b1F402233E80F55E3CaE0Fde4d87;
        emergencyLiquidators[1] = 0x16040e932b5Ac7A3aB23b88a2f230B4185727b0d;

        PeripheryContract[] memory peripheryContracts = new PeripheryContract[](7);
        peripheryContracts[0] = PeripheryContract("DEGEN_NFT", 0x32D72d4AB2A6066A2f301EEc0515d04B282aC06A);
        peripheryContracts[1] = PeripheryContract("MULTI_PAUSE", 0xf9E344ADa2181A4104a7DC6092A92A1bC67A52c9);
        peripheryContracts[2] = PeripheryContract("DEGEN_DISTRIBUTOR", 0x79a6FcdDDe1918D6a5b1D9757f29a338C942d547);
        peripheryContracts[3] = PeripheryContract("BOT", 0x938094B41dDaC7bD3f21fC962D424E1a84ac4a85);
        peripheryContracts[4] = PeripheryContract("BOT", 0x44A9fDEF7307AE8C0997a1A339588a1C073930a7);
        peripheryContracts[5] = PeripheryContract("BOT", 0x8A35C229ff4f96e8b7A4f9168B22b9F7DF6b82f3);
        peripheryContracts[6] = PeripheryContract("BOT", 0x538d66d6cA2607673ceC8af3cA3933476f361633);

        return LegacyParams({
            acl: acl,
            contractsRegister: contractsRegister,
            gearStaking: gearStaking,
            priceOracle: priceOracle,
            zapperRegister: zapperRegister,
            pausableAdmins: pausableAdmins,
            unpausableAdmins: unpausableAdmins,
            emergencyLiquidators: emergencyLiquidators,
            peripheryContracts: peripheryContracts
        });
    }

    function _getNexoMainnetLegacyParams() internal pure returns (LegacyParams memory) {
        address acl = 0x83347DbF1DC98db2989BeEf5746790431B934614;
        address contractsRegister = 0x0e1d8e931F0F3FE33FAdcA0bb517E5A8E1CD8E1B;
        address gearStaking = 0x2fcbD02d5B1D52FC78d4c02890D7f4f47a459c33;
        address priceOracle = 0x599f585D1042A14aAb194AC8031b2048dEFdFB85;
        address zapperRegister = 0x522c047660A2d81D8D831457770404B9621A6eD9;

        address[] memory pausableAdmins = new address[](5);
        pausableAdmins[0] = 0x3655Ae71eB5437F8FbD0187C012e4619064F9B41;
        pausableAdmins[1] = 0xdcC3FD83DBF480e8Ad74DD3A634CaE29B68b9814;
        pausableAdmins[2] = 0xdD84A24eeddE63F10Ec3e928f1c8302A47538b6B;
        pausableAdmins[3] = 0x043BBDf51239bC7F958D0bF6c6fA4E2A825621f6;
        pausableAdmins[4] = 0x029De72Fa62A2AdB1E84E97A339F92ce4810e2a9;

        address[] memory unpausableAdmins = new address[](4);
        unpausableAdmins[0] = 0x3655Ae71eB5437F8FbD0187C012e4619064F9B41;
        unpausableAdmins[1] = 0xdcC3FD83DBF480e8Ad74DD3A634CaE29B68b9814;
        unpausableAdmins[2] = 0xdD84A24eeddE63F10Ec3e928f1c8302A47538b6B;
        unpausableAdmins[3] = 0x029De72Fa62A2AdB1E84E97A339F92ce4810e2a9;

        address[] memory emergencyLiquidators = new address[](7);
        emergencyLiquidators[0] = 0xbd796DdE46DEB00B1840e7be311eF469c375c940;
        emergencyLiquidators[1] = 0x98b0EB10A3a2aaf72CA2C362f8D8360FE6037E8b;
        emergencyLiquidators[2] = 0x16040e932b5Ac7A3aB23b88a2f230B4185727b0d;
        emergencyLiquidators[3] = 0x3c2E5548bCe88315D50eAB4f6b1Ffb2f1B8eBd7A;
        emergencyLiquidators[4] = 0x1a396F9209BDbF7E1Bc95c488E7F1237DA796a03;
        emergencyLiquidators[5] = 0x3d673C58eA3486E95943F4418932c3b1776B3c8c;
        emergencyLiquidators[6] = 0x32D956b225b0F1C1E78E676a53C886552c38ed70;

        PeripheryContract[] memory peripheryContracts = new PeripheryContract[](5);
        peripheryContracts[0] = PeripheryContract("MULTI_PAUSE", 0x029De72Fa62A2AdB1E84E97A339F92ce4810e2a9);
        peripheryContracts[1] = PeripheryContract("BOT", 0xc82020f1922AE56CCF25d5F2E2d6155E44583ef9);
        peripheryContracts[2] = PeripheryContract("BOT", 0x5397F95B1452EBEE91369c9b35149602d4ACBee2);
        peripheryContracts[3] = PeripheryContract("BOT", 0xE5f56A2C92FAA510785d1dBe269774Cf815bCA4A);
        peripheryContracts[4] = PeripheryContract("BOT", 0x3E3a906C8b286b6f95e61E7580E1Eb081BD1299D);

        return LegacyParams({
            acl: acl,
            contractsRegister: contractsRegister,
            gearStaking: gearStaking,
            priceOracle: priceOracle,
            zapperRegister: zapperRegister,
            pausableAdmins: pausableAdmins,
            unpausableAdmins: unpausableAdmins,
            emergencyLiquidators: emergencyLiquidators,
            peripheryContracts: peripheryContracts
        });
    }
}
