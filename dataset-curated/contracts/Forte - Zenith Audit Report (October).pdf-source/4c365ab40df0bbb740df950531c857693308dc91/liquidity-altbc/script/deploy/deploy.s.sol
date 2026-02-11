// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import "forge-std/console2.sol";
import {ALTBCFactory} from "src/factory/ALTBCFactory.sol";
import {ALTBCPool, IERC20} from "src/amm/ALTBCPool.sol";
import {ALTBCInput} from "src/amm/ALTBC.sol";
import {ExternalDeployments, FactoryDeployment, CommonPoolDeployment, Recorder, GenericERC20FixedSupply, GenericERC20, IFactory, PoolBase, TokenDeployment, WETHDeployment, allowlistsDeployment, LPTokenDeployment} from "lib/liquidity-base/script/deploy/deploy.s.sol";
import {LPToken, ILPToken} from "lib/liquidity-base/src/common/LPToken.sol";

/**
 * @title ALTBC Factory Deployment File
 * @dev a series of deployment scripts for tokens, whitelists, factories and pools.
 * @notice make sure you source the env file before running this script if you are using the command line
 * to run this script. DO NOT USE THE --private-key flag. Instead, SET THE "DEPLOYMENT_OWNER_KEY" env variable
 * and do a `source .env` in your terminal window before running the script.
 */
contract allowlistsDeploymentALTBC is allowlistsDeployment {}

contract TokenDeploymentALTBC is TokenDeployment {}

contract ALTBCCommonFactoryDeployment is FactoryDeployment {
    function deployALTBCFactory() internal returns (ALTBCFactory altbcFactory) {
        vm.startBroadcast(vm.envUint("DEPLOYMENT_OWNER_KEY"));
        altbcFactory = new ALTBCFactory(type(ALTBCPool).creationCode);
        vm.stopBroadcast();
        setENVAddress("ALTBC_FACTORY", vm.toString(address(altbcFactory)));
        console2.log("ALTBC_FACTORY", vm.toString(address(altbcFactory)));
    }

    function _deployFactory() internal override returns (IFactory factory) {
        factory = IFactory(deployALTBCFactory());
    }
}

contract ALTBCCommonLPTokenDeployment is LPTokenDeployment {
    function deployALTBCLPToken() internal returns (LPToken lpToken) {
        vm.startBroadcast(vm.envUint("DEPLOYMENT_OWNER_KEY"));

        lpToken = new LPToken(vm.envString("NAME"), vm.envString("SYMBOL"));
        vm.stopBroadcast();
        setENVAddress("LP_TOKEN_ADDRESS", vm.toString(address(lpToken)));
        console2.log("LP_TOKEN_ADDRESS", vm.toString(address(lpToken)));
    }
}

contract ALTBCFactoryDeployment is ALTBCCommonFactoryDeployment {
    function run() external {
        _deployFactory();
    }
}

contract ALTBCExternalContractsDeployment is ExternalDeployments {
    function run() external {
        deployExternalContracts(10e21);
    }
}

contract ALTBCFactoryDeploymentAndPrep is ALTBCCommonFactoryDeployment {
    function run() external {
        prepareForDeployment();
    }
}

contract ALTBCPoolDeployment is Recorder, CommonPoolDeployment {
    function _getTBCString() internal pure override returns (string memory) {
        return "ALTBC";
    }

    function run() external {
        ALTBCFactory factory = ALTBCFactory(vm.envAddress("ALTBC_FACTORY"));
        vm.startBroadcast(vm.envUint("DEPLOYMENT_OWNER_KEY"));

        console2.log("approving pool ");
        IERC20(vm.envAddress("XTOKEN_ADDRESS")).approve(address(factory), vm.envUint("XADD"));
        address poolAddress = factory.createPool(
            vm.envAddress("XTOKEN_ADDRESS"),
            vm.envAddress("YTOKEN_ADDRESS"),
            uint16(vm.envUint("LP_FEE_AMOUNT")),
            ALTBCInput(vm.envUint("LOWER_PRICE_AMOUNT"), vm.envUint("V"), vm.envUint("XMIN"), vm.envUint("C")),
            vm.envUint("XADD"),
            vm.envUint("XINACTIVE")
        );
        console2.log("pool created ", poolAddress);
        setENVAddress("POOL_CONTRACT", vm.toString(poolAddress));
        approvePool(poolAddress, vm.envAddress("XTOKEN_ADDRESS"), vm.envAddress("YTOKEN_ADDRESS"), vm.envAddress("DEPLOYMENT_OWNER"));
        vm.stopBroadcast();
        recordDeployment(address(factory), vm.envAddress("XTOKEN_ADDRESS"), vm.envAddress("YTOKEN_ADDRESS"), poolAddress);
    }
}
