// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import "../../lib/openzeppelin-contracts/contracts/utils/Strings.sol";
import "../../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {AllowList} from "src/allowList/AllowList.sol";
import {GenericERC20FixedSupply} from "src/example/ERC20/GenericERC20FixedSupply.sol";
import {GenericERC20} from "src/example/ERC20/GenericERC20.sol";
import {IFactory} from "../../src/factory/IFactory.sol";
import {PoolBase} from "src/amm/base/PoolBase.sol";
import {PythonUtils} from "./pythonUtils.s.sol";
import {SixDecimalERC20} from "src/example/ERC20/SixDecimalERC20.sol";
import {ExampleERC721URI} from "src/example/ERC721/ExampleERC721URI.sol";
import {Descriptor, SVGLinesPart1, SVGLinesPart2, SVGLinesPart3, SVG, HexStrings} from "src/common/NFTSVG.sol";

contract CommonDeployment is Script, PythonUtils {
    function _deployFactory() internal virtual returns (IFactory) {}

    function deployAllowLists() internal returns (AllowList yTokenAllowList, AllowList deployerAllowList) {
        yTokenAllowList = new AllowList();
        deployerAllowList = new AllowList();
        setENVAddress("Y_TOKEN_ALLOWLIST", vm.toString(address(yTokenAllowList)));
        setENVAddress("DEPLOYER_ALLOWLIST", vm.toString(address(deployerAllowList)));
        console2.log("Y_TOKEN_ALLOWLIST", vm.toString(address(yTokenAllowList)));
        console2.log("DEPLOYER_ALLOWLIST", vm.toString(address(deployerAllowList)));
    }

    // used for deploying a fresh batch of tokens
    function deployTokens(uint supply) internal returns (GenericERC20FixedSupply xToken, GenericERC20 yToken) {
        xToken = new GenericERC20FixedSupply("Test Token", "TST", supply);
        yToken = new GenericERC20("collateral token", "COLL");
        address _owner = vm.envAddress("DEPLOYMENT_OWNER");
        yToken.mint(_owner, supply);
        setENVAddress("XTOKEN_ADDRESS", vm.toString(address(xToken)));
        setENVAddress("YTOKEN_ADDRESS", vm.toString(address(yToken)));
        console2.log("xToken", address(xToken));
        console2.log("yToken", address(yToken));
        require(yToken.totalSupply() == supply, "yToken supply is not equal to the supply passed to the function");
        require(xToken.totalSupply() == supply, "xToken supply is not equal to the supply passed to the function");
        require(yToken.owner() == _owner, "yToken owner is not the owner passed to the function");
        require(yToken.balanceOf(_owner) == supply, "yToken balance of the owner is not equal to the supply passed to the function");
        require(xToken.balanceOf(_owner) == supply, "xToken balance of the owner is not equal to the supply passed to the function");
        console2.log("Test Token (TST):", address(xToken), "\n collateral token (COLL):", address(yToken));
    }

    function deployXToken(uint supply) internal returns (GenericERC20FixedSupply xToken) {
        xToken = new GenericERC20FixedSupply("Test Token", "TST", supply);
        setENVAddress("XTOKEN_ADDRESS", vm.toString(address(xToken)));
        require(xToken.totalSupply() == supply, "xToken supply is not equal to the supply passed to the function");
        require(xToken.balanceOf(vm.envAddress("DEPLOYMENT_OWNER")) == supply, "xToken balance of the owner is not equal to the supply passed to the function");
        console2.log("Test Token (TST):", address(xToken));
    }

    function deployWETH(uint supply) internal returns (GenericERC20 weth) {
        weth = new GenericERC20("Wrapped Ether", "WETH");
        weth.mint(vm.envAddress("DEPLOYMENT_OWNER"), supply);
        setENVAddress("YTOKEN_ADDRESS", vm.toString(address(weth)));
        setENVAddress("WETH_ADDRESS", vm.toString(address(weth)));
        require(weth.totalSupply() == supply, "weth supply is not equal to the supply passed to the function");
        require(weth.balanceOf(vm.envAddress("DEPLOYMENT_OWNER")) == supply, "weth balance of the owner is not equal to the supply passed to the function");
        console2.log("Wrapped Ether (WETH):", address(weth));
    }

    function deployStableCoin(uint supply) internal returns (SixDecimalERC20 stableCoin) {
        stableCoin = new SixDecimalERC20("Stable Coin", "STC");
        stableCoin.mint(vm.envAddress("DEPLOYMENT_OWNER"), supply);
        setENVAddress("YTOKEN_ADDRESS", vm.toString(address(stableCoin)));
        setENVAddress("STC_ADDRESS", vm.toString(address(stableCoin)));
        require(stableCoin.totalSupply() == supply, "stableCoin supply is not equal to the supply passed to the function");
        require(stableCoin.balanceOf(vm.envAddress("DEPLOYMENT_OWNER")) == supply, "stableCoin balance of the owner is not equal to the supply passed to the function");
        console2.log("Stable Coin (STC):", address(stableCoin));
    }

    function deployERC721() internal returns (ExampleERC721URI) {
        ExampleERC721URI erc721 = new ExampleERC721URI("Example ERC721", "ERC721");
        setENVAddress("ERC721_ADDRESS", vm.toString(address(erc721)));
        console2.log("Example ERC721 (ERC721):", address(erc721));
        erc721.mint(vm.envAddress("DEPLOYMENT_OWNER"));
        return erc721;
    }

    function setProtocolFeeCollector(IFactory factory, address _protocolFeeCollector, uint feeCollectorFee) internal {
        factory.proposeProtocolFeeCollector(_protocolFeeCollector);
        vm.stopBroadcast();
        vm.startBroadcast(feeCollectorFee);
        factory.confirmProtocolFeeCollector();
        vm.stopBroadcast();
    }
}

contract allowlistsDeployment is CommonDeployment {
    function run() external {
        uint256 privateKey = vm.envUint("DEPLOYMENT_OWNER_KEY");
        vm.startBroadcast(privateKey);
        deployAllowLists();
        vm.stopBroadcast();
    }
}

contract TokenDeployment is CommonDeployment {
    function run() external {
        vm.startBroadcast(vm.envUint("DEPLOYMENT_OWNER_KEY"));
        deployTokens(10e21);
        vm.stopBroadcast();
    }
}

contract WETHDeployment is CommonDeployment {
    function run() external {
        vm.startBroadcast(vm.envUint("DEPLOYMENT_OWNER_KEY"));
        deployWETH(10e18);
        vm.stopBroadcast();
    }
}

contract StableCoinDeployment is CommonDeployment {
    function run() external {
        vm.startBroadcast(vm.envUint("DEPLOYMENT_OWNER_KEY"));
        deployStableCoin(10e21);
        vm.stopBroadcast();
    }
}

contract XTokenDeployment is CommonDeployment {
    function run() external {
        vm.startBroadcast(vm.envUint("DEPLOYMENT_OWNER_KEY"));
        deployTokens(10e21);
        vm.stopBroadcast();
    }
}

contract ERC721Deployment is CommonDeployment {
    function run() external {
        vm.startBroadcast(vm.envUint("DEPLOYMENT_OWNER_KEY"));
        deployERC721();
        vm.stopBroadcast();
    }
}


contract CommonConfigDeployment is CommonDeployment {

    IFactory _factory;

    function prepareForDeployment() internal {
        if (address(_factory) == address(0)) {
            _factory = _deployFactory();
        }
        vm.startBroadcast(vm.envUint("DEPLOYMENT_OWNER_KEY"));
        uint size;
        address factoryAddress = address(_factory);
        assembly {
            size := extcodesize(factoryAddress)
        }
        require(size > 0, "FACTORY is not a deployed contract, try deploying the factory with deploy.s.sol:ALTBCFactoryDeployment or deploy.s.sol:URQTBCFactoryDeployment");
        {
            address yToken = vm.envAddress("YTOKEN_ADDRESS");
            assembly {
                size := extcodesize(yToken)
            }
            require(size > 0, "YTOKEN_ADDRESS is not a deployed contract, try deploying the tokens with deploy.s.sol:TokenDeployment");
            address yTokenAllowList = vm.envAddress("Y_TOKEN_ALLOWLIST");
            assembly {
                size := extcodesize(yTokenAllowList)
            }
            require(size > 0, "Y_TOKEN_ALLOWLIST is not a deployed contract, try deploying the allow lists with deploy.s.sol:allowlistsDeployment");
            address deployerAllowList = vm.envAddress("DEPLOYER_ALLOWLIST");
            assembly {
                size := extcodesize(deployerAllowList)
            }
            require(size > 0, "DEPLOYER_ALLOWLIST is not a deployed contract, try deploying the allow lists with deploy.s.sol:allowlistsDeployment");
            AllowList(yTokenAllowList).addToAllowList(vm.envAddress("YTOKEN_ADDRESS"));
            AllowList(deployerAllowList).addToAllowList(vm.envAddress("DEPLOYMENT_OWNER"));
        }
        {
            _factory.setYTokenAllowList(vm.envAddress("Y_TOKEN_ALLOWLIST"));
            _factory.setDeployerAllowList(vm.envAddress("DEPLOYER_ALLOWLIST"));
        }
        {
            _factory.proposeProtocolFeeCollector(vm.envAddress("FEE_COLLECTOR"));
            _factory.setProtocolFee(uint16(vm.envUint("PROTOCOL_FEE_AMOUNT")));
        }
        {
            setProtocolFeeCollector(_factory, vm.envAddress("FEE_COLLECTOR"), uint256(vm.envUint("FEE_COLLECTOR_KEY")));
            vm.startBroadcast(vm.envUint("DEPLOYMENT_OWNER_KEY"));
        }
    }
}

abstract contract Recorder is Script {
    using Strings for uint256;
    using Strings for address;

    function _getTBCString() internal view virtual returns (string memory) {}

    function recordDeployment(address factory, address tokenX, address tokenY, address poolAddress) internal {
        string memory record = "deployment";
        {
            vm.serializeString(record, "poolType", _getTBCString());
            vm.serializeString(record, "factory", factory.toHexString());
            vm.serializeString(record, "issuanceToken", tokenX.toHexString());
            vm.serializeString(record, "collateralToken", tokenY.toHexString());
            vm.serializeString(record, "pool", poolAddress.toHexString());
        }
        {
            console.log("---------------RECORDS---------------");
            string memory firstMsg = string.concat(
                string.concat(
                    string.concat(string.concat("recorded items at ./deploymentRecords/", vm.toString(block.chainid)), "/"),
                    vm.toString(block.timestamp)
                ),
                "_deploymentRecord.json"
            );
            console.log(firstMsg);
            console.log("poolType:", _getTBCString());
            console.log("factory:", factory.toHexString());
            console.log("issuanceToken:", tokenX.toHexString());
            console.log("collateralToken:", tokenY.toHexString());
            console.log("pool:", poolAddress.toHexString());
        }
        string memory recordJson = vm.serializeUint(record, "chainId", block.chainid);
        string[] memory makePath = new string[](3);
        makePath[0] = "mkdir";
        makePath[1] = "-p";
        makePath[2] = string.concat("deploymentRecords/", vm.toString(block.chainid), "/", vm.toString(block.timestamp));
        vm.ffi(makePath);

        string memory path = string.concat(
            "deploymentRecords/",
            vm.toString(block.chainid),
            "/",
            vm.toString(block.timestamp),
            "_deploymentRecord.json"
        );
        vm.writeJson(recordJson, path);
    }
}

contract PoolDeploymentCommon is CommonDeployment {
    function prepareForDeployment() internal returns (IFactory factory, GenericERC20FixedSupply xToken, GenericERC20 yToken) {
        vm.startBroadcast(vm.envUint("DEPLOYMENT_OWNER_KEY"));
        (xToken, yToken) = deployTokens(10e21);
        (AllowList yTokenAllowList, AllowList deployerAllowList) = deployAllowLists();
        factory = _deployFactory();
        // TODO fix this hack for getting deployer account
        address deployerAddress = vm.envAddress("DEPLOYMENT_OWNER");
        console.log(deployerAddress);
        {
            yTokenAllowList.addToAllowList(address(yToken));
            deployerAllowList.addToAllowList(deployerAddress);
            factory.setYTokenAllowList(address(yTokenAllowList));
            factory.setDeployerAllowList(address(deployerAllowList));
            factory.setProtocolFee(uint16(vm.envUint("PROTOCOL_FEE_AMOUNT")));
            setProtocolFeeCollector(factory, vm.envAddress("FEE_COLLECTOR"), uint256(vm.envUint("FEE_COLLECTOR_KEY")));
        }
        vm.startBroadcast(vm.envUint("DEPLOYMENT_OWNER_KEY"));
    }
}

contract PoolConfigDeploymentCommon is CommonDeployment, Recorder {

    function initializePool(address poolAddress, address xTokenAddress, address yTokenAddress, address ownerAddress) internal {
        IERC20 tokenX = IERC20(xTokenAddress);
        {
            IERC20 tokenY = IERC20(yTokenAddress);
            tokenX.approve(poolAddress, tokenX.totalSupply());
            tokenX.approve(ownerAddress, tokenX.totalSupply());
            tokenY.approve(poolAddress, tokenX.totalSupply());
            tokenY.approve(ownerAddress, tokenX.totalSupply());
        }
        {
            PoolBase pool = PoolBase(poolAddress);
            setENVAddress("POOL_CONTRACT", vm.toString(address(pool)));
        }
    }
}
