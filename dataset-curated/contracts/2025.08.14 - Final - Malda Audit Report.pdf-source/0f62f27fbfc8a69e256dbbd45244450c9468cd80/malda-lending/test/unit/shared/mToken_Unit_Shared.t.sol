// SPDX-License-Identifier: BSL-1.1
pragma solidity =0.8.28;

//interfaces
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

//contracts
import {mErc20Host} from "src/mToken/host/mErc20Host.sol";
import {mErc20Immutable} from "src/mToken/mErc20Immutable.sol";
import {ImTokenOperationTypes} from "src/interfaces/ImToken.sol";
import {mTokenGateway} from "src/mToken/extension/mTokenGateway.sol";
import {BatchSubmitter} from "src/mToken/BatchSubmitter.sol";
import {ZkVerifier} from "src/verifier/ZkVerifier.sol";

import {Base_Unit_Test} from "../../Base_Unit_Test.t.sol";

import {ERC20Mock} from "../../mocks/ERC20Mock.sol";
import {Risc0VerifierMock} from "../../mocks/Risc0VerifierMock.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {console} from "forge-std/console.sol";
abstract contract mToken_Unit_Shared is Base_Unit_Test {
    // ----------- STORAGE ------------
    mErc20Host public mWethHost;
    mErc20Host public mDaiHost;
    mErc20Immutable public mWeth;
    mTokenGateway public mWethExtension;
    BatchSubmitter public batchSubmitter;
    ZkVerifier public zkVerifier;

    Risc0VerifierMock public verifierMock;

    struct Commitment {
        uint256 id;
        bytes32 digest;
        bytes32 configID;
    }

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

        // Deploy mDaiHost proxy
        bytes memory initDataDai = abi.encodeWithSelector(
            mErc20Host.initialize.selector,
            address(dai),
            address(operator),
            address(interestModel),
            1e18,
            "Market DAI",
            "mDai",
            18,
            payable(address(this)),
            address(zkVerifier),
            address(roles)
        );
        ERC1967Proxy proxyDai = new ERC1967Proxy(address(implementation), initDataDai);
        mDaiHost = mErc20Host(address(proxyDai));
        vm.label(address(mDaiHost), "mDaiHost");

        // Deploy mWeth (non-proxy)
        mWeth = new mErc20Immutable(
            address(weth),
            address(operator),
            address(interestModel),
            1e18,
            "Market WETH",
            "mWeth",
            18,
            payable(address(this))
        );
        vm.label(address(mWeth), "mWeth");

        // Deploy mWethExtension implementation and proxy
        mTokenGateway gatewayImpl = new mTokenGateway();
        bytes memory wethGatewayInitData = abi.encodeWithSelector(
            mTokenGateway.initialize.selector,
            payable(address(this)),
            address(weth),
            address(roles),
            address(zkVerifier)
        );
        ERC1967Proxy wethGatewayProxy = new ERC1967Proxy(address(gatewayImpl), wethGatewayInitData);
        mWethExtension = mTokenGateway(address(wethGatewayProxy));
        vm.label(address(mWethExtension), "mWethExtension");

        batchSubmitter = new BatchSubmitter(address(roles), address(verifierMock), address(this));
        vm.label(address(batchSubmitter), "BatchSubmitter");
        roles.allowFor(address(batchSubmitter), roles.PROOF_BATCH_FORWARDER(), true);
    }
    // ----------- HELPERS ------------

    function _createAccumulatedAmountJournal(address sender, address market, uint256 accAmount)
        internal
        view
        returns (bytes memory)
    {
        // decode action data
        // | Offset | Length | Data Type               |
        // |--------|---------|----------------------- |
        // | 0      | 20      | address sender         |
        // | 20     | 40      | address market         |
        // | 40     | 32      | uint256 accAmountIn    |
        // | 72     | 32      | uint256 accAmountOut   |
        // | 104    | 4       | uint32 chainId         |
        // | 108    | 4       | uint32 dstChainId      |
        // | 112    | 1       | bool L1inclusion       |
        bytes memory journal =
            abi.encodePacked(sender, market, accAmount, accAmount, uint32(block.chainid), uint32(block.chainid), true);
        bytes[] memory journals = new bytes[](1);
        journals[0] = journal;
        return abi.encode(journals);
    }

    function _borrowPrerequisites(address mToken, uint256 supplyAmount) internal {
        address underlying = mErc20Immutable(mToken).underlying();
        _getTokens(ERC20Mock(underlying), address(this), supplyAmount);
        IERC20(underlying).approve(mToken, supplyAmount);
        mErc20Immutable(mToken).mint(supplyAmount, address(this), supplyAmount);
    }

    // function _borrowGatewayPrerequisites(address mGateway, uint256 supplyAmount) internal {
    //     address underlying = mTokenGateway(mGateway).underlying();
    //     _getTokens(ERC20Mock(underlying), address(this), supplyAmount);
    //     IERC20(underlying).approve(mGateway, supplyAmount);
    //     mTokenGateway(mGateway).mintOnHost(supplyAmount);
    // }

    function _repayPrerequisites(address mToken, uint256 supplyAmount, uint256 borrowAmount) internal {
        _borrowPrerequisites(mToken, supplyAmount);
        mErc20Immutable(mToken).borrow(borrowAmount);
    }

    // ----------- MODIFIERS ------------
    modifier whenPaused(address mToken, ImTokenOperationTypes.OperationType pauseType) {
        operator.setPaused(mToken, pauseType, true);
        _;
    }

    modifier whenNotPaused(address mToken, ImTokenOperationTypes.OperationType pauseType) {
        operator.setPaused(mToken, pauseType, false);
        _;
    }

    modifier whenMarketIsListed(address mToken) {
        operator.supportMarket(mToken);
        _;
    }

    modifier whenSupplyCapReached(address mToken, uint256 amount) {
        address[] memory mTokens = new address[](1);
        uint256[] memory caps = new uint256[](1);
        mTokens[0] = mToken;
        caps[0] = amount - 1;
        operator.setMarketSupplyCaps(mTokens, caps);
        _;
    }

    modifier whenBorrowCapReached(address mToken, uint256 amount) {
        address[] memory mTokens = new address[](1);
        uint256[] memory caps = new uint256[](1);
        mTokens[0] = mToken;
        caps[0] = amount - 1;
        operator.setMarketBorrowCaps(mTokens, caps);
        _;
    }

    modifier whenMarketEntered(address mToken) {
        address[] memory mTokens = new address[](1);
        mTokens[0] = mToken;
        operator.enterMarkets(mTokens);
        operator.setCollateralFactor(mToken, DEFAULT_COLLATERAL_FACTOR);
        _;
    }
}
