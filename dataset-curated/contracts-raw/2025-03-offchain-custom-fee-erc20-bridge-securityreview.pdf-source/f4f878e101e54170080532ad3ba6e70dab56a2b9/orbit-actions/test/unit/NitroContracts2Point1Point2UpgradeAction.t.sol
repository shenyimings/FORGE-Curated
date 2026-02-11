// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "forge-std/Test.sol";

import {Bridge, IOwnable} from "@arbitrum/nitro-contracts-2.1.2/src/bridge/Bridge.sol";
import {
    ERC20Bridge as ERC20Bridge_2_1_2,
    IOwnable as IOwnable_2_1_2
} from "@arbitrum/nitro-contracts-2.1.2/src/bridge/ERC20Bridge.sol";
import {
    ERC20Bridge as ERC20Bridge_2_1_0,
    IOwnable as IOwnable_2_1_0
} from "@arbitrum/nitro-contracts-2.1.0/src/bridge/ERC20Bridge.sol";
import {
    ERC20Bridge as ERC20Bridge_1_3_0,
    IOwnable as IOwnable_1_3_0
} from "@arbitrum/nitro-contracts-1.3.0/src/bridge/ERC20Bridge.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {NitroContracts2Point1Point2UpgradeAction} from
    "../../contracts/parent-chain/contract-upgrades/NitroContracts2Point1Point2UpgradeAction.sol";
import {IUpgradeExecutor} from "@offchainlabs/upgrade-executor/src/IUpgradeExecutor.sol";
import {DeploymentHelpersScript} from "../../scripts/foundry/helper/DeploymentHelpers.s.sol";

interface IUpgradeExecutorExtended is IUpgradeExecutor {
    function initialize(address admin, address[] memory executors) external;
}

contract FakeToken {
    uint256 public decimals = 18;
}

contract NitroContracts2Point1Point2UpgradeActionTest is Test, DeploymentHelpersScript {
    IUpgradeExecutorExtended upgradeExecutor;

    address fakeToken;

    ProxyAdmin proxyAdmin;

    ERC20Bridge_2_1_2 newBridgeImpl;

    address ethBridge;
    address erc20Bridge_2_1_0;
    address erc20Bridge_1_3_0;

    NitroContracts2Point1Point2UpgradeAction action;

    address fakeRollup = 0x822F75d77182fa8Fc17232E511d3A2abf98c7907;

    function setUp() public {
        // deploy a proxy admin
        proxyAdmin = new ProxyAdmin();

        // deploy an upgrade executor
        address[] memory execs = new address[](1);
        execs[0] = address(this);
        upgradeExecutor = IUpgradeExecutorExtended(
            address(
                new TransparentUpgradeableProxy(
                    deployBytecodeFromJSON(
                        "/node_modules/@offchainlabs/upgrade-executor/build/contracts/src/UpgradeExecutor.sol/UpgradeExecutor.json"
                    ),
                    address(proxyAdmin),
                    ""
                )
            )
        );
        upgradeExecutor.initialize(address(this), execs);

        proxyAdmin.transferOwnership(address(upgradeExecutor));

        // deploy a fake token
        fakeToken = address(new FakeToken());

        // deploy ERC20Bridge v2.1.2 implementation
        newBridgeImpl = new ERC20Bridge_2_1_2();

        // deploy an ETH Bridge
        ethBridge = address(new TransparentUpgradeableProxy(address(new Bridge()), address(proxyAdmin), ""));
        Bridge(ethBridge).initialize(IOwnable(fakeRollup)); // pretend the test contract is the rollup

        // deploy an ERC20Bridge on v2.1.0
        erc20Bridge_2_1_0 =
            address(new TransparentUpgradeableProxy(address(new ERC20Bridge_2_1_0()), address(proxyAdmin), ""));
        ERC20Bridge_2_1_0(erc20Bridge_2_1_0).initialize(IOwnable_2_1_0(fakeRollup), fakeToken);

        // deploy an ERC20Bridge on v1.3.0
        erc20Bridge_1_3_0 =
            address(new TransparentUpgradeableProxy(address(new ERC20Bridge_1_3_0()), address(proxyAdmin), ""));
        ERC20Bridge_1_3_0(erc20Bridge_1_3_0).initialize(IOwnable_1_3_0(fakeRollup), fakeToken);

        // deploy the upgrade action
        action = new NitroContracts2Point1Point2UpgradeAction(address(newBridgeImpl));
    }

    function testShouldRevertOnEth() public {
        vm.expectRevert("NitroContracts2Point1Point2UpgradeAction: bridge is not an ERC20Bridge");
        upgradeExecutor.execute(address(action), abi.encodeCall(action.perform, (ethBridge, proxyAdmin)));
    }

    function testShouldRevertOnV2() public {
        vm.expectRevert("NitroContracts2Point1Point2UpgradeAction: bridge is not v1.x.x");
        upgradeExecutor.execute(address(action), abi.encodeCall(action.perform, (erc20Bridge_2_1_0, proxyAdmin)));
    }

    function testShouldUpgradeAndSetDecimals() public {
        upgradeExecutor.execute(address(action), abi.encodeCall(action.perform, (erc20Bridge_1_3_0, proxyAdmin)));

        assertEq(
            proxyAdmin.getProxyImplementation(TransparentUpgradeableProxy(payable(erc20Bridge_1_3_0))),
            address(newBridgeImpl)
        );
        assertEq(ERC20Bridge_2_1_2(address(erc20Bridge_1_3_0)).nativeTokenDecimals(), 18);
    }
}
