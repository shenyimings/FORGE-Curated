// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29;

import "forge-std/src/Test.sol";

import "./Mocks.sol";
import "../src/proxy/AddressRegistry.sol";
import "../src/utils/Constants.sol";
import "../src/AbstractYieldStrategy.sol";
import "../src/oracles/AbstractCustomOracle.sol";
import "../src/proxy/TimelockUpgradeableProxy.sol";
import "./TestWithdrawRequest.sol";

abstract contract TestEnvironment is Test {
    string RPC_URL = vm.envString("RPC_URL");
    uint256 FORK_BLOCK = vm.envUint("FORK_BLOCK");

    ERC20 public w;
    MockOracle public o;
    IYieldStrategy public y;
    ERC20 public feeToken;
    ERC20 public asset;
    uint256 public defaultDeposit;
    uint256 public defaultBorrow;
    uint256 public maxEntryValuationSlippage = 0.0010e18;
    uint256 public maxExitValuationSlippage = 0.0010e18;
    uint256 public maxWithdrawValuationChange = 0.0050e18;

    address public owner = address(0x02479BFC7Dce53A02e26fE7baea45a0852CB0909);
    ERC20 constant USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    address constant IRM = address(0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC);
    address public addressRegistry;
    ILendingRouter public lendingRouter;

    IWithdrawRequestManager public manager;
    TestWithdrawRequest public withdrawRequest;
    MockOracle internal withdrawTokenOracle;

    string public strategyName;
    string public strategySymbol;

    bool public canInspectTransientVariables = false;

    modifier onlyIfWithdrawRequestManager() {
        vm.skip(address(manager) == address(0));
        _;
    }

    function checkTransientsCleared() internal {
        if (!canInspectTransientVariables) return;

        (address currentAccount, address currentLendingRouter, address allowTransferTo, uint256 allowTransferAmount) = MockYieldStrategy(address(y)).transientVariables();
        assertEq(currentAccount, address(0), "Current account should be cleared");
        assertEq(currentLendingRouter, address(0), "Current lending router should be cleared");
        assertEq(allowTransferTo, address(0), "Allow transfer to should be cleared");
        assertEq(allowTransferAmount, 0, "Allow transfer amount should be cleared");
    }


    function deployAddressRegistry() public {
        address deployer = makeAddr("deployer");
        vm.prank(deployer);
        addressRegistry = address(new AddressRegistry());
        TimelockUpgradeableProxy proxy = new TimelockUpgradeableProxy(
            address(addressRegistry),
            abi.encodeWithSelector(Initializable.initialize.selector, abi.encode(owner, owner, owner))
        );
        addressRegistry = address(proxy);

        assertEq(address(addressRegistry), address(ADDRESS_REGISTRY), "AddressRegistry is incorrect");
    }

    function setMaxOracleFreshness() internal {
        vm.prank(owner);
        TRADING_MODULE.setMaxOracleFreshness(type(uint32).max);
    }

    function setupWithdrawRequestManager(address impl) internal virtual {
        TimelockUpgradeableProxy proxy = new TimelockUpgradeableProxy(
            address(impl), abi.encodeWithSelector(Initializable.initialize.selector, bytes(""))
        );
        manager = IWithdrawRequestManager(address(proxy));

        if (address(ADDRESS_REGISTRY.getWithdrawRequestManager(manager.YIELD_TOKEN())) == address(0)) {
            vm.prank(ADDRESS_REGISTRY.upgradeAdmin());
            ADDRESS_REGISTRY.setWithdrawRequestManager(address(manager));
        }
    }

    function overrideForkBlock() internal virtual { }

    function setUp() public virtual {
        overrideForkBlock();
        vm.createSelectFork(RPC_URL, FORK_BLOCK);
        strategyName = "name";
        strategySymbol = "symbol";
        deployAddressRegistry();
        setMaxOracleFreshness();

        deployYieldStrategy();
        TimelockUpgradeableProxy proxy = new TimelockUpgradeableProxy(
            address(y),
            abi.encodeWithSelector(Initializable.initialize.selector, abi.encode(strategyName, strategySymbol))
        );
        y = IYieldStrategy(address(proxy));

        vm.prank(ADDRESS_REGISTRY.upgradeAdmin());
        ADDRESS_REGISTRY.setWhitelistedVault(address(y), true);

        asset = ERC20(y.asset());
        // Set default fee token, this changes for Convex staked tokens
        if (address(feeToken) == address(0)) feeToken = w;

        vm.prank(owner);
        TRADING_MODULE.setPriceOracle(address(w), AggregatorV2V3Interface(address(o)));

        // USDC whale
        vm.startPrank(0x98C23E9d8f34FEFb1B7BD6a91B7FF122F4e16F5c);
        USDC.transfer(msg.sender, 100_000e6);
        USDC.transfer(owner, 15_000_000e6);
        vm.stopPrank();

        // Deal WETH
        deal(address(WETH), owner, 2_000_000e18);
        vm.prank(owner);
        WETH.transfer(msg.sender, 250_000e18);

        lendingRouter = setupLendingRouter(0.915e18);
        if (address(manager) != address(0)) {
            vm.prank(owner);
            manager.setApprovedVault(address(y), true);
        }

        postDeploySetup();
    }

    /*** Virtual Test Functions ***/

    function finalizeWithdrawRequest(address user) internal virtual {
        (WithdrawRequest memory wr, /* */) = manager.getWithdrawRequest(address(y), user);
        withdrawRequest.finalizeWithdrawRequest(wr.requestId);
    }

    function getRedeemData(
        address /* user */,
        uint256 /* shares */
    ) internal virtual returns (bytes memory redeemData) {
        return "";
    }

    function getDepositData(
        address /* user */,
        uint256 /* depositAmount */
    ) internal virtual returns (bytes memory depositData) {
        return "";
    }

    function getWithdrawRequestData(
        address /* user */,
        uint256 /* shares */
    ) internal virtual returns (bytes memory withdrawRequestData) {
        return bytes("");
    }

    function deployYieldStrategy() internal virtual;

    function postDeploySetup() internal virtual { }

    function setupLendingRouter(uint256 lltv) internal virtual returns (ILendingRouter);

}