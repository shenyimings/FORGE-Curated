// SPDX-License-Identifier: MIT

pragma solidity ^0.8.10;

import { Script, console } from "forge-std/Script.sol";
import { DeployCapyfiProtocol } from "./capyfi/DeployCapyfiProtocol.s.sol";
import { DeployInterestRateModels } from "./capyfi/DeployInterestRateModels.s.sol";
import { DeployMockTokens } from "./capyfi/DeployMockTokens.s.sol";
import { DeployCTokens } from "./capyfi/DeployCTokens.s.sol";
import { Config } from "./capyfi/config/Config.sol";
import { ProdConfig } from "./capyfi/config/ProdConfig.sol";
import { CustomConfig } from "./capyfi/config/CustomConfig.sol";

abstract contract CodeConstants {
    address public FOUNDRY_DEFAULT_SENDER = 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38;

    address public ANVIL_DEFAULT_SENDER = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

    uint256 public constant LATESTNET_CHAIN_ID = 418;
    uint256 public constant LACHAIN_CHAIN_ID = 274;
    uint256 public constant LOCAL_CHAIN_ID = 31_337;
    uint256 public constant ETHEREUM_CHAIN_ID = 1;
    uint256 public constant SEPOLIA_CHAIN_ID = 11155111;
    uint256 public constant FORKED_ETHEREUM_CHAIN_ID = 7400;
}

contract HelperConfig is CodeConstants, Script {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error HelperConfig__InvalidChainId();

    /*//////////////////////////////////////////////////////////////
                                 TYPES
    //////////////////////////////////////////////////////////////*/

    struct NetworkConfig {
        address unitroller; // Unitroller contract address
        address comptroller; // Comptroller contract address
        address oracle; // Oracle contract address
        Config.DeployedInterestRateModels interestRateModels;
        Config.DeployedCTokens cTokens;
        Config.DeployedUnderlyingTokens underlyingTokens;
        address account;
    }

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    // Local network state variables
    NetworkConfig public localNetworkConfig;
    mapping(uint256 => NetworkConfig) public networkConfigs;

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    constructor() {
        networkConfigs[LATESTNET_CHAIN_ID] = getLaTestnetConfig();
        networkConfigs[LACHAIN_CHAIN_ID] = getLaChainConfig();
        networkConfigs[ETHEREUM_CHAIN_ID] = getEthereumConfig();
        networkConfigs[SEPOLIA_CHAIN_ID] = getSepoliaConfig();
        networkConfigs[FORKED_ETHEREUM_CHAIN_ID] = getForkedEthereumConfig();
        // Note: We skip doing the local config
    }

    function getConfig() public returns (NetworkConfig memory) {
        return getConfigByChainId(block.chainid);
    }

    function setConfig(uint256 chainId, NetworkConfig memory networkConfig) public {
        networkConfigs[chainId] = networkConfig;
    }

    function getConfigByChainId(uint256 chainId) public returns (NetworkConfig memory) {
        if (networkConfigs[chainId].unitroller != address(0)) {
            return networkConfigs[chainId];
        } else if (chainId == LOCAL_CHAIN_ID) {
            return getOrCreateAnvilEthConfig();
        } else {
            revert HelperConfig__InvalidChainId();
        }
    }

    function getLaTestnetConfig() public pure returns (NetworkConfig memory latestnetConfig) {
        latestnetConfig = NetworkConfig({
            unitroller: 0x6a672B8Ab304Fd8BDEBF817a456bB67834c580B8,
            comptroller: 0x891BBb982E2B4A5768E11141a90D91022Cfab7a1,
            oracle: 0xB0aB685705d1eC031CB305946FDc775848139308,
            interestRateModels: Config.DeployedInterestRateModels({
                iRM_UXD_Updateable: 0xB07D9989dd1BF10894a5B67dF8204df9a86c0F05,
                iRM_WETH_Updateable: 0x64D1CF3CcE14Ecf64a6d5365F5301C50DAE6BE04,
                iRM_LAC_Updateable: 0x844b2d34E00631Ee3Df1AB5865F78484d06e57C3,
                iRM_WBTC_Updateable: 0x12B0e76F3D5240Bd8463b7060C7533C6Fb278Db1,
                iRM_USDT_Updateable: 0xc36e31EB3C2c61Bf9AAd43Da6233b248D775BFb6,
                iRM_USDC_Updateable: 0x0000000000000000000000000000000000000000,
                iRM_MockCToken_Updateable: 0x0000000000000000000000000000000000000000
            }),
            cTokens: Config.DeployedCTokens({
                caUXD: 0x75CEf1817587DcB40498019C65335D7d8b490985,
                caWETH: 0x4f385642b0dB52B644adF2716633309F74F3705F,
                caLAC: 0xF5B67b03C2523b2C60d1218555166E9B1B102852,
                caWBTC: 0x9BF347805a27c9fc3afE21A10A94B3bF98FF1798,
                caUSDT: 0x838D312461072A1dAc2c912449c97142b274CFAC,
                caUSDC: 0x0000000000000000000000000000000000000000,
                caMOCK: 0x0000000000000000000000000000000000000000
            }),
            underlyingTokens: Config.DeployedUnderlyingTokens({
                uxd: 0xf6Ca7FD7722b5Fa683788aE56b82df3501B54386,
                weth: 0x5bc9577E712E4AE153268feFCb1ef17e81e1D8ea,
                wbtc: 0x1CAf8ecb17fAc1693c9F0af5f9DfC7596b835954,
                usdt: 0x1CD17f8e3C4dD2e897Ee8b2660b5E9AD56387953,
                usdc: 0x0000000000000000000000000000000000000000,
                mockUnderlying: 0x0000000000000000000000000000000000000000,
                lac: address(0)
            }),
            account: 0x4F379424719a1feF0196F4913DccF3eB6d49AdE9
        });
    }

    function getLaChainConfig() public pure returns (NetworkConfig memory lachainConfig) {
        lachainConfig = NetworkConfig({
            unitroller: 0x123Abe3A273FDBCeC7fc0EBedc05AaeF4eE63060,
            comptroller: 0xB45435f4d5Fa43C8Fd59199beA39D5A023D0d20c,
            oracle: 0x4E07BDEec540D3a2318A91fAEe130E692506a360,
            interestRateModels: Config.DeployedInterestRateModels({
                iRM_UXD_Updateable: 0x5164Ebab89dE284b1b8f8839C6240B7f76d5B2D6,
                iRM_WETH_Updateable: 0x64bC091f97764f30c86A153254c8bfE0106a1746,
                iRM_LAC_Updateable: 0x53898cb3f79790a6F077e2D3f877011b1aeB553c,
                iRM_WBTC_Updateable: 0xb92fBb1FAa5ff3213Afb02B881eF30Ca4c2109fC,
                iRM_USDT_Updateable: 0x021097EB068De295CDB6829960bb92643FB23653,
                iRM_USDC_Updateable: 0xD6f850Cf3688f2423bd004cd06c998db2CE49423,
                iRM_MockCToken_Updateable: 0x0000000000000000000000000000000000000000
            }),
            cTokens: Config.DeployedCTokens({
                caUXD: 0x8A3e793Ea2120A615dA2119b03CA015ceE59DB5c,
                caWETH: 0xe06651160F514b8a6bA65f83f07dEca2889b3C46,
                caLAC: 0x465ebFCeB3953e2922B686F2B4006173664D16cE,
                caWBTC: 0x694C3940B4680504a82d6c30E64377B0D2e9d251,
                caUSDT: 0x87153302A2b8B2dCf29642D149F5C88C73ee4bf6,
                caUSDC: 0x08dfCC0eE2659d131bb82e4f15e15513F643063E,
                caMOCK: 0x0000000000000000000000000000000000000000
            }),
            underlyingTokens: Config.DeployedUnderlyingTokens({
                uxd: 0xDe09E74d4888Bc4e65F589e8c13Bce9F71DdF4c7,
                weth: 0x42C8C9C0f0A98720dACdaeaC0C319cb272b00d7E,
                wbtc: 0xf54B8cb8eeEe3823A55dDDF5540ceADdf9724626,
                usdt: 0x7dC8b9e3B083C26C68f0B124cA923AaEc7FBee39,
                usdc: 0x51115241c7b8361EeE88D8610f71d0A92cee5323,
                mockUnderlying: 0x0000000000000000000000000000000000000000,
                lac: address(0)

            }),
            account: 0x0000000000000000000000000000000000000000
        });
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
        // Check to see if we set an active network config
        if (localNetworkConfig.unitroller != address(0)) {
            return localNetworkConfig;
        }

        // Deploy Capyfi Protocol
        DeployCapyfiProtocol deployCapyfiProtocol = new DeployCapyfiProtocol();
        Config.DeployedProtocolContracts memory capyfiProtocolAddresses = deployCapyfiProtocol.run(ANVIL_DEFAULT_SENDER);

        // Deploy InterestRateModels
        DeployInterestRateModels deployInterestRateModels = new DeployInterestRateModels();
        Config.DeployedInterestRateModels memory irmAddresses = deployInterestRateModels.run(ANVIL_DEFAULT_SENDER);

        // Deploy Mock ERC20s
        DeployMockTokens deployMockTokens = new DeployMockTokens();
        Config.DeployedUnderlyingTokens memory mockTokenAddresses = deployMockTokens.run(ANVIL_DEFAULT_SENDER);

        // DeployCTokens
        DeployCTokens deployCTokens = new DeployCTokens();
        Config.DeployedCTokens memory cTokenAddresses = deployCTokens.run(
            ANVIL_DEFAULT_SENDER,
            capyfiProtocolAddresses,
            irmAddresses,
            mockTokenAddresses
        );

        localNetworkConfig = NetworkConfig({
            unitroller: capyfiProtocolAddresses.unitroller,
            comptroller: capyfiProtocolAddresses.comptroller,
            oracle: capyfiProtocolAddresses.priceOracle,
            interestRateModels: Config.DeployedInterestRateModels({
                iRM_UXD_Updateable: irmAddresses.iRM_UXD_Updateable,
                iRM_WETH_Updateable: irmAddresses.iRM_WETH_Updateable,
                iRM_LAC_Updateable: irmAddresses.iRM_LAC_Updateable,
                iRM_WBTC_Updateable: irmAddresses.iRM_WBTC_Updateable,
                iRM_USDT_Updateable: irmAddresses.iRM_USDT_Updateable,
                iRM_USDC_Updateable: irmAddresses.iRM_USDC_Updateable,
                iRM_MockCToken_Updateable: irmAddresses.iRM_MockCToken_Updateable
            }),
            cTokens: Config.DeployedCTokens({
                caUXD: cTokenAddresses.caUXD,
                caWETH: cTokenAddresses.caWETH,
                caLAC: cTokenAddresses.caLAC,
                caWBTC: cTokenAddresses.caWBTC,
                caUSDT: cTokenAddresses.caUSDT,
                caUSDC: cTokenAddresses.caUSDC,
                caMOCK: cTokenAddresses.caMOCK
            }),
            underlyingTokens: Config.DeployedUnderlyingTokens({
                uxd: mockTokenAddresses.uxd,
                weth: mockTokenAddresses.weth,
                wbtc: mockTokenAddresses.wbtc,
                usdt: mockTokenAddresses.usdt,
                usdc: mockTokenAddresses.usdc,
                mockUnderlying: mockTokenAddresses.mockUnderlying,
                lac: address(0)
            }),
            account: ANVIL_DEFAULT_SENDER
        });

        return localNetworkConfig;
    }

    function getEthereumConfig() public pure returns (NetworkConfig memory ethereumConfig) {
        ethereumConfig = NetworkConfig({
            unitroller: 0x0b9af1fd73885aD52680A1aeAa7A3f17AC702afA,
            comptroller: 0x00dc4965916e03A734190fA382633657c71f867E,
            oracle: 0xfbA2712d3bbcf32c6E0178a21955b61FE1FF424A,
            interestRateModels: Config.DeployedInterestRateModels({
                iRM_UXD_Updateable: 0xf5FA0EA9C6b7bE2da713F8BDec9D35AAE289E5c0,
                iRM_WETH_Updateable: 0x03c1cF154d621E0Fd7e2b88be3aE60CCf07Aca31,
                iRM_LAC_Updateable: 0x254FCeeece1893c0A55bC7cF8A8a1C21cB05C29C,
                iRM_WBTC_Updateable: 0xcA142dA9286D37211e7e04FEc59D1de5de86EF33,
                iRM_USDT_Updateable: 0x5BeA6bE1DCcD0b5066842d42852e6302d7f668e8,
                iRM_USDC_Updateable: 0xa6b02274f7B017C96d570bc2693119c90533E9c3,
                iRM_MockCToken_Updateable: address(0)
            }),
            cTokens: Config.DeployedCTokens({
                caUXD: 0x98Ac8AC56d833bD69d34F909Ac15226772FAc9aa,
                caWETH: 0x37DE57183491Fa9745d8Fa5DCd950f0c3a4645c9,
                caLAC: 0x0568F6cb5A0E84FACa107D02f81ddEB1803f3B50,
                caWBTC: 0xDa5928d59ECE82808Af2cbBE4f2872FeA8E12CD6,
                caUSDT: 0x0f864A3e50D1070adDE5100fd848446C0567362B,
                caUSDC: 0xc3aD34De18B59A24BD0877e454Fb924181F09C8f,
                caMOCK: address(0)
            }),
            underlyingTokens: Config.DeployedUnderlyingTokens({
                uxd: 0x0f6011F7DBC40c17EcE894b1147f4ecfA712b600, // Mainnet UXD
                weth: address(0), // we use native eth as underlying for cETH
                wbtc: 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599, // Mainnet WBTC
                usdt: 0xdAC17F958D2ee523a2206206994597C13D831ec7, // Mainnet USDT
                usdc: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, // Mainnet USDC
                lac: 0x0Df3a853e4B604fC2ac0881E9Dc92db27fF7f51b, // Mainnet LAC
                mockUnderlying: address(0)
            }),
            account: address(0)
        });
    }

    function getForkedEthereumConfig() public pure returns (NetworkConfig memory forkedEthereumConfig) {
        forkedEthereumConfig = NetworkConfig({
            unitroller: 0x7C4BDA48bd4C9ac4FbcC60deEb66bf80d35705f0,
            comptroller: 0x9C6c49E1a5108eC5A2111c0b9B62624100d11e3a,
            oracle: 0x897945A56464616a525C9e5F11a8D400a72a8f3A,
            interestRateModels: Config.DeployedInterestRateModels({
                iRM_UXD_Updateable: 0x17f4B55A352Be71CC03856765Ad04147119Aa09B,
                iRM_WETH_Updateable: 0xa7480B62a657555f6727bCdb96953bCC211FFbaC,
                iRM_LAC_Updateable: 0xDf66AB853Fc112Ec955531bd76E9079db30A0e27,
                iRM_WBTC_Updateable: 0xa9Ea7F91E63896d852c4FCA6124c974adC68Af3B,
                iRM_USDT_Updateable: 0xF816b7FfDa4a8aB6B68540D1993fCa98E462b3bc,
                iRM_USDC_Updateable: 0x8797847c9d63D8Ed9C30B058F408d4257A33B76C,
                iRM_MockCToken_Updateable: address(0)
            }),
            cTokens: Config.DeployedCTokens({
                caUXD: 0x5E0399B4C3c4C31036DcA08d53c0c5b5c29C113e,
                caWETH: 0x512a0E8bAeb6Ac3D52A11780c92517627005b0b1,
                caLAC: 0x71d75C9A9e1a4fFa5a16556b51D6e630A4FA902A,
                caWBTC: 0x012D720e7d2E84b24b68989e0f4aD824fE5B294C,
                caUSDT: 0x886a2A3ABF5B79AA5dFF1C73016BD07CFc817e04,
                caUSDC: 0x701dC26AcaD119E892695bb6A06956e2165C2052,
                caMOCK: address(0)
            }),
            underlyingTokens: Config.DeployedUnderlyingTokens({
                uxd: 0x0f6011F7DBC40c17EcE894b1147f4ecfA712b600, // Mainnet UXD
                weth: address(0), // we use native eth as underlying for cETH
                wbtc: 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599, // Mainnet WBTC
                usdt: 0xdAC17F958D2ee523a2206206994597C13D831ec7, // Mainnet USDT
                usdc: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, // Mainnet USDC
                lac: 0x0Df3a853e4B604fC2ac0881E9Dc92db27fF7f51b, // Mainnet LAC
                mockUnderlying: address(0)
            }),
            account: address(0)
        });
    }

    function getSepoliaConfig() public pure returns (NetworkConfig memory sepoliaConfig) {
        sepoliaConfig = NetworkConfig({
            unitroller: 0x6E612712a07372Db6b937c45c1E178882e15D413,
            comptroller: 0x42BEccd00782b758e16B057f5b01037bF7234A8d,
            oracle: 0xAc8a31177dA73a1d82976676e4Fa70CF7BB00Fbb,
            interestRateModels: Config.DeployedInterestRateModels({
                iRM_UXD_Updateable: 0xDe23335c964B16c7115145d02cAfFf3622c2E6a0,
                iRM_WETH_Updateable: 0xa56fE82aEf25e197812207B27195E1FF1A3718ec,
                iRM_LAC_Updateable: 0xBCBF85EF1Fc65E2418996b4156364C65e45A1c65,
                iRM_WBTC_Updateable: 0xe27738534416F8554723B5B38372B497d1354497,
                iRM_USDT_Updateable: address(0),
                iRM_USDC_Updateable: address(0),
                iRM_MockCToken_Updateable: 0xf4EA71701758ef92Ea8224e926f01040684ae63e
            }),
            cTokens: Config.DeployedCTokens({
                caUXD: address(0),
                caWETH: address(0),
                caLAC: address(0),
                caWBTC: address(0),
                caUSDT: address(0),
                caUSDC: address(0),
                caMOCK: address(0)
            }),
            underlyingTokens: Config.DeployedUnderlyingTokens({
                // Sepolia testnet tokens
                uxd: address(0),
                weth: 0x8bBCf4f1F9ab907345a309083105D4aC9523Db53, 
                wbtc: 0x5FAFeB07B90BE13deEB074Fd39B944f83cAD9d79, 
                usdt: 0x509b30bc361BA6F0bAe8Fb0fE06904646853aa0A, 
                usdc: address(0),
                mockUnderlying: 0x06E71F26328A6096A01DB356DD104233a0dF6035,
                lac: address(0)
            }),
            account: address(0)
        });
    }

    /**
     * @notice Retrieves the cToken address based on the token symbol
     * @param config The network configuration containing cToken addresses
     * @param tokenSymbol The symbol of the token (e.g., "WETH", "UXD", etc.)
     * @return The address of the cToken corresponding to the given token symbol
     */
    function getCTokenAddressBySymbol(NetworkConfig memory config, string memory tokenSymbol) 
        public pure returns (address) 
    {
        bytes32 symbolHash = keccak256(abi.encodePacked(tokenSymbol));
        
        if (symbolHash == keccak256(abi.encodePacked("UXD"))) {
            return config.cTokens.caUXD;
        } else if (symbolHash == keccak256(abi.encodePacked("WETH"))) {
            return config.cTokens.caWETH;
        } else if (symbolHash == keccak256(abi.encodePacked("LAC"))) {
            return config.cTokens.caLAC;
        } else if (symbolHash == keccak256(abi.encodePacked("WBTC"))) {
            return config.cTokens.caWBTC;
        } else if (symbolHash == keccak256(abi.encodePacked("USDT"))) {
            return config.cTokens.caUSDT;
        } else if (symbolHash == keccak256(abi.encodePacked("USDC"))) {
            return config.cTokens.caUSDC;
        } else if (symbolHash == keccak256(abi.encodePacked("MOCK"))) {
            return config.cTokens.caMOCK;
        } else {
            return address(0);
        }
    }

    function getConfigBasedOnNetwork() public returns (Config config) {
           // Select appropriate config based on network
        if (block.chainid == 274 || block.chainid == 1 || block.chainid == 7400) { // Lachain mainnet or Ethereum mainnet or Forked Ethereum mainnet
            console.log("Using production config");
            config = new ProdConfig();
        } else {
            console.log("Using development/test config");
            config = new CustomConfig();
        }
        return config;
    }
}
