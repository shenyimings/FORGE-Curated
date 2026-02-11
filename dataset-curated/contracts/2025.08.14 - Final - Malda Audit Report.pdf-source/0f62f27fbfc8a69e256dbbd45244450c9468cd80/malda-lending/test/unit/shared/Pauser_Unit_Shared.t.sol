// SPDX-License-Identifier: BSL-1.1
pragma solidity =0.8.28;

import {IPauser} from "src/interfaces/IPauser.sol";

import {Pauser} from "src/pauser/Pauser.sol";
import {Base_Unit_Test} from "../../Base_Unit_Test.t.sol";
import {mErc20Host} from "src/mToken/host/mErc20Host.sol";
import {Risc0VerifierMock} from "../../mocks/Risc0VerifierMock.sol";
import {mTokenGateway} from "src/mToken/extension/mTokenGateway.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ZkVerifier} from "src/verifier/ZkVerifier.sol";

abstract contract Pauser_Unit_Shared is Base_Unit_Test {
    mErc20Host public mWethHost;
    mTokenGateway public mWethExtension;
    ZkVerifier public zkVerifier;

    Risc0VerifierMock public verifierMock;

    Pauser public pauser;

    function setUp() public virtual override {
        super.setUp();

        verifierMock = new Risc0VerifierMock();
        vm.label(address(verifierMock), "verifierMock");

        zkVerifier = new ZkVerifier(address(this), "0x123", address(verifierMock));
        vm.label(address(zkVerifier), "ZkVerifier contract");

        // Deploy mWethHost implementation and proxy
        mErc20Host implementation = new mErc20Host();
        bytes memory initData = abi.encodeWithSelector(
            mErc20Host.initialize.selector,
            address(weth),
            address(operator),
            address(interestModel),
            1e18,
            "Market WETH",
            "mWeth",
            18,
            payable(address(this)),
            address(zkVerifier),
            address(roles)
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        mWethHost = mErc20Host(address(proxy));
        vm.label(address(mWethHost), "mWethHost");

        // Deploy mWethExtension implementation and proxy
        mTokenGateway gatewayImpl = new mTokenGateway();
        bytes memory gatewayInitData = abi.encodeWithSelector(
            mTokenGateway.initialize.selector,
            payable(address(this)),
            address(weth),
            address(roles),
            address(zkVerifier)
        );
        ERC1967Proxy gatewayProxy = new ERC1967Proxy(address(gatewayImpl), gatewayInitData);
        mWethExtension = mTokenGateway(address(gatewayProxy));
        vm.label(address(mWethExtension), "mWethExtension");

        pauser = new Pauser(address(roles), address(operator), address(this));
    }
}
