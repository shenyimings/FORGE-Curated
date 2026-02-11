// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19;

contract IContractAddresses {
    struct LevelContracts {
        address lvlUSD;
        address slvlUSD;
        address levelMinting;
        address levelAdmin;
        address levelDeployer;
        address levelPauser;
        address levelTreasuryReceiver;
        address levelOperator;
        address levelDev;
        address eigenlayerReserveManager;
        address karakReserveManager;
        address aaveV3YieldManager;
        address symbioticReserveManager;
    }

    struct EigenlayerContracts {
        address eigenlayerDelegationManager;
        address eigenlayerStrategyManager;
        address eigenlayerStrategyFactory;
        address eigenlayerRewardsCoordinator;
    }

    struct AaveContracts {
        address aavePoolProxy;
        address aaveUsdc;
        address aaveUsdt;
    }

    struct TokenContracts {
        address usdc;
        address usdt;
        address waUsdc;
        address waUsdt;
    }
}

// deploy Eigenlayer LRM to Holesky testnet
contract ContractAddresses is IContractAddresses {
    LevelContracts public levelContracts;
    EigenlayerContracts public eigenlayerContracts;
    AaveContracts public aaveContracts;
    TokenContracts public tokenContracts;

    //------------------------------------ Mainnet addresses -------------------------------------------------------
    address public constant MAINNET_LVLUSD = 0x7C1156E515aA1A2E851674120074968C905aAF37;
    address public constant MAINNET_LEVEL_MINTING = 0x8E7046e27D14d09bdacDE9260ff7c8c2be68a41f;
    address public constant MAINNET_SLVLUSD = 0x4737D9b4592B40d51e110b94c9C043c6654067Ae;

    address public constant MAINNET_LEVEL_ADMIN = 0x343ACce723339D5A417411D8Ff57fde8886E91dc;
    address public constant MAINNET_LEVEL_DEPLOYER = 0x5b5004f1bC12C66F94782070032a6eAdC6821a3e;
    address public constant MAINNET_LEVEL_OPERATOR = 0xcEa14C3e9Afc5822d44ADe8d006fCFBAb60f7a21;
    address public constant MAINNET_LEVEL_TREASURY_RECEIVER = 0xcEa14C3e9Afc5822d44ADe8d006fCFBAb60f7a21;
    address public constant MAINNET_LEVEL_PAUSER = 0xe9AF0428143E4509df4379Bd10C4850b223F2EcB;
    address public constant MAINNET_LEVEL_DEV = 0xe9AF0428143E4509df4379Bd10C4850b223F2EcB;

    address public constant MAINNET_LEVEL_EIGENLAYER_RESERVE_MANAGER = 0x7B2c2C905184CEf1FABe920D4CbEA525acAa6f14;
    address public constant MAINNET_LEVEL_SYMBIOTIC_RESERVE_MANAGER = 0x21C937d436f2D86859ce60311290a8072368932D;
    address public constant MAINNET_LEVEL_KARAK_RESERVE_MANAGER = 0x329F91FE82c1799C3e089FabE9D3A7efDC2D3151;
    address public constant MAINNET_LEVEL_AAVE_V3_YIELD_MANAGER = 0x9df5680D8Dc866aD154Dc07A7Dc1c418dC60C96C;

    address public constant MAINNET_EIGENLAYER_DELEGATION_MANAGER = 0x39053D51B77DC0d36036Fc1fCc8Cb819df8Ef37A;
    address public constant MAINNET_EIGENLAYER_STRATEGY_MANAGER = 0x858646372CC42E1A627fcE94aa7A7033e7CF075A;
    address public constant MAINNET_EIGENLAYER_STRATEGY_FACTORY = 0x5e4C39Ad7A3E881585e383dB9827EB4811f6F647;
    address public constant MAINNET_EIGENLAYER_REWARDS_COORDINATOR = 0x7750d328b314EfFa365A0402CcfD489B80B0adda;

    address public constant MAINNET_WAUSDC_EIGENLAYER_STRATEGY = 0x82A2e702C4CeCA35D8c474e218eD6f0852827380;
    address public constant MAINNET_WAUSDT_EIGENLAYER_STRATEGY = 0x38fb62B973e4515a2A2A8B819a3B2217101Ad691;

    address public constant MAINNET_AAVE_POOL_PROXY = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;
    address public constant MAINNET_AAVE_USDC = 0x98C23E9d8f34FEFb1B7BD6a91B7FF122F4e16F5c;
    address public constant MAINNET_AAVE_USDT = 0x23878914EFE38d27C4D67Ab83ed1b93A74D4086a;

    address public constant MAINNET_USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant MAINNET_USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address public constant MAINNET_WAUSDC = 0x78c6B27Be6DB520d332b1b44323F94bC831F5e33;
    address public constant MAINNET_WAUSDT = 0xb723377679b807370Ae8615ae3E76F6D1E75a5F2;

    address public constant MAINNET_HEXAGATE_GATEKEEPER_1 = 0xA7367eCE6AeA6EA5D775867Aa9B56F5f35B202Fe;
    address public constant MAINNET_HEXAGATE_GATEKEEPER_2 = 0x1557C8a68110D17cf19Bd7451972ea954B689ed6;

    address public constant MAINNET_LEVEL_RESERVE_LENS_PROXY = 0xd7f68a32E4bdd4908bDD1daa03bDd04581De80Ff;
    address public constant MAINNET_LEVEL_RESERVE_LENS_IMPLEMENTATION = 0xf2b94ccF1Bf8F51e1CB0dCFef74b7134a49d22b6;

    address public constant MAINNET_SYMBIOTIC_WAUSDC_BURNER_ROUTER = 0xdeD54FD22FeBf6095dA66f3c8d25c9FFB1daD3B1;
    address public constant MAINNET_SYMBIOTIC_WAUSDC_VAULT = 0x67F91a36c5287709E68E3420cd17dd5B13c60D6d;
    address public constant MAINNET_SYMBIOTIC_WAUSDC_DELEGATOR = 0x356e7658390AF3ABA15C50583572D8B6C0653Fc9;
    address public constant MAINNET_SYMBIOTIC_WAUSDC_SLASHER = 0x9A8F128B2F20fF7f474A58558Cb24D2Cc02cd5bf;

    address public constant MAINNET_SYMBIOTIC_WAUSDT_BURNER_ROUTER = 0xAbc36850D45CC69BA2EFC30294dAb8dd88296a0b;
    address public constant MAINNET_SYMBIOTIC_WAUSDT_VAULT = 0x9BF93077Ad7BB7f43E177b6AbBf8Dae914761599;
    address public constant MAINNET_SYMBIOTIC_WAUSDT_DELEGATOR = 0x866AD11507926c0cb8Fe96E871ade61788352B6e;
    address public constant MAINNET_SYMBIOTIC_WAUSDT_SLASHER = 0x04856C082a9f27Fc62e89436a1bA81379e65f714;

    //------------------------------------ Holesky addresses -------------------------------------------------------
    address public constant HOLESKY_LVLUSD = 0x96829CBCd28B74E096c511Ad0528b2F7F07Da982;
    address public constant HOLESKY_LEVEL_MINTING = 0x8D841142bE8A99DCB53eAcaB05d40Ca70ec9600a;
    address public constant HOLESKY_SLVLUSD = 0xb3d0002515C558546180aE3067a9f64868b7a569;

    address public constant HOLESKY_LEVEL_EIGENLAYER_RESERVE_MANAGER = 0x9C18db0640dC08C246CF9a4Ab361ae7e7358Bfa4;
    address public constant HOLESKY_LEVEL_AAVE_V3_YIELD_MANAGER = 0x9f0cc48577563596CEB558088051519655F460cA;

    address public constant HOLESKY_LEVEL_ADMIN = 0x74C3dC2F48b9cc5f167B0C8AE09FbbDc6315f519;
    address public constant HOLESKY_LEVEL_DEPLOYER = 0x74C3dC2F48b9cc5f167B0C8AE09FbbDc6315f519;
    address public constant HOLESKY_LEVEL_OPERATOR = 0x74C3dC2F48b9cc5f167B0C8AE09FbbDc6315f519;
    address public constant HOLESKY_LEVEL_TREASURY_RECEIVER = 0x74C3dC2F48b9cc5f167B0C8AE09FbbDc6315f519;
    address public constant HOLESKY_LEVEL_PAUSER = 0x74C3dC2F48b9cc5f167B0C8AE09FbbDc6315f519;
    address public constant HOLESKY_LEVEL_DEV = 0xe9AF0428143E4509df4379Bd10C4850b223F2EcB;

    address public constant HOLESKY_EIGENLAYER_DELEGATION_MANAGER = 0xA44151489861Fe9e3055d95adC98FbD462B948e7;
    address public constant HOLESKY_EIGENLAYER_STRATEGY_MANAGER = 0xdfB5f6CE42aAA7830E94ECFCcAd411beF4d4D5b6;
    address public constant HOLESKY_EIGENLAYER_STRATEGY_FACTORY = 0x9c01252B580efD11a05C00Aa42Dd3ac1Ec52DF6d;
    address public constant HOLESKY_EIGENLAYER_REWARDS_COORDINATOR = 0xAcc1fb458a1317E886dB376Fc8141540537E68fE;

    address public constant HOLESKY_AAVE_POOL_PROXY = 0xDCd2ebca2f5F2EDD9C4FE246f5fded0b503a023a;
    address public constant HOLESKY_AAVE_USDC = 0xAc8504aF7B2fdA5B819b1D12F4aa95c90c813E69;
    address public constant HOLESKY_AAVE_USDT = 0x3b6358909CD9C010Cbb856D5c158bF1354b9DA22;

    address public constant HOLESKY_USDC = 0x508991e1B38287616778E95e59135EF040f559fb;
    address public constant HOLESKY_USDT = 0x28e527F5EEB632a8e62dDBfcF832FAF867E55Cc8;

    address public constant HOLESKY_WAUSDC = 0xD2b88b4bADe4E83e9FF2f7385556E0205561CC48;
    address public constant HOLESKY_WAUSDT = 0x2838ade44B884ca6813c1DaCB7B4C9D747cE7F64;

    function _initializeAddresses(uint256 chainId) internal {
        _initializeLevelContractAddresses(chainId);
        _initializeEigenlayerContractAddresses(chainId);
        _initializeAaveContractAddresses(chainId);
        _initializeTokenContractAddresses(chainId);
    }

    function _initializeLevelContractAddresses(uint256 chainId) internal {
        if (chainId == 1) {
            levelContracts.lvlUSD = MAINNET_LVLUSD;
            levelContracts.levelMinting = MAINNET_LEVEL_MINTING;
            levelContracts.levelAdmin = MAINNET_LEVEL_ADMIN;
            levelContracts.levelDeployer = MAINNET_LEVEL_DEPLOYER;
            levelContracts.levelDev = MAINNET_LEVEL_DEV;
            levelContracts.levelOperator = MAINNET_LEVEL_OPERATOR;
            levelContracts.levelTreasuryReceiver = MAINNET_LEVEL_TREASURY_RECEIVER;
            levelContracts.levelPauser = MAINNET_LEVEL_PAUSER;
            levelContracts.eigenlayerReserveManager = MAINNET_LEVEL_EIGENLAYER_RESERVE_MANAGER;
            levelContracts.symbioticReserveManager = MAINNET_LEVEL_SYMBIOTIC_RESERVE_MANAGER;
            levelContracts.karakReserveManager = MAINNET_LEVEL_KARAK_RESERVE_MANAGER;
            levelContracts.aaveV3YieldManager = MAINNET_LEVEL_AAVE_V3_YIELD_MANAGER;
        } else if (chainId == 17000) {
            levelContracts.lvlUSD = HOLESKY_LVLUSD;
            levelContracts.levelMinting = HOLESKY_LEVEL_MINTING;
            levelContracts.slvlUSD = HOLESKY_SLVLUSD;
            levelContracts.levelAdmin = HOLESKY_LEVEL_ADMIN;
            levelContracts.levelDeployer = HOLESKY_LEVEL_ADMIN;
            levelContracts.levelOperator = HOLESKY_LEVEL_OPERATOR;
            levelContracts.levelTreasuryReceiver = HOLESKY_LEVEL_TREASURY_RECEIVER;
            levelContracts.levelPauser = HOLESKY_LEVEL_PAUSER;
            levelContracts.levelDev = HOLESKY_LEVEL_DEV;
            levelContracts.eigenlayerReserveManager = HOLESKY_LEVEL_EIGENLAYER_RESERVE_MANAGER;
            levelContracts.aaveV3YieldManager = HOLESKY_LEVEL_AAVE_V3_YIELD_MANAGER;
        }
    }

    function _initializeEigenlayerContractAddresses(uint256 chainId) internal {
        if (chainId == 1) {
            eigenlayerContracts.eigenlayerDelegationManager = MAINNET_EIGENLAYER_DELEGATION_MANAGER;
            eigenlayerContracts.eigenlayerStrategyManager = MAINNET_EIGENLAYER_STRATEGY_MANAGER;
            eigenlayerContracts.eigenlayerStrategyFactory = MAINNET_EIGENLAYER_STRATEGY_FACTORY;
            eigenlayerContracts.eigenlayerRewardsCoordinator = MAINNET_EIGENLAYER_REWARDS_COORDINATOR;
        } else if (chainId == 17000) {
            eigenlayerContracts.eigenlayerDelegationManager = HOLESKY_EIGENLAYER_DELEGATION_MANAGER;
            eigenlayerContracts.eigenlayerStrategyManager = HOLESKY_EIGENLAYER_STRATEGY_MANAGER;
            eigenlayerContracts.eigenlayerStrategyFactory = HOLESKY_EIGENLAYER_STRATEGY_FACTORY;
            eigenlayerContracts.eigenlayerRewardsCoordinator = HOLESKY_EIGENLAYER_REWARDS_COORDINATOR;
        }
    }

    function _initializeAaveContractAddresses(uint256 chainId) internal {
        if (chainId == 1) {
            aaveContracts.aavePoolProxy = MAINNET_AAVE_POOL_PROXY;
            aaveContracts.aaveUsdc = MAINNET_AAVE_USDC;
            aaveContracts.aaveUsdt = MAINNET_AAVE_USDT;
        } else if (chainId == 17000) {
            aaveContracts.aavePoolProxy = HOLESKY_AAVE_POOL_PROXY;
            aaveContracts.aaveUsdc = HOLESKY_AAVE_USDC;
            aaveContracts.aaveUsdt = HOLESKY_AAVE_USDT;
        }
    }

    function _initializeTokenContractAddresses(uint256 chainId) internal {
        if (chainId == 1) {
            tokenContracts.usdc = MAINNET_USDC;
            tokenContracts.usdt = MAINNET_USDT;
        } else if (chainId == 17000) {
            tokenContracts.usdc = HOLESKY_USDC;
            tokenContracts.usdt = HOLESKY_USDT;

            tokenContracts.waUsdc = HOLESKY_WAUSDC;
            tokenContracts.waUsdt = HOLESKY_WAUSDT;
        }
    }
}
