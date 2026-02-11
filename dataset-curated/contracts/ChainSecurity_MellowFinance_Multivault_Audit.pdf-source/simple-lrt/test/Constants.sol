// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

library Constants {
    bytes32 public constant SET_FARM_ROLE = keccak256("SET_FARM_ROLE");
    bytes32 public constant REMOVE_FARM_ROLE = keccak256("REMOVE_FARM_ROLE");
    bytes32 public constant SET_LIMIT_ROLE = keccak256("SET_LIMIT_ROLE");
    bytes32 public constant PAUSE_WITHDRAWALS_ROLE = keccak256("PAUSE_WITHDRAWALS_ROLE");
    bytes32 public constant UNPAUSE_WITHDRAWALS_ROLE = keccak256("UNPAUSE_WITHDRAWALS_ROLE");
    bytes32 public constant PAUSE_DEPOSITS_ROLE = keccak256("PAUSE_DEPOSITS_ROLE");
    bytes32 public constant UNPAUSE_DEPOSITS_ROLE = keccak256("UNPAUSE_DEPOSITS_ROLE");
    bytes32 public constant SET_DEPOSIT_WHITELIST_ROLE = keccak256("SET_DEPOSIT_WHITELIST_ROLE");
    bytes32 public constant SET_DEPOSITOR_WHITELIST_STATUS_ROLE =
        keccak256("SET_DEPOSITOR_WHITELIST_STATUS_ROLE");

    address public constant HOLESKY_EL_DELEGATION_MANAGER =
        0xA44151489861Fe9e3055d95adC98FbD462B948e7;
    address public constant HOLESKY_EL_STRATEGY_MANAGER = 0xdfB5f6CE42aAA7830E94ECFCcAd411beF4d4D5b6;
    address public constant HOLESKY_EL_REWARDS_COORDINATOR =
        0xAcc1fb458a1317E886dB376Fc8141540537E68fE;

    address public constant HOLESKY_WSTETH_SYMBIOTIC_COLLATERAL =
        0x23E98253F372Ee29910e22986fe75Bb287b011fC;
    address public constant HOLESKY_WSTETH = 0x8d09a4502Cc8Cf1547aD300E066060D043f6982D;

    address public constant MAINNET_WSTETH_SYMBIOTIC_COLLATERAL =
        0xC329400492c6ff2438472D4651Ad17389fCb843a;

    address public constant MAINNET_WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;

    address public constant HOLESKY_STETH = 0x3F1c547b21f65e10480dE3ad8E19fAAC46C95034;
    address public constant HOLESKY_WETH = 0x94373a4919B3240D86eA41593D5eBa789FEF3848;

    address public constant MAINNET_STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address public constant MAINNET_WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    // chain-specific helper functions

    function WSTETH() internal view returns (address) {
        if (block.chainid == 1) {
            return MAINNET_WSTETH;
        } else if (block.chainid == 17000) {
            return HOLESKY_WSTETH;
        } else {
            revert("Constants: unsupported chain");
        }
    }

    function STETH() internal view returns (address) {
        if (block.chainid == 1) {
            return MAINNET_STETH;
        } else if (block.chainid == 17000) {
            return HOLESKY_STETH;
        } else {
            revert("Constants: unsupported chain");
        }
    }

    function WETH() internal view returns (address) {
        if (block.chainid == 1) {
            return MAINNET_WETH;
        } else if (block.chainid == 17000) {
            return HOLESKY_WETH;
        } else {
            revert("Constants: unsupported chain");
        }
    }

    function WSTETH_SYMBIOTIC_COLLATERAL() internal view returns (address) {
        if (block.chainid == 1) {
            return MAINNET_WSTETH_SYMBIOTIC_COLLATERAL;
        } else if (block.chainid == 17000) {
            return HOLESKY_WSTETH_SYMBIOTIC_COLLATERAL;
        } else {
            revert("Constants: unsupported chain");
        }
    }

    struct SymbioticDeployment {
        address networkRegistry;
        address operatorRegistry;
        address vaultFactory;
        address delegatorFactory;
        address slasherFactory;
        address vaultConfigurator;
        address networkMiddlewareService;
        address operatorVaultOptInService;
        address operatorNetworkOptInService;
    }

    function symbioticDeployment() internal view returns (SymbioticDeployment memory) {
        if (block.chainid == 17000) {
            return SymbioticDeployment({
                networkRegistry: address(0x7d03b7343BF8d5cEC7C0C27ecE084a20113D15C9),
                operatorRegistry: address(0x6F75a4ffF97326A00e52662d82EA4FdE86a2C548),
                vaultFactory: address(0x407A039D94948484D356eFB765b3c74382A050B4),
                delegatorFactory: address(0x890CA3f95E0f40a79885B7400926544B2214B03f),
                slasherFactory: address(0xbf34bf75bb779c383267736c53a4ae86ac7bB299),
                vaultConfigurator: address(0xD2191FE92987171691d552C219b8caEf186eb9cA),
                networkMiddlewareService: address(0x62a1ddfD86b4c1636759d9286D3A0EC722D086e3),
                operatorVaultOptInService: address(0x95CC0a052ae33941877c9619835A233D21D57351),
                operatorNetworkOptInService: address(0x58973d16FFA900D11fC22e5e2B6840d9f7e13401)
            });
        } else if (block.chainid == 1) {
            revert("Not yet implemented");
        } else {
            revert("Unsupported chain");
        }
    }

    function testConstants() internal pure {}
}
