// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/console2.sol";
import {ALTBCFactory} from "src/factory/ALTBCFactory.sol";
import {ALTBCPool, IERC20} from "src/amm/ALTBCPool.sol";
import {ALTBCInput} from "src/amm/ALTBC.sol";
import {CommonDeployment, CommonConfigDeployment, Recorder, PoolDeploymentCommon, PoolConfigDeploymentCommon, GenericERC20FixedSupply, GenericERC20, IFactory, PoolBase, XTokenDeployment, WETHDeployment, allowlistsDeployment} from "lib/liquidity-base/script/deploy/deploy.s.sol";

contract allowlistsDeploymentALTBC is allowlistsDeployment {}

contract XTokenDeploymentALTBC is XTokenDeployment {}

contract WETHDeploymentALTBC is WETHDeployment {}

contract ALTBCCommonDeployment is CommonDeployment {
    function deployALTBCFactory() internal returns (ALTBCFactory altbcFactory) {
        altbcFactory = new ALTBCFactory(type(ALTBCPool).creationCode);
        setENVAddress("ALTBC_FACTORY", vm.toString(address(altbcFactory)));
        console2.log("ALTBC_FACTORY", vm.toString(address(altbcFactory)));
    }
}

contract ALTBCFactoryDeployment is ALTBCCommonDeployment {
    function run() external {
        uint256 privateKey = vm.envUint("DEPLOYMENT_OWNER_KEY");
        vm.startBroadcast(privateKey);
        deployALTBCFactory();
        vm.stopBroadcast();
    }
}

contract ALTBCDeploymentConfig is CommonConfigDeployment, ALTBCCommonDeployment {
    function _deployFactory() internal override returns (IFactory factory) {
        factory = IFactory(deployALTBCFactory());
    }

    function run() external {
        uint256 privateKey = vm.envUint("DEPLOYMENT_OWNER_KEY");
        vm.startBroadcast(privateKey);
        _factory = deployALTBCFactory();
        vm.stopBroadcast();
        prepareForDeployment();
        vm.stopBroadcast();
    }
}

contract ALTBCPoolDeployment is PoolDeploymentCommon, Recorder {
    function run() external {
        ALTBCInput memory tbcInput = ALTBCInput(
            vm.envUint("LOWER_PRICE_AMOUNT"),
            vm.envUint("XINACTIVE"),
            vm.envUint("V"),
            vm.envUint("XMIN"),
            vm.envUint("C")
        );
        (IFactory _factory, GenericERC20FixedSupply xToken, GenericERC20 yToken) = prepareForDeployment();
        address factory = address(_factory);
        IERC20(address(xToken)).approve(factory, vm.envUint("XADD"));
        address poolAddress = ALTBCFactory(factory).createPool(
            address(xToken),
            address(yToken),
            0,
            tbcInput,
            vm.envUint("XADD"),
            vm.envString("NAME"),
            vm.envString("SYMBOL")
        );
        vm.stopBroadcast();
        recordDeployment(factory, address(xToken), address(yToken), poolAddress);
    }
}

contract ALTBCPoolConfigDeployment is Recorder, PoolConfigDeploymentCommon {
    function _getTBCString() internal pure override returns (string memory) {
        return "ALTBC";
    }

    function run() external {
        ALTBCFactory factory = ALTBCFactory(vm.envAddress("ALTBC_FACTORY"));
        vm.startBroadcast(vm.envUint("DEPLOYMENT_OWNER_KEY"));
        IERC20(vm.envAddress("XTOKEN_ADDRESS")).approve(address(factory), vm.envUint("XADD"));
        address poolAddress = factory.createPool(
            vm.envAddress("XTOKEN_ADDRESS"),
            vm.envAddress("YTOKEN_ADDRESS"),
            uint16(vm.envUint("LP_FEE_AMOUNT")),
            ALTBCInput(vm.envUint("LOWER_PRICE_AMOUNT"), vm.envUint("XINACTIVE"), vm.envUint("V"), vm.envUint("XMIN"), vm.envUint("C")),
            vm.envUint("XADD"),
            vm.envString("NAME"),
            vm.envString("SYMBOL")
        );
        initializePool(poolAddress, vm.envAddress("XTOKEN_ADDRESS"), vm.envAddress("YTOKEN_ADDRESS"), vm.envAddress("DEPLOYMENT_OWNER"));
        vm.stopBroadcast();
        recordDeployment(address(factory), vm.envAddress("XTOKEN_ADDRESS"), vm.envAddress("YTOKEN_ADDRESS"), poolAddress);
    }
}
