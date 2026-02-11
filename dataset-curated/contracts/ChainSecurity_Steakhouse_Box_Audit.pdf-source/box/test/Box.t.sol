// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.28;

import {Test, console2} from "forge-std/Test.sol";
import {Box} from "../src/Box.sol";
import {BoxFactory} from "../src/factories/BoxFactory.sol";
import {IBoxFactory} from "../src/interfaces/IBoxFactory.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IBox} from "../src/interfaces/IBox.sol";
import {IOracle} from "../src/interfaces/IOracle.sol";
import {ISwapper} from "../src/interfaces/ISwapper.sol";
import {IFunding, IOracleCallback} from "../src/interfaces/IFunding.sol";
import "../src/libraries/Constants.sol";
import {BoxLib} from "../src/periphery/BoxLib.sol";
import {ErrorsLib} from "../src/libraries/ErrorsLib.sol";
import {ERC20MockDecimals} from "./mocks/ERC20MockDecimals.sol";
import {FundingMorpho} from "../src/FundingMorpho.sol";
import {IMorpho, MarketParams, Position} from "@morpho-blue/interfaces/IMorpho.sol";
import {Morpho} from "@morpho-blue/Morpho.sol";
import {IrmMock} from "@morpho-blue/mocks/IrmMock.sol";
import {OracleMock} from "@morpho-blue/mocks/OracleMock.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {EventsLib} from "../src/libraries/EventsLib.sol";

contract MockOracle is IOracle {
    uint256 public price = 1e36; // 1:1 price
    int256 immutable decimalsShift;

    constructor(IERC20 input, IERC20 output) {
        decimalsShift =
            int256(uint256(IERC20Metadata(address(output)).decimals())) - int256(uint256(IERC20Metadata(address(input)).decimals()));
        price = (decimalsShift > 0) ? 1e36 * (10 ** uint256(decimalsShift)) : 1e36 / (10 ** uint256(-decimalsShift));
    }

    function setPrice(uint256 _price) external {
        price = (decimalsShift > 0) ? _price * (10 ** uint256(decimalsShift)) : _price / (10 ** uint256(-decimalsShift));
    }
}

contract MockSwapper is ISwapper {
    uint256 public slippagePercent = 0; // 0% slippage by default in 18 decimals
    bool public shouldRevert = false;
    bool public spendTooMuch = false;

    function setSlippage(uint256 _slippagePercent) external {
        slippagePercent = _slippagePercent;
    }

    function setShouldRevert(bool _shouldRevert) external {
        shouldRevert = _shouldRevert;
    }

    function setSpendTooMuch(bool _spendTooMuch) external {
        spendTooMuch = _spendTooMuch;
    }

    function sell(IERC20 input, IERC20 output, uint256 amountIn, bytes calldata) external {
        require(!shouldRevert, "Swapper: Forced revert");

        // If spendTooMuch is true, try to take more than authorized
        uint256 actualAmount = spendTooMuch ? amountIn + 1 : amountIn;
        input.transferFrom(msg.sender, address(this), actualAmount);

        int256 decimalsShift = int256(uint256(IERC20Metadata(address(output)).decimals())) -
            int256(uint256(IERC20Metadata(address(input)).decimals()));

        // Apply slippage
        uint256 amountOut = (amountIn * (10 ** 18 - slippagePercent)) / 10 ** 18;

        if (decimalsShift > 0) {
            amountOut = amountOut * (10 ** uint256(decimalsShift));
        } else if (decimalsShift < 0) {
            amountOut = amountOut / (10 ** uint256(-decimalsShift));
        }

        output.transfer(msg.sender, amountOut);
    }
}

contract PriceAwareSwapper is ISwapper {
    IOracle public oracle;
    uint256 public slippagePercent = 0;

    constructor(IOracle _oracle) {
        oracle = _oracle;
    }

    function setSlippage(uint256 _slippagePercent) external {
        slippagePercent = _slippagePercent;
    }

    function sell(IERC20 input, IERC20 output, uint256 amountIn, bytes calldata) external {
        // Pull input tokens
        input.transferFrom(msg.sender, address(this), amountIn);

        // Pay out assets according to oracle price, minus slippage
        uint256 expectedOut = (amountIn * oracle.price()) / ORACLE_PRECISION;
        uint256 amountOut = (expectedOut * (10 ** 18 - slippagePercent)) / 10 ** 18;
        output.transfer(msg.sender, amountOut);
    }
}

contract MaliciousSwapper is ISwapper {
    uint256 public step = 5; // level of recursion
    IBox public box;
    uint256 public scenario = ALLOCATE;
    uint256 public constant ALLOCATE = 0;
    uint256 public constant DEALLOCATE = 1;
    uint256 public constant REALLOCATE = 2;

    function setBox(IBox _box) external {
        box = _box;
    }

    function setScenario(uint256 _scenario) external {
        scenario = _scenario;
    }

    function sell(IERC20 input, IERC20 output, uint256 amountIn, bytes calldata data) external {
        input.transferFrom(msg.sender, address(this), amountIn);

        step--;

        if (step > 0) {
            // Recursively call sell to simulate reentrancy
            if (scenario == 0) {
                box.allocate(output, amountIn, this, data);
            } else if (scenario == 1) {
                box.deallocate(input, amountIn, this, data);
            } else if (scenario == 2) {
                box.reallocate(input, output, amountIn, this, data);
            }
        }

        if (step == 0) {
            output.transfer(msg.sender, amountIn);
        }

        step++;
    }
}

contract MaliciousFundingSwapper is ISwapper {
    IBox public box;
    IFunding public funding;
    uint256 public scenario = BORROW;
    uint256 public constant BORROW = 0;
    uint256 public constant DEPLEDGE = 1;

    function setBox(IBox _box) external {
        box = _box;
    }

    function setFunding(IFunding _funding) external {
        funding = _funding;
    }

    function setScenario(uint256 _scenario) external {
        scenario = _scenario;
    }

    function sell(IERC20 input, IERC20 output, uint256 amountIn, bytes calldata) external {
        input.transferFrom(msg.sender, address(this), amountIn);

        if (scenario == 0) {
            box.borrow(funding, "", output, amountIn);
        } else if (scenario == 1) {
            box.depledge(funding, "", output, amountIn);
        }
    }
}

// Malicious swapper that attempts read-only reentrancy attack (5.2)
contract ReadOnlyReentrancySwapper is ISwapper {
    using SafeERC20 for IERC20;
    IBox public immutable box;
    uint256 public observedTotalAssets;
    IOracle public oracle;

    constructor(IBox _box) {
        box = _box;
    }

    function setOracle(IOracle _oracle) external {
        oracle = _oracle;
    }

    function sell(IERC20 input, IERC20 output, uint256 amountIn, bytes calldata) external {
        // Take tokens from Box
        input.safeTransferFrom(msg.sender, address(this), amountIn);

        // Attempt read-only reentrancy: try to observe manipulated NAV
        // With the fix, this should return the CACHED (pre-swap) NAV, not the manipulated NAV
        observedTotalAssets = box.totalAssets();

        // Return assets based on oracle price
        uint256 outputAmount = (amountIn * oracle.price()) / ORACLE_PRECISION;
        output.safeTransfer(msg.sender, outputAmount);
    }
}

// Malicious flash callback that attempts to deposit/withdraw during flash
contract MaliciousFlashCallback {
    using SafeERC20 for IERC20;
    IBox public immutable box;
    IERC20 public immutable asset;
    uint256 public scenario;
    uint256 public constant DEPOSIT = 0;
    uint256 public constant MINT = 1;
    uint256 public constant WITHDRAW = 2;
    uint256 public constant REDEEM = 3;

    constructor(IBox _box, IERC20 _asset) {
        box = _box;
        asset = _asset;
    }

    function setScenario(uint256 _scenario) external {
        scenario = _scenario;
    }

    function onBoxFlash(IERC20 token, uint256 amount, bytes calldata) external {
        require(msg.sender == address(box), "Only Box can call");

        if (scenario == DEPOSIT) {
            // Attempt to deposit during flash
            IERC20(asset).safeIncreaseAllowance(address(box), 100e18);
            box.deposit(100e18, address(this));
        } else if (scenario == MINT) {
            // Attempt to mint during flash
            IERC20(asset).safeIncreaseAllowance(address(box), 100e18);
            box.mint(100e18, address(this));
        } else if (scenario == WITHDRAW) {
            // Attempt to withdraw during flash
            box.withdraw(10e18, address(this), address(this));
        } else if (scenario == REDEEM) {
            // Attempt to redeem during flash
            box.redeem(10e18, address(this), address(this));
        }
    }
}

// Mock funding module for testing debt scenarios
contract MockFunding is IFunding {
    using SafeERC20 for IERC20;
    mapping(IERC20 => uint256) public debtBalances;
    address public immutable owner;

    constructor(address _owner) {
        owner = _owner;
    }

    function setDebtBalance(IERC20 token, uint256 amount) external {
        debtBalances[token] = amount;
    }

    function debtBalance(IERC20 token) external view returns (uint256) {
        return debtBalances[token];
    }

    // Stub implementations for other required functions
    function nav(IOracleCallback) external pure returns (uint256) {
        return 0;
    }
    function ltv(bytes calldata) external pure returns (uint256) {
        return 0;
    }
    function collateralBalance(bytes calldata, IERC20) external pure returns (uint256) {
        return 0;
    }
    function collateralBalance(IERC20) external pure returns (uint256) {
        return 0;
    }
    function debtBalance(bytes calldata, IERC20) external pure returns (uint256) {
        return 0;
    }
    function isCollateralToken(IERC20) external pure returns (bool) {
        return false;
    }
    function isDebtToken(IERC20) external pure returns (bool) {
        return true;
    }
    function collateralTokensLength() external pure returns (uint256) {
        return 0;
    }
    function debtTokensLength() external pure returns (uint256) {
        return 0;
    }
    function facilitiesLength() external pure returns (uint256) {
        return 0;
    }
    function facilities(uint256) external pure returns (bytes memory) {
        return "";
    }
    function isFacility(bytes calldata) external pure returns (bool) {
        return false;
    }
    function collateralTokens(uint256) external pure returns (IERC20) {
        return IERC20(address(0));
    }
    function debtTokens(uint256) external pure returns (IERC20) {
        return IERC20(address(0));
    }
    function addFacility(bytes calldata) external {}
    function removeFacility(bytes calldata) external {}
    function addCollateralToken(IERC20) external {}
    function removeCollateralToken(IERC20) external {}
    function addDebtToken(IERC20) external {}
    function removeDebtToken(IERC20) external {}
    function pledge(bytes calldata, IERC20, uint256) external {}
    function depledge(bytes calldata, IERC20 token, uint256 amount) external {
        token.safeTransfer(msg.sender, amount);
    }
    function borrow(bytes calldata, IERC20 token, uint256 amount) external {
        token.safeTransfer(msg.sender, amount);
    }
    function repay(bytes calldata, IERC20, uint256) external {}
    function skim(IERC20) external {}
}

contract BoxTest is Test {
    using BoxLib for IBox;
    using SafeERC20 for IERC20;
    using SafeERC20 for ERC20MockDecimals;

    IBoxFactory public boxFactory;
    IBox public box;

    ERC20MockDecimals public asset;
    ERC20MockDecimals public token1;
    ERC20MockDecimals public token2;
    ERC20MockDecimals public token3;
    MockOracle public oracle1;
    MockOracle public oracle2;
    MockOracle public oracle3;
    MockSwapper public swapper;
    MockSwapper public backupSwapper;
    MockSwapper public badSwapper;
    MaliciousSwapper public maliciousSwapper;
    MockFunding public mockFunding;

    address public owner = address(0x1);
    address public allocator = address(0x2);
    address public curator = address(0x3);
    address public guardian = address(0x4);
    address public feeder = address(0x5);
    address public user1 = address(0x6);
    address public user2 = address(0x7);
    address public nonAuthorized = address(0x8);

    IMorpho morpho;
    address irm;

    uint256 lltv80 = 800000000000000000;
    uint256 lltv90 = 900000000000000000;

    MarketParams marketParamsLtv80;
    MarketParams marketParamsLtv90;

    FundingMorpho fundingMorpho;
    bytes facilityDataLtv80;
    bytes facilityDataLtv90;

    event Deposit(address indexed caller, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(address indexed caller, address indexed receiver, address indexed owner, uint256 assets, uint256 shares);
    event Allocation(
        IERC20 indexed token,
        uint256 assets,
        uint256 expectedTokens,
        uint256 actualTokens,
        int256 slippagePct,
        ISwapper indexed swapper,
        bytes data
    );
    event Deallocation(
        IERC20 indexed token,
        uint256 tokens,
        uint256 expectedAssets,
        uint256 actualAssets,
        int256 slippagePct,
        ISwapper indexed swapper,
        bytes data
    );
    event Reallocation(
        IERC20 indexed fromToken,
        IERC20 indexed toToken,
        uint256 fromAmount,
        uint256 expectedToAmount,
        uint256 actualToAmount,
        int256 slippagePct,
        ISwapper indexed swapper,
        bytes data
    );
    event Shutdown(address indexed guardian);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        asset = new ERC20MockDecimals(18);
        token1 = new ERC20MockDecimals(18);
        token2 = new ERC20MockDecimals(18);
        token3 = new ERC20MockDecimals(18);
        oracle1 = new MockOracle(token1, asset);
        oracle2 = new MockOracle(token2, asset);
        oracle3 = new MockOracle(token3, asset);
        swapper = new MockSwapper();
        backupSwapper = new MockSwapper();
        badSwapper = new MockSwapper();
        maliciousSwapper = new MaliciousSwapper();

        // Mint tokens for testing
        asset.mint(address(this), 10000e18);
        asset.mint(feeder, 10000e18);
        asset.mint(user1, 10000e18);
        asset.mint(user2, 10000e18);
        token1.mint(address(swapper), 10000e18);
        token2.mint(address(swapper), 10000e18);
        token3.mint(address(swapper), 10000e18);
        token1.mint(address(this), 10000e18);
        token2.mint(address(this), 10000e18);
        token3.mint(address(this), 10000e18);
        token1.mint(address(backupSwapper), 10000e18);
        token2.mint(address(backupSwapper), 10000e18);
        token3.mint(address(backupSwapper), 10000e18);
        token1.mint(address(badSwapper), 10000e18);
        token2.mint(address(badSwapper), 10000e18);
        token3.mint(address(badSwapper), 10000e18);
        token1.mint(address(maliciousSwapper), 10000e18);
        token2.mint(address(maliciousSwapper), 10000e18);
        token3.mint(address(maliciousSwapper), 10000e18);

        // Mint asset for swappers to provide liquidity
        asset.mint(address(swapper), 10000e18);
        asset.mint(address(backupSwapper), 10000e18);
        asset.mint(address(badSwapper), 10000e18);
        asset.mint(address(maliciousSwapper), 10000e18);

        // Funding context using Morpho

        morpho = IMorpho(address(new Morpho(address(this))));
        irm = address(new IrmMock());

        morpho.enableIrm(irm);
        morpho.enableLltv(lltv80);
        morpho.enableLltv(lltv90);

        // Create a 80% lltv market and seed it
        marketParamsLtv80 = MarketParams(address(asset), address(token1), address(oracle1), address(irm), lltv80);
        morpho.createMarket(marketParamsLtv80);
        asset.approve(address(morpho), 10000e18);
        token1.approve(address(morpho), 10000e18);
        morpho.supplyCollateral(marketParamsLtv80, 10e18, address(this), "");
        morpho.supply(marketParamsLtv80, 10e18, 0, address(this), "");
        morpho.borrow(marketParamsLtv80, 5e18, 0, address(this), address(this));
        facilityDataLtv80 = abi.encode(marketParamsLtv80);

        // Create a 90% lltv market and seed it
        marketParamsLtv90 = MarketParams(address(asset), address(token1), address(oracle1), address(irm), lltv90);
        morpho.createMarket(marketParamsLtv90);
        morpho.supplyCollateral(marketParamsLtv90, 10e18, address(this), "");
        morpho.supply(marketParamsLtv90, 10e18, 0, address(this), "");
        morpho.borrow(marketParamsLtv90, 5e18, 0, address(this), address(this));
        facilityDataLtv90 = abi.encode(marketParamsLtv90);

        boxFactory = new BoxFactory();

        //  Vault parameters
        string memory name = "Box Shares";
        string memory symbol = "BOX";
        uint256 maxSlippage = 0.01 ether; // 1%
        uint256 slippageEpochDuration = 7 days;
        uint256 shutdownSlippageDuration = 10 days;
        uint256 shutdownWarmup = 7 days;

        box = boxFactory.createBox(
            asset,
            owner,
            owner, // Initially owner is also curator
            name,
            symbol,
            maxSlippage,
            slippageEpochDuration,
            shutdownSlippageDuration,
            shutdownWarmup,
            bytes32(0)
        );

        // Create mockFunding with box as owner
        mockFunding = new MockFunding(address(box));

        // Setup roles and investment tokens using new timelock pattern
        // Note: owner is initially the curator, so owner can submit
        vm.startPrank(owner);
        // Set curator
        box.setCurator(curator);
        vm.stopPrank();

        vm.startPrank(curator);

        box.setGuardianInstant(guardian);
        box.addFeederInstant(feeder);
        box.setIsAllocator(allocator, true);
        box.setIsAllocator(address(maliciousSwapper), true);

        box.addTokenInstant(token1, oracle1);
        box.addTokenInstant(token2, oracle2);

        // Increase some timelocks
        box.increaseTimelock(box.setMaxSlippage.selector, 1 days);
        box.increaseTimelock(box.setGuardian.selector, 1 days);

        // Funding config
        fundingMorpho = new FundingMorpho(address(box), address(morpho), 99e16);
        box.addFundingInstant(fundingMorpho);
        box.addFundingCollateralInstant(fundingMorpho, token1);
        box.addFundingDebtInstant(fundingMorpho, asset);
        box.addFundingFacilityInstant(fundingMorpho, facilityDataLtv80);

        vm.stopPrank();
    }

    /////////////////////////////
    /// BASIC TESTS
    /////////////////////////////
    function testBoxCreation(
        address asset_,
        address owner_,
        address curator_,
        string memory name_,
        string memory symbol_,
        uint256 maxSlippage_,
        uint256 slippageEpochDuration_,
        uint256 shutdownSlippageDuration_,
        uint256 shutdownWarmup_,
        bytes32 salt
    ) public {
        vm.assume(asset_ != address(0));
        vm.assume(owner_ != address(0));
        vm.assume(curator_ != address(0));
        vm.assume(maxSlippage_ <= MAX_SLIPPAGE_LIMIT);
        vm.assume(slippageEpochDuration_ != 0);
        vm.assume(shutdownSlippageDuration_ != 0);
        vm.assume(shutdownWarmup_ <= MAX_SHUTDOWN_WARMUP);

        // Mock decimals() to return 18 for the fuzzed asset address
        vm.mockCall(asset_, abi.encodeWithSignature("decimals()"), abi.encode(uint8(18)));

        bytes memory initCode = abi.encodePacked(
            type(Box).creationCode,
            abi.encode(
                asset_,
                owner_,
                curator_,
                name_,
                symbol_,
                maxSlippage_,
                slippageEpochDuration_,
                shutdownSlippageDuration_,
                shutdownWarmup_
            )
        );

        address predicted = vm.computeCreate2Address(
            salt,
            keccak256(initCode),
            address(boxFactory) // deploying address
        );

        vm.expectEmit(true, true, true, true);
        emit IBoxFactory.BoxCreated(
            IBox(predicted),
            IERC20(asset_),
            owner_,
            curator_,
            name_,
            symbol_,
            maxSlippage_,
            slippageEpochDuration_,
            shutdownSlippageDuration_,
            shutdownWarmup_
        );
        box = boxFactory.createBox(
            IERC20(asset_),
            owner_,
            curator_,
            name_,
            symbol_,
            maxSlippage_,
            slippageEpochDuration_,
            shutdownSlippageDuration_,
            shutdownWarmup_,
            salt
        );

        assertEq(address(box), predicted, "unexpected CREATE2 address");
        assertEq(address(box.asset()), address(asset_));
        assertEq(box.owner(), owner_);
        assertEq(box.curator(), curator_);
        assertEq(box.name(), name_);
        assertEq(box.symbol(), symbol_);
        assertEq(box.maxSlippage(), maxSlippage_);
        assertEq(box.slippageEpochDuration(), slippageEpochDuration_);
        assertEq(box.shutdownSlippageDuration(), shutdownSlippageDuration_);
    }

    function testDefaultSkimRecipientIsZero() public view {
        assertEq(box.skimRecipient(), address(0), "skimRecipient should default to zero");
    }

    function testSkimTransfersToRecipient() public {
        // Mint unrelated token (not the asset and not whitelisted) to the Box and skim it
        uint256 amount = 1e18;
        token3.mint(address(box), amount);
        assertEq(token3.balanceOf(address(box)), amount);

        vm.prank(box.skimRecipient());
        vm.expectRevert();
        box.skim(token3);

        vm.prank(owner);
        box.setSkimRecipient(nonAuthorized);

        vm.prank(box.skimRecipient());
        box.skim(token3);

        assertEq(token3.balanceOf(address(box)), 0);
        assertEq(token3.balanceOf(nonAuthorized), amount);
    }

    function testSkimNotAuthorized(address nonAuthorized_) public {
        vm.assume(nonAuthorized_ != box.skimRecipient());

        // Mint unrelated token (not the asset and not whitelisted) to the Box and skim it
        uint256 amount = 1e18;
        token3.mint(address(box), amount);
        assertEq(token3.balanceOf(address(box)), amount);

        vm.startPrank(nonAuthorized_);
        vm.expectRevert(ErrorsLib.OnlySkimRecipient.selector);
        box.skim(token3);
        vm.stopPrank();
    }

    function testSkimNativeETH() public {
        // Send ETH to the Box contract (simulating it receiving ETH from external source)
        uint256 amount = 5 ether;
        vm.deal(address(box), amount);
        assertEq(address(box).balance, amount);

        // Set a skim recipient (use a proper address, not a precompile)
        address skimRecipient = address(0x1234);
        vm.prank(owner);
        box.setSkimRecipient(skimRecipient);

        uint256 recipientBalanceBefore = skimRecipient.balance;

        // Skim ETH (address(0) represents native currency)
        vm.prank(skimRecipient);
        box.skim(IERC20(address(0)));

        assertEq(address(box).balance, 0, "Box should have no ETH left");
        assertEq(skimRecipient.balance, recipientBalanceBefore + amount, "Recipient should receive ETH");
    }

    function testReceiveNativeETH() public {
        // This test verifies that the Box can receive native ETH
        // (e.g., from a funding module that sends ETH back)
        uint256 amount = 2 ether;

        uint256 balanceBefore = address(box).balance;

        // Send ETH to Box from an external address (simulating funding module)
        address sender = address(0x9999);
        vm.deal(sender, amount);

        vm.prank(sender);
        (bool success, ) = address(box).call{value: amount}("");
        assertTrue(success, "ETH transfer should succeed");

        assertEq(address(box).balance, balanceBefore + amount, "Box should receive ETH");
    }

    /////////////////////////////
    /// BASIC ERC4626 TESTS
    /////////////////////////////

    function testERC4626Compliance() public view {
        // Test asset()
        assertEq(box.asset(), address(asset));

        // Test initial state
        assertEq(box.totalAssets(), 0);
        assertEq(box.totalSupply(), 0);
        assertEq(box.convertToShares(100e18), 100e18); // 1:1 when empty
        assertEq(box.convertToAssets(100e18), 100e18); // 1:1 when empty

        // Test max functions when not shutdown
        assertEq(box.maxDeposit(feeder), type(uint256).max);
        assertEq(box.maxMint(feeder), type(uint256).max);
        assertEq(box.maxWithdraw(feeder), 0); // No shares yet
        assertEq(box.maxRedeem(feeder), 0); // No shares yet
    }

    function testERC4626SharesNoAssets() public {
        assertEq(box.convertToShares(100e18), 100e18); // 1:1 when empty

        vm.startPrank(feeder);
        asset.approve(address(box), 100e18);
        box.deposit(100e18, feeder);
        vm.stopPrank();

        // Simulate the loss to get totalAsset = 0
        vm.prank(address(box));
        asset.transfer(address(0xdead), 100e18);

        // With virtual shares + 1 offset, conversion doesn't revert even when totalAssets=0
        // Formula: assets * (supply + virtual) / (totalAssets + 1)
        // This matches VaultV2 and ERC4626 standard behavior
        uint256 shares = box.convertToShares(100e18);
        assertGt(shares, 0, "Should return valid shares even with 0 total assets");
    }

    function testDeposit() public {
        vm.startPrank(feeder);
        asset.approve(address(box), 100e18);

        vm.expectEmit(true, true, true, true);
        emit Deposit(feeder, feeder, 100e18, 100e18);

        uint256 shares = box.deposit(100e18, feeder);
        vm.stopPrank();

        assertEq(shares, 100e18);
        assertEq(box.balanceOf(feeder), 100e18);
        assertEq(box.totalSupply(), 100e18);
        assertEq(box.totalAssets(), 100e18);
        assertEq(asset.balanceOf(address(box)), 100e18);
    }

    function testDepositOneUnitWithDifferentDecimals() public {
        // Test that depositing 1 unit of asset (regardless of decimals) gives 1 unit of shares
        uint8[] memory decimalsToTest = new uint8[](5);
        decimalsToTest[0] = 6;
        decimalsToTest[1] = 8;
        decimalsToTest[2] = 12;
        decimalsToTest[3] = 18;
        decimalsToTest[4] = 24;

        for (uint256 i = 0; i < decimalsToTest.length; i++) {
            uint8 assetDecimals = decimalsToTest[i];

            // Create asset with specific decimals
            ERC20MockDecimals testAsset = new ERC20MockDecimals(assetDecimals);
            testAsset.mint(feeder, 1000 * (10 ** assetDecimals));

            // Create box with this asset
            IBox testBox = boxFactory.createBox(
                testAsset,
                owner,
                curator,
                "Test Box",
                "TBOX",
                0.01 ether,
                7 days,
                10 days,
                7 days,
                bytes32(uint256(i))
            );

            // Add feeder
            vm.prank(curator);
            testBox.addFeederInstant(feeder);

            // Deposit one unit of the asset
            uint256 oneUnit = 10 ** assetDecimals;
            vm.startPrank(feeder);
            testAsset.approve(address(testBox), oneUnit);
            uint256 shares = testBox.deposit(oneUnit, feeder);
            vm.stopPrank();

            // Expected shares: should be 1 unit in the box's decimal system
            // Box normalizes to 18 decimals for assets with <=18 decimals
            // For assets with >18 decimals, box uses the asset's decimals
            uint256 expectedShares = assetDecimals <= 18 ? 1e18 : 10 ** assetDecimals;

            assertEq(shares, expectedShares, string.concat("Failed for ", vm.toString(assetDecimals), " decimals: shares mismatch"));
            assertEq(
                testBox.balanceOf(feeder),
                expectedShares,
                string.concat("Failed for ", vm.toString(assetDecimals), " decimals: balance mismatch")
            );
            assertEq(
                testBox.decimals(),
                assetDecimals <= 18 ? 18 : assetDecimals,
                string.concat("Failed for ", vm.toString(assetDecimals), " decimals: box decimals mismatch")
            );
        }
    }

    function testDepositNonFeeder() public {
        vm.startPrank(nonAuthorized);
        asset.approve(address(box), 100e18);

        vm.expectRevert(ErrorsLib.OnlyFeeders.selector);
        box.deposit(100e18, nonAuthorized);
        vm.stopPrank();
    }

    function testDepositWhenShutdown() public {
        vm.prank(guardian);
        box.shutdown();

        vm.startPrank(feeder);
        asset.approve(address(box), 100e18);

        vm.expectRevert(ErrorsLib.CannotDuringShutdown.selector);
        box.deposit(100e18, feeder);
        vm.stopPrank();
    }

    function testMint() public {
        vm.startPrank(feeder);
        asset.approve(address(box), 100e18);

        vm.expectEmit(true, true, true, true);
        emit Deposit(feeder, feeder, 100e18, 100e18);

        uint256 assets = box.mint(100e18, feeder);
        vm.stopPrank();

        assertEq(assets, 100e18);
        assertEq(box.balanceOf(feeder), 100e18);
        assertEq(box.totalSupply(), 100e18);
        assertEq(box.totalAssets(), 100e18);
    }

    function testMintNonFeeder() public {
        vm.startPrank(nonAuthorized);
        asset.approve(address(box), 100e18);

        vm.expectRevert(ErrorsLib.OnlyFeeders.selector);
        box.mint(100e18, nonAuthorized);
        vm.stopPrank();
    }

    function testMintWhenShutdown() public {
        vm.prank(guardian);
        box.shutdown();

        vm.startPrank(feeder);
        asset.approve(address(box), 100e18);

        vm.expectRevert(ErrorsLib.CannotDuringShutdown.selector);
        box.mint(100e18, feeder);
        vm.stopPrank();
    }

    function testWithdraw() public {
        // First deposit
        vm.startPrank(feeder);
        asset.approve(address(box), 100e18);
        box.deposit(100e18, feeder);

        // Then withdraw
        vm.expectEmit(true, true, true, true);
        emit Withdraw(feeder, feeder, feeder, 50e18, 50e18);

        uint256 shares = box.withdraw(50e18, feeder, feeder);
        vm.stopPrank();

        assertEq(shares, 50e18);
        assertEq(box.balanceOf(feeder), 50e18);
        assertEq(box.totalSupply(), 50e18);
        assertEq(box.totalAssets(), 50e18);
        assertEq(asset.balanceOf(feeder), 9950e18);
    }

    function testWithdrawInsufficientShares() public {
        vm.startPrank(feeder);
        asset.approve(address(box), 100e18);
        box.deposit(100e18, feeder);

        vm.expectRevert(ErrorsLib.InsufficientShares.selector);
        box.withdraw(200e18, feeder, feeder);
        vm.stopPrank();
    }

    function testWithdrawWithAllowance() public {
        // Setup: feeder deposits, user1 gets allowance
        vm.startPrank(feeder);
        asset.approve(address(box), 100e18);
        box.deposit(100e18, feeder);
        box.approve(user1, 50e18);
        vm.stopPrank();

        // Add user1 as feeder so they can withdraw
        vm.startPrank(curator);
        bytes memory userData = abi.encodeWithSelector(box.setIsFeeder.selector, user1, true);
        box.submit(userData);
        vm.warp(block.timestamp + 1 days + 1);
        (bool userSuccess, ) = address(box).call(userData);
        require(userSuccess, "Failed to set user1 as feeder");
        vm.stopPrank();

        // user1 withdraws on behalf of feeder
        vm.prank(user1);
        uint256 shares = box.withdraw(30e18, user1, feeder);

        assertEq(shares, 30e18);
        assertEq(box.balanceOf(feeder), 70e18);
        assertEq(box.allowance(feeder, user1), 20e18); // 50 - 30
        assertEq(asset.balanceOf(user1), 10030e18);
    }

    function testWithdrawInsufficientAllowance() public {
        vm.startPrank(feeder);
        asset.approve(address(box), 100e18);
        box.deposit(100e18, feeder);
        box.approve(user1, 30e18);
        vm.stopPrank();

        // Add user1 as feeder so they can withdraw
        vm.startPrank(curator);
        bytes memory userData = abi.encodeWithSelector(box.setIsFeeder.selector, user1, true);
        box.submit(userData);
        vm.warp(block.timestamp + 1 days + 1);
        (bool userSuccess, ) = address(box).call(userData);
        require(userSuccess, "Failed to set user1 as feeder");
        vm.stopPrank();

        vm.expectRevert(ErrorsLib.InsufficientAllowance.selector);
        vm.prank(user1);
        box.withdraw(50e18, user1, feeder);
    }

    function testRedeem() public {
        // First deposit
        vm.startPrank(feeder);
        asset.approve(address(box), 100e18);
        box.deposit(100e18, feeder);

        // Then redeem
        vm.expectEmit(true, true, true, true);
        emit Withdraw(feeder, feeder, feeder, 50e18, 50e18);

        uint256 assets = box.redeem(50e18, feeder, feeder);
        vm.stopPrank();

        assertEq(assets, 50e18);
        assertEq(box.balanceOf(feeder), 50e18);
        assertEq(box.totalSupply(), 50e18);
        assertEq(asset.balanceOf(feeder), 9950e18);
    }

    function testRedeemInsufficientShares() public {
        vm.startPrank(feeder);
        asset.approve(address(box), 100e18);
        box.deposit(100e18, feeder);

        vm.expectRevert(ErrorsLib.InsufficientShares.selector);
        box.redeem(200e18, feeder, feeder);
        vm.stopPrank();
    }

    /////////////////////////////
    /// ERC20 SHARE TESTS
    /////////////////////////////

    function testERC20Transfer() public {
        // Setup
        vm.startPrank(feeder);
        asset.approve(address(box), 100e18);
        box.deposit(100e18, feeder);

        vm.expectEmit(true, true, true, true);
        emit Transfer(feeder, user1, 50e18);

        bool success = box.transfer(user1, 50e18);
        vm.stopPrank();

        assertTrue(success);
        assertEq(box.balanceOf(feeder), 50e18);
        assertEq(box.balanceOf(user1), 50e18);
    }

    function testERC20TransferInsufficientBalance() public {
        vm.startPrank(feeder);
        asset.approve(address(box), 100e18);
        box.deposit(100e18, feeder);

        vm.expectRevert();
        box.transfer(user1, 200e18);
        vm.stopPrank();
    }

    function testERC20Approve() public {
        vm.startPrank(feeder);

        vm.expectEmit(true, true, true, true);
        emit Approval(feeder, user1, 100e18);

        bool success = box.approve(user1, 100e18);
        vm.stopPrank();

        assertTrue(success);
        assertEq(box.allowance(feeder, user1), 100e18);
    }

    function testERC20TransferFrom() public {
        // Setup
        vm.startPrank(feeder);
        asset.approve(address(box), 100e18);
        box.deposit(100e18, feeder);
        box.approve(user1, 50e18);
        vm.stopPrank();

        vm.expectEmit(true, true, true, true);
        emit Transfer(feeder, user2, 30e18);

        vm.prank(user1);
        bool success = box.transferFrom(feeder, user2, 30e18);

        assertTrue(success);
        assertEq(box.balanceOf(feeder), 70e18);
        assertEq(box.balanceOf(user2), 30e18);
        assertEq(box.allowance(feeder, user1), 20e18);
    }

    function testERC20TransferFromInsufficientAllowance() public {
        vm.startPrank(feeder);
        asset.approve(address(box), 100e18);
        box.deposit(100e18, feeder);
        box.approve(user1, 30e18);
        vm.stopPrank();

        vm.expectRevert();
        vm.prank(user1);
        box.transferFrom(feeder, user2, 50e18);
    }

    function testERC20TransferFromInsufficientBalance() public {
        vm.startPrank(feeder);
        asset.approve(address(box), 100e18);
        box.deposit(100e18, feeder);
        box.approve(user1, 200e18);
        vm.stopPrank();

        vm.expectRevert();
        vm.prank(user1);
        box.transferFrom(feeder, user2, 150e18);
    }

    function testERC20TransferFromMaxAllowance() public {
        // Setup with max allowance
        vm.startPrank(feeder);
        asset.approve(address(box), 100e18);
        box.deposit(100e18, feeder);
        box.approve(user1, type(uint256).max);
        vm.stopPrank();

        vm.prank(user1);
        box.transferFrom(feeder, user2, 50e18);

        assertEq(box.balanceOf(feeder), 50e18);
        assertEq(box.balanceOf(user2), 50e18);
        assertEq(box.allowance(feeder, user1), type(uint256).max); // Should not decrease
    }

    /////////////////////////////
    /// ALLOCATION TESTS
    /////////////////////////////

    function testAllocateToToken() public {
        // Setup
        vm.startPrank(feeder);
        asset.approve(address(box), 100e18);
        box.deposit(100e18, feeder);
        vm.stopPrank();

        vm.expectEmit(true, true, true, true);
        emit Allocation(token1, 50e18, 50e18, 50e18, 0, swapper, "");

        // Allocate to token1
        vm.prank(allocator);
        box.allocate(token1, 50e18, swapper, "");

        assertEq(asset.balanceOf(address(box)), 50e18);
        assertEq(token1.balanceOf(address(box)), 50e18);
        assertEq(box.totalAssets(), 100e18); // 50 USDC + 50 token1 (1:1 price)

        // Approval should be revoked post-swap
        assertEq(asset.allowance(address(box), address(swapper)), 0);
    }

    function testAllocateNonAllocator() public {
        vm.startPrank(feeder);
        asset.approve(address(box), 100e18);
        box.deposit(100e18, feeder);
        vm.stopPrank();

        vm.expectRevert(ErrorsLib.OnlyAllocatorsOrWinddown.selector);
        vm.prank(nonAuthorized);
        box.allocate(token1, 50e18, swapper, "");
    }

    function testAllocateWhenShutdown() public {
        vm.startPrank(feeder);
        asset.approve(address(box), 100e18);
        box.deposit(100e18, feeder);
        vm.stopPrank();

        vm.prank(guardian);
        box.shutdown();

        // Still work during shutdown
        vm.prank(allocator);
        box.allocate(token1, 50e18, swapper, "");

        vm.prank(nonAuthorized);
        vm.expectRevert(ErrorsLib.OnlyAllocatorsOrWinddown.selector);
        box.allocate(token1, 10e18, swapper, "");

        // Should not work because allocator don't have much power anymore
        // And as there is no debt it should work
        vm.warp(block.timestamp + box.shutdownWarmup());
        vm.prank(allocator);
        vm.expectRevert(ErrorsLib.OnlyAllocatorsOrWinddown.selector);
        box.allocate(token1, 10e18, swapper, "");

        vm.prank(nonAuthorized);
        vm.expectRevert(ErrorsLib.OnlyAllocatorsOrWinddown.selector);
        box.allocate(token1, 10e18, swapper, "");
    }

    function testAllocateNonWhitelistedToken() public {
        vm.startPrank(feeder);
        asset.approve(address(box), 100e18);
        box.deposit(100e18, feeder);
        vm.stopPrank();

        vm.expectRevert(ErrorsLib.TokenNotWhitelisted.selector);
        vm.prank(allocator);
        box.allocate(token3, 50e18, swapper, "");
    }

    function testAllocateNoOracle() public {
        // This test needs to be updated since the error happens at execution time now
        vm.startPrank(curator);
        bytes memory tokenData = abi.encodeWithSelector(box.addToken.selector, token3, IOracle(address(0)));
        box.submit(tokenData);
        vm.warp(block.timestamp + 1 days + 1);
        vm.expectRevert(ErrorsLib.OracleRequired.selector);
        box.addToken(token3, IOracle(address(0)));
        vm.stopPrank();
    }

    function testAllocateSlippageProtection() public {
        vm.startPrank(feeder);
        asset.approve(address(box), 100e18);
        box.deposit(100e18, feeder);
        vm.stopPrank();

        // Set oracle price to make allocation expensive
        oracle1.setPrice(0.5e36); // 1 asset = 2 tokens expected
        // But swapper gives 1:1, so we get less than expected

        vm.expectRevert(ErrorsLib.AllocationTooExpensive.selector);
        vm.prank(allocator);
        box.allocate(token1, 50e18, swapper, "");
    }

    function testAllocateWithSlippage() public {
        vm.startPrank(feeder);
        asset.approve(address(box), 100e18);
        box.deposit(100e18, feeder);
        vm.stopPrank();

        // Set swapper to have 1% slippage
        swapper.setSlippage(0.01 ether); // 1% slippage

        // This should work as 1% is within the 1% max slippage
        vm.prank(allocator);
        box.allocate(token1, 50e18, swapper, "");

        assertEq(asset.balanceOf(address(box)), 50e18);
        assertEq(token1.balanceOf(address(box)), 49.5e18); // 1% slippage
    }

    function testDeallocateFromToken() public {
        // Setup and allocate
        vm.startPrank(feeder);
        asset.approve(address(box), 100e18);
        box.deposit(100e18, feeder);
        vm.stopPrank();

        vm.prank(allocator);
        box.allocate(token1, 50e18, swapper, "");

        vm.expectEmit(true, true, true, true);
        emit Deallocation(token1, 25e18, 25e18, 25e18, 0, swapper, "");

        // Deallocate
        vm.prank(allocator);
        box.deallocate(token1, 25e18, swapper, "");

        assertEq(asset.balanceOf(address(box)), 75e18);
        assertEq(token1.balanceOf(address(box)), 25e18);
        assertEq(box.totalAssets(), 100e18); // 75 USDC + 25 token1

        // Approval should be revoked post-swap
        assertEq(token1.allowance(address(box), address(swapper)), 0);
    }

    function testDeallocateNonAllocator() public {
        vm.startPrank(feeder);
        asset.approve(address(box), 100e18);
        box.deposit(100e18, feeder);
        vm.stopPrank();

        vm.prank(allocator);
        box.allocate(token1, 50e18, swapper, "");

        // TODO why do we have this?
        // make sure timestamp is realistic, setting it in August 15, 2025
        //vm.warp(1755247499);

        vm.startPrank(nonAuthorized);
        vm.expectRevert(ErrorsLib.OnlyAllocatorsOrWinddown.selector);
        box.deallocate(token1, 25e18, swapper, "");
        vm.stopPrank();
    }

    function testDeallocateNonWhitelistedToken() public {
        vm.expectRevert(ErrorsLib.TokenNotWhitelisted.selector);
        vm.prank(allocator);
        box.deallocate(token3, 25e18, swapper, "");
    }

    function testDeallocateSlippageProtection() public {
        vm.startPrank(feeder);
        asset.approve(address(box), 100e18);
        box.deposit(100e18, feeder);
        vm.stopPrank();

        vm.prank(allocator);
        box.allocate(token1, 50e18, swapper, "");

        // Set oracle price to make deallocation expensive
        oracle1.setPrice(2e36); // 1 token = 2 asset expected
        // But swapper gives 1:1, so we get less than expected

        vm.expectRevert(ErrorsLib.TokenSaleNotGeneratingEnoughAssets.selector);
        vm.prank(allocator);
        box.deallocate(token1, 25e18, swapper, "");
    }

    function testReallocate() public {
        // Setup and allocate to token1
        vm.startPrank(feeder);
        asset.approve(address(box), 100e18);
        box.deposit(100e18, feeder);
        vm.stopPrank();

        vm.prank(allocator);
        box.allocate(token1, 50e18, swapper, "");

        vm.expectEmit(true, true, true, true);
        emit Reallocation(token1, token2, 25e18, 25e18, 25e18, 0, swapper, "");

        // Reallocate from token1 to token2
        vm.prank(allocator);
        box.reallocate(token1, token2, 25e18, swapper, "");

        assertEq(token1.balanceOf(address(box)), 25e18);
        assertEq(token2.balanceOf(address(box)), 25e18);

        // Approval should be revoked post-swap
        assertEq(token1.allowance(address(box), address(swapper)), 0);
    }

    function testReallocateNonAllocator() public {
        vm.expectRevert(ErrorsLib.OnlyAllocators.selector);
        vm.prank(nonAuthorized);
        box.reallocate(token1, token2, 25e18, swapper, "");
    }

    function testReallocateWhenShutdown() public {
        // Setup and allocate to token1
        vm.startPrank(feeder);
        asset.approve(address(box), 100e18);
        box.deposit(100e18, feeder);
        vm.stopPrank();
        vm.prank(allocator);
        box.allocate(token1, 50e18, swapper, "");

        // Entering shutdown mode
        vm.prank(guardian);
        box.shutdown();

        // Can reallocate during shutdown
        vm.prank(allocator);
        box.reallocate(token1, token2, 25e18, swapper, "");

        // But no longer when wind-down mode is reached
        vm.warp(block.timestamp + box.shutdownWarmup());
        vm.expectRevert(ErrorsLib.CannotDuringWinddown.selector);
        vm.prank(allocator);
        box.reallocate(token1, token2, 25e18, swapper, "");
    }

    function testReallocateNonWhitelistedTokens() public {
        vm.expectRevert(ErrorsLib.TokenNotWhitelisted.selector);
        vm.prank(allocator);
        box.reallocate(token3, token1, 25e18, swapper, "");

        vm.expectRevert(ErrorsLib.TokenNotWhitelisted.selector);
        vm.prank(allocator);
        box.reallocate(token1, token3, 25e18, swapper, "");
    }

    function testReallocateSlippageProtection() public {
        // Setup and allocate to token1
        vm.startPrank(feeder);
        asset.approve(address(box), 100e18);
        box.deposit(100e18, feeder);
        vm.stopPrank();

        vm.prank(allocator);
        box.allocate(token1, 50e18, swapper, "");

        // Set oracle prices to make reallocation expensive
        oracle1.setPrice(1e36); // 1 token1 = 1 asset
        oracle2.setPrice(0.5e36); // 1 token2 = 0.5 asset (so we expect 2 token2 for 1 token1)

        // But swapper gives 1:1, so we get less than expected (50% slippage)
        vm.expectRevert(ErrorsLib.ReallocationSlippageTooHigh.selector);
        vm.prank(allocator);
        box.reallocate(token1, token2, 25e18, swapper, "");
    }

    function testReallocateWithAcceptableSlippage() public {
        // Setup and allocate to token1
        vm.startPrank(feeder);
        asset.approve(address(box), 100e18);
        box.deposit(100e18, feeder);
        vm.stopPrank();

        vm.prank(allocator);
        box.allocate(token1, 50e18, swapper, "");

        // Set oracle prices with small difference
        oracle1.setPrice(1e36); // 1 token1 = 1 asset
        oracle2.setPrice(0.995e36); // 1 token2 = 0.995 asset (expect ~1.005 token2 for 1 token1)

        // Swapper gives 1:1, which is within 1% slippage tolerance
        vm.prank(allocator);
        box.reallocate(token1, token2, 25e18, swapper, "");

        assertEq(token1.balanceOf(address(box)), 25e18);
        assertEq(token2.balanceOf(address(box)), 25e18);
    }

    /////////////////////////////
    /// MULTIPLE INVESTMENT TOKEN TESTS
    /////////////////////////////

    function testMultipleInvestmentTokens() public {
        // Setup
        vm.startPrank(feeder);
        asset.approve(address(box), 200e18);
        box.deposit(200e18, feeder);
        vm.stopPrank();

        // Allocate to both assets
        vm.prank(allocator);
        box.allocate(token1, 50e18, swapper, "");

        vm.prank(allocator);
        box.allocate(token2, 50e18, swapper, "");

        assertEq(asset.balanceOf(address(box)), 100e18);
        assertEq(token1.balanceOf(address(box)), 50e18);
        assertEq(token2.balanceOf(address(box)), 50e18);
        assertEq(box.totalAssets(), 200e18); // 100 USDC + 50 token1 + 50 token2
        assertEq(box.tokensLength(), 2);
        assertEq(address(box.tokens(0)), address(token1));
        assertEq(address(box.tokens(1)), address(token2));
    }

    function testTotalAssetsWithDifferentPrices() public {
        vm.startPrank(feeder);
        asset.approve(address(box), 200e18);
        box.deposit(200e18, feeder);
        vm.stopPrank();

        // First allocate with normal prices
        vm.prank(allocator);
        box.allocate(token1, 50e18, swapper, "");

        vm.prank(allocator);
        box.allocate(token2, 50e18, swapper, "");

        // Then change oracle prices after allocation
        oracle1.setPrice(2e36); // 1 token1 = 2 asset
        oracle2.setPrice(0.5e36); // 1 token2 = 0.5 asset

        // Total assets = 100 asset + 50 token1 * 2 + 50 token2 * 0.5 = 100 + 100 + 25 = 225
        assertEq(box.totalAssets(), 225e18);
    }

    function testConvertToSharesWithInvestments() public {
        vm.startPrank(feeder);
        asset.approve(address(box), 200e18);
        box.deposit(200e18, feeder);
        vm.stopPrank();

        vm.prank(allocator);
        box.allocate(token1, 100e18, swapper, "");

        // Total assets = 100 asset + 100 token1 = 200
        // Total supply = 200 shares
        // convertToShares(100) = 100 * 200 / 200 = 100
        assertEq(box.convertToShares(100e18), 100e18);

        // Change token1 price to 2x
        oracle1.setPrice(2e36);
        // Total assets = 100 asset + 100 token1 * 2 = 300
        // convertToShares(100) = 100 * 200 / 300 = 66.666...
        assertEq(box.convertToShares(100e18), 66666666666666666666);
    }

    /////////////////////////////
    /// SLIPPAGE ACCUMULATION TESTS
    /////////////////////////////

    function testSlippageAccumulation() public {
        vm.startPrank(feeder);
        asset.approve(address(box), 1000e18);
        box.deposit(1000e18, feeder);
        vm.stopPrank();

        // Set swapper to have 1% slippage
        swapper.setSlippage(0.01 ether); // 1% slippage

        // Multiple allocations should accumulate slippage
        vm.startPrank(allocator);
        box.allocate(token1, 100e18, swapper, ""); // 0.1% of total assets slippage
        box.allocate(token1, 100e18, swapper, ""); // Another 0.1%
        box.allocate(token1, 100e18, swapper, ""); // Another 0.1%
        vm.stopPrank();

        // Should still work as we're under 1% total
        assertEq(token1.balanceOf(address(box)), 297e18); // 300 - 3% slippage
    }

    function testSlippageAccumulationLimit() public {
        vm.startPrank(feeder);
        asset.approve(address(box), 1000e18);
        box.deposit(1000e18, feeder);
        vm.stopPrank();

        // Set swapper to have 1% slippage
        swapper.setSlippage(0.01 ether); // 1% slippage

        vm.startPrank(allocator);
        // Multiple larger allocations that accumulate slippage faster
        // Each 100e18 allocation with 1% slippage should contribute more significantly
        box.allocate(token1, 100e18, swapper, ""); // ~0.1% slippage
        box.allocate(token1, 100e18, swapper, ""); // ~0.1% slippage
        box.allocate(token1, 100e18, swapper, ""); // ~0.1% slippage
        box.allocate(token1, 100e18, swapper, ""); // ~0.1% slippage
        box.allocate(token1, 100e18, swapper, ""); // ~0.1% slippage
        box.allocate(token1, 100e18, swapper, ""); // ~0.1% slippage
        box.allocate(token1, 100e18, swapper, ""); // ~0.1% slippage
        box.allocate(token1, 100e18, swapper, ""); // ~0.1% slippage
        box.allocate(token1, 100e18, swapper, ""); // ~0.1% slippage

        // This should fail as it would exceed 1% total slippage
        vm.expectRevert(ErrorsLib.TooMuchAccumulatedSlippage.selector);
        box.allocate(token1, 100e18, swapper, ""); // Would push over 1% total
        vm.stopPrank();
    }

    function testSlippageEpochReset() public {
        vm.startPrank(feeder);
        asset.approve(address(box), 1000e18);
        box.deposit(1000e18, feeder);
        vm.stopPrank();

        swapper.setSlippage(1);

        vm.startPrank(allocator);
        // Use up most of slippage budget
        box.allocate(token1, 90e18, swapper, ""); // 0.09% slippage

        // Warp forward 8 days to reset epoch
        vm.warp(block.timestamp + 8 days);

        // Should work again as epoch reset
        box.allocate(token1, 90e18, swapper, "");
        vm.stopPrank();
    }

    /////////////////////////////
    /// FUNDING TESTS
    /////////////////////////////

    function testFundingSetup() public view {
        assertTrue(box.isFunding(fundingMorpho));
        assertEq(box.fundingsLength(), 1);

        assertTrue(fundingMorpho.isFacility(facilityDataLtv80));
        assertEq(fundingMorpho.facilitiesLength(), 1);

        assertTrue(fundingMorpho.isCollateralToken(token1));
        assertEq(fundingMorpho.collateralTokensLength(), 1);

        assertTrue(fundingMorpho.isDebtToken(asset));
        assertEq(fundingMorpho.debtTokensLength(), 1);
    }

    /// @dev test that we can't add a funding token that is not already whitelisted as token at Box level
    function testAddFundingTokenNotWhitelisted() public {
        vm.startPrank(curator);

        bytes memory data = abi.encodeWithSelector(box.addFundingCollateral.selector, fundingMorpho, token3);
        box.submit(data);

        vm.expectRevert(ErrorsLib.TokenNotWhitelisted.selector);
        box.addFundingCollateral(fundingMorpho, token3);

        data = abi.encodeWithSelector(box.addFundingDebt.selector, fundingMorpho, token3);
        box.submit(data);

        vm.expectRevert(ErrorsLib.TokenNotWhitelisted.selector);
        box.addFundingDebt(fundingMorpho, token3);

        box.addTokenInstant(token3, oracle3);

        // Now it works (data are already submitted)
        box.addFundingCollateral(fundingMorpho, token3);
        box.addFundingDebt(fundingMorpho, token3);

        vm.stopPrank();
    }

    function testRemoveFundingOneCollateral() public {
        vm.startPrank(curator);

        box.removeFundingFacility(fundingMorpho, facilityDataLtv80);
        box.removeFundingDebt(fundingMorpho, asset);

        vm.expectRevert(ErrorsLib.CannotRemove.selector);
        box.removeFunding(fundingMorpho);

        box.removeFundingCollateral(fundingMorpho, token1);

        box.removeFunding(fundingMorpho);

        vm.stopPrank();
    }

    function testRemoveFundingOneDebt() public {
        vm.startPrank(curator);

        box.removeFundingFacility(fundingMorpho, facilityDataLtv80);
        box.removeFundingCollateral(fundingMorpho, token1);

        vm.expectRevert(ErrorsLib.CannotRemove.selector);
        box.removeFunding(fundingMorpho);

        box.removeFundingDebt(fundingMorpho, asset);

        box.removeFunding(fundingMorpho);

        vm.stopPrank();
    }

    function testRemoveFundingOrToken() public {
        token3.mint(address(box), 100e18);

        vm.startPrank(curator);

        // Don't need this one
        box.removeFundingFacility(fundingMorpho, facilityDataLtv80);
        box.removeFundingDebt(fundingMorpho, asset);

        // Shouldn't work after setup as there is a facility, debt and collateral
        vm.expectRevert(ErrorsLib.CannotRemove.selector);
        box.removeFunding(fundingMorpho);

        ERC20MockDecimals token4 = new ERC20MockDecimals(18);

        box.addTokenInstant(token4, oracle1); // Wrong oracle but fine for this test
        box.addFundingCollateralInstant(fundingMorpho, token4);

        vm.expectRevert(ErrorsLib.CannotRemove.selector);
        box.removeToken(token4);

        box.removeFundingCollateral(fundingMorpho, token4);
        vm.stopPrank();

        // Only curator can remove token
        vm.prank(address(allocator));
        vm.expectRevert(ErrorsLib.OnlyCurator.selector);
        box.removeToken(token4);

        vm.startPrank(curator);
        box.removeToken(token4);

        // Create a 90% lltv market and seed it
        box.addTokenInstant(token3, oracle3);
        box.addFundingCollateralInstant(fundingMorpho, token3);
        MarketParams memory marketParamsLocal = MarketParams(address(token3), address(token1), address(oracle1), address(irm), lltv90);
        morpho.createMarket(marketParamsLocal);
        token3.mint(address(curator), 100e18);
        token3.approve(address(morpho), 100e18);
        morpho.supply(marketParamsLocal, 100e18, 0, address(curator), "");
        bytes memory facilityDataLocal = fundingMorpho.encodeFacilityData(marketParamsLocal);
        box.addFundingDebtInstant(fundingMorpho, token3);
        box.addFundingFacilityInstant(fundingMorpho, facilityDataLocal);

        // No longer can remove token3 from Box, because there are token3 balance
        vm.expectRevert(ErrorsLib.TokenBalanceMustBeZero.selector);
        box.removeToken(token3);
        vm.stopPrank();

        // Withdraw all tokens
        vm.startPrank(address(box));
        token3.safeTransfer(address(curator), token3.balanceOf(address(box)));
        token1.safeTransfer(address(curator), token1.balanceOf(address(box)));
        vm.stopPrank();

        // Still can't remove token3 beacause there is a funding using it as debt token
        vm.startPrank(curator);
        vm.expectRevert(ErrorsLib.CannotRemove.selector);
        box.removeToken(token3);

        // Can't remove token1 from Box
        vm.expectRevert(ErrorsLib.CannotRemove.selector);
        box.removeToken(token1);

        vm.stopPrank();
        token1.mint(address(box), 10e18);
        vm.prank(allocator);
        box.pledge(fundingMorpho, facilityDataLocal, token1, 10e18);
        vm.startPrank(curator);

        // Can't remove collateral while pledged
        vm.expectRevert(ErrorsLib.CannotRemove.selector);
        box.removeFundingCollateral(fundingMorpho, token1);

        vm.stopPrank();
        vm.prank(allocator);
        box.borrow(fundingMorpho, facilityDataLocal, token3, 1e18);
        vm.startPrank(curator);

        // Can't remove debt token
        vm.expectRevert(ErrorsLib.CannotRemove.selector);
        box.removeFundingDebt(fundingMorpho, token3);

        vm.stopPrank();
        vm.startPrank(allocator);
        box.repay(fundingMorpho, facilityDataLocal, token3, 1e18);
        box.depledge(fundingMorpho, facilityDataLocal, token1, 10e18);
        vm.stopPrank();

        vm.startPrank(address(box));
        token1.safeTransfer(address(curator), token1.balanceOf(address(box)));
        token3.safeTransfer(address(curator), token3.balanceOf(address(box)));
        vm.stopPrank();

        vm.startPrank(curator);

        box.removeFundingFacility(fundingMorpho, facilityDataLocal);

        box.removeFundingCollateral(fundingMorpho, token3);

        // Still a debt token
        vm.expectRevert(ErrorsLib.CannotRemove.selector);
        box.removeToken(token3);

        box.removeFundingDebt(fundingMorpho, token3);

        box.removeToken(token3);

        box.removeFundingCollateral(fundingMorpho, token1);

        box.removeToken(token1);

        box.removeFunding(fundingMorpho);

        assertFalse(box.isFunding(fundingMorpho));
        assertEq(box.fundingsLength(), 0);

        vm.stopPrank();
    }

    IERC20 public flashToken;
    function onBoxFlash(IERC20 token, uint256, bytes calldata) external {
        require(msg.sender == address(box), "Only Box can call");
        require(token == flashToken, "Only asset token");

        // totalAssets() should return the cached NAV during flash, not revert
        uint256 assetsInFlash = box.totalAssets();
        assertEq(assetsInFlash, 50e18, "totalAssets during flash returns cached value");
    }

    function testFlashNav() public {
        asset.mint(address(feeder), 50e18);
        vm.startPrank(feeder);
        asset.approve(address(box), 50e18);
        box.deposit(50e18, feeder);
        vm.stopPrank();

        vm.prank(curator);
        box.setIsAllocator(address(this), true);

        assertEq(box.totalAssets(), 50e18, "Initial total assets is 50e18");

        token1.mint(address(this), 100e18); // Add some investment token to have non-trivial nav

        // Set a random price
        oracle1.setPrice(2e36); // 1 token1 = 2 asset, so nav should be 50 + 100*2 = 250
        token1.approve(address(box), 100e18);
        flashToken = token1;
        box.flash(token1, 100e18, "");

        assertEq(box.totalAssets(), 50e18, "After flash, total assets is 50e18");

        // Same test with the underlying asset
        asset.mint(address(this), 100e18);
        asset.approve(address(box), 100e18);
        flashToken = asset;
        box.flash(asset, 100e18, "");

        assertEq(box.totalAssets(), 50e18, "After flash, total assets is 50e18");
    }

    function testFlashWrongToken() public {
        token3.mint(address(allocator), 50e18);

        vm.startPrank(allocator);
        token3.approve(address(box), 50e18);
        vm.expectRevert(ErrorsLib.TokenNotWhitelisted.selector);
        box.flash(token3, 10e18, "");
        vm.stopPrank();
    }

    function testFlashCannotDepositDuringCallback() public {
        // Setup: Deposit initial funds and make malicious callback a feeder
        asset.mint(address(feeder), 100e18);
        vm.startPrank(feeder);
        asset.approve(address(box), 100e18);
        box.deposit(100e18, feeder);
        vm.stopPrank();

        // Create malicious callback and give it allocator and feeder roles
        MaliciousFlashCallback maliciousCallback = new MaliciousFlashCallback(box, asset);

        vm.prank(curator);
        box.setIsAllocator(address(maliciousCallback), true);

        vm.prank(curator);
        box.submit(abi.encodeWithSelector(IBox.setIsFeeder.selector, address(maliciousCallback), true));
        vm.warp(block.timestamp + 1);
        vm.prank(curator);
        box.setIsFeeder(address(maliciousCallback), true);

        // Fund the callback with assets to deposit
        asset.mint(address(maliciousCallback), 100e18);

        // Flash the asset and attempt to deposit during callback
        asset.mint(address(maliciousCallback), 50e18);
        maliciousCallback.setScenario(0); // DEPOSIT

        vm.prank(address(maliciousCallback));
        asset.approve(address(box), 50e18);

        vm.expectRevert(ErrorsLib.ReentryNotAllowed.selector);
        vm.prank(address(maliciousCallback));
        box.flash(asset, 50e18, "");
    }

    function testFlashCannotMintDuringCallback() public {
        // Setup: Deposit initial funds
        asset.mint(address(feeder), 100e18);
        vm.startPrank(feeder);
        asset.approve(address(box), 100e18);
        box.deposit(100e18, feeder);
        vm.stopPrank();

        // Create malicious callback and give it allocator and feeder roles
        MaliciousFlashCallback maliciousCallback = new MaliciousFlashCallback(box, asset);

        vm.prank(curator);
        box.setIsAllocator(address(maliciousCallback), true);

        vm.prank(curator);
        box.submit(abi.encodeWithSelector(IBox.setIsFeeder.selector, address(maliciousCallback), true));
        vm.warp(block.timestamp + 1);
        vm.prank(curator);
        box.setIsFeeder(address(maliciousCallback), true);

        // Fund the callback with assets to mint
        asset.mint(address(maliciousCallback), 150e18);

        // Flash the asset and attempt to mint during callback
        maliciousCallback.setScenario(1); // MINT

        vm.prank(address(maliciousCallback));
        asset.approve(address(box), 150e18);

        vm.expectRevert(ErrorsLib.ReentryNotAllowed.selector);
        vm.prank(address(maliciousCallback));
        box.flash(asset, 50e18, "");
    }

    function testFlashCannotWithdrawDuringCallback() public {
        // Setup: Deposit initial funds
        asset.mint(address(feeder), 100e18);
        vm.startPrank(feeder);
        asset.approve(address(box), 100e18);
        box.deposit(100e18, feeder);
        vm.stopPrank();

        // Create malicious callback with shares
        MaliciousFlashCallback maliciousCallback = new MaliciousFlashCallback(box, asset);

        // Give callback some shares
        asset.mint(address(maliciousCallback), 100e18);
        vm.prank(curator);
        box.submit(abi.encodeWithSelector(IBox.setIsFeeder.selector, address(maliciousCallback), true));
        vm.warp(block.timestamp + 1);
        vm.prank(curator);
        box.setIsFeeder(address(maliciousCallback), true);

        vm.startPrank(address(maliciousCallback));
        asset.approve(address(box), 100e18);
        box.deposit(100e18, address(maliciousCallback));
        vm.stopPrank();

        // Give callback allocator role
        vm.prank(curator);
        box.setIsAllocator(address(maliciousCallback), true);

        // Flash and attempt to withdraw during callback
        asset.mint(address(maliciousCallback), 50e18);
        maliciousCallback.setScenario(2); // WITHDRAW

        vm.prank(address(maliciousCallback));
        asset.approve(address(box), 50e18);

        vm.expectRevert(ErrorsLib.ReentryNotAllowed.selector);
        vm.prank(address(maliciousCallback));
        box.flash(asset, 50e18, "");
    }

    function testFlashCannotRedeemDuringCallback() public {
        // Setup: Deposit initial funds
        asset.mint(address(feeder), 100e18);
        vm.startPrank(feeder);
        asset.approve(address(box), 100e18);
        box.deposit(100e18, feeder);
        vm.stopPrank();

        // Create malicious callback with shares
        MaliciousFlashCallback maliciousCallback = new MaliciousFlashCallback(box, asset);

        // Give callback some shares
        asset.mint(address(maliciousCallback), 100e18);
        vm.prank(curator);
        box.submit(abi.encodeWithSelector(IBox.setIsFeeder.selector, address(maliciousCallback), true));
        vm.warp(block.timestamp + 1);
        vm.prank(curator);
        box.setIsFeeder(address(maliciousCallback), true);

        vm.startPrank(address(maliciousCallback));
        asset.approve(address(box), 100e18);
        box.deposit(100e18, address(maliciousCallback));
        vm.stopPrank();

        // Give callback allocator role
        vm.prank(curator);
        box.setIsAllocator(address(maliciousCallback), true);

        // Flash and attempt to redeem during callback
        asset.mint(address(maliciousCallback), 50e18);
        maliciousCallback.setScenario(3); // REDEEM

        vm.prank(address(maliciousCallback));
        asset.approve(address(box), 50e18);

        vm.expectRevert(ErrorsLib.ReentryNotAllowed.selector);
        vm.prank(address(maliciousCallback));
        box.flash(asset, 50e18, "");
    }

    /////////////////////////////
    /// SHUTDOWN TESTS
    /////////////////////////////

    function testShutdownGuardian() public {
        vm.expectEmit(true, true, true, true);
        emit Shutdown(guardian);

        vm.prank(guardian);
        box.shutdown();

        assertTrue(box.isShutdown());
        assertEq(box.shutdownTime(), block.timestamp);
        assertEq(box.maxDeposit(feeder), 0);
        assertEq(box.maxMint(feeder), 0);
    }

    function testShutdownCurator() public {
        vm.expectEmit(true, true, true, true);
        emit Shutdown(curator);

        vm.prank(curator);
        box.shutdown();

        assertTrue(box.isShutdown());
        assertEq(box.shutdownTime(), block.timestamp);
    }

    function testShutdownNonGuardian() public {
        vm.expectRevert(ErrorsLib.OnlyGuardianOrCuratorCanShutdown.selector);
        vm.prank(nonAuthorized);
        box.shutdown();

        vm.expectRevert(ErrorsLib.OnlyGuardianOrCuratorCanShutdown.selector);
        vm.prank(owner);
        box.shutdown();

        vm.expectRevert(ErrorsLib.OnlyGuardianOrCuratorCanShutdown.selector);
        vm.prank(allocator);
        box.shutdown();

        vm.expectRevert(ErrorsLib.OnlyGuardianOrCuratorCanShutdown.selector);
        vm.prank(feeder);
        box.shutdown();
    }

    function testShutdownAlreadyShutdown() public {
        vm.prank(guardian);
        box.shutdown();

        vm.expectRevert(ErrorsLib.AlreadyShutdown.selector);
        vm.prank(guardian);
        box.shutdown();
    }

    function testDeallocateAfterShutdown() public {
        vm.startPrank(feeder);
        asset.approve(address(box), 100e18);
        box.deposit(100e18, feeder);
        vm.stopPrank();

        vm.prank(allocator);
        box.allocate(token1, 50e18, swapper, "");

        vm.prank(guardian);
        box.shutdown();

        // Anyone should be able to deallocate after shutdown
        vm.startPrank(nonAuthorized);

        // But need to wait box.shutdownWarmup() before deallocation
        vm.expectRevert(ErrorsLib.OnlyAllocatorsOrWinddown.selector);
        box.deallocate(token1, 25e18, swapper, "");

        // After warmup it should work
        vm.warp(block.timestamp + box.shutdownWarmup() + 1);
        box.deallocate(token1, 25e18, swapper, "");

        assertEq(token1.balanceOf(address(box)), 25e18);
    }

    function testShutdownSlippageTolerance() public {
        vm.startPrank(feeder);
        asset.approve(address(box), 100e18);
        box.deposit(100e18, feeder);
        vm.stopPrank();

        vm.prank(allocator);
        box.allocate(token1, 50e18, swapper, "");

        vm.prank(guardian);
        box.shutdown();

        // Test that shutdown mode allows deallocation
        vm.prank(allocator);
        box.deallocate(token1, 25e18, swapper, "");

        assertEq(token1.balanceOf(address(box)), 25e18);
    }

    function testWithdrawAfterShutdown() public {
        vm.startPrank(feeder);
        asset.approve(address(box), 200e18);
        box.deposit(200e18, feeder);
        vm.stopPrank();

        // Allocate some funds but leave enough asset for withdrawal
        vm.prank(allocator);
        box.allocate(token1, 100e18, swapper, "");

        vm.prank(guardian);
        box.shutdown();

        // Try to withdraw - should work with available asset
        vm.prank(feeder);
        box.withdraw(50e18, feeder, feeder);

        // Go after wind-down
        vm.warp(block.timestamp + box.shutdownWarmup() + 1);

        vm.prank(feeder);
        box.withdraw(50e18, feeder, feeder);

        // Verify withdrawal worked
        assertEq(asset.balanceOf(address(box)), 0e18);
        assertEq(token1.balanceOf(address(box)), 100e18);
    }

    function testWinddownAccess() public {
        vm.startPrank(guardian);

        // Guardian cannot change oracle - only curator can (before winddown)
        vm.expectRevert(ErrorsLib.OnlyCurator.selector);
        box.changeTokenOracle(token1, oracle3);

        box.shutdown();

        // Still only curator can change oracle (after shutdown but before winddown)
        vm.expectRevert(ErrorsLib.OnlyCurator.selector);
        box.changeTokenOracle(token1, oracle3);

        vm.warp(block.timestamp + box.shutdownWarmup());
        assertEq(box.isWinddown(), true);

        vm.expectRevert(ErrorsLib.NotAllowed.selector);
        box.changeTokenOracle(token1, oracle3);

        vm.stopPrank();

        // Check that the curator lost control of change of oracle
        vm.startPrank(curator);

        vm.expectRevert(ErrorsLib.NotAllowed.selector);
        box.changeTokenOracle(token1, oracle3);

        vm.expectRevert(ErrorsLib.CannotDuringWinddown.selector);
        box.setGuardian(curator);

        vm.stopPrank();

        vm.startPrank(guardian);

        // Guardian can change oracle only after the slippage duration
        vm.warp(block.timestamp + box.shutdownSlippageDuration());

        vm.expectEmit(true, true, true, true);
        emit EventsLib.TokenOracleChanged(token1, oracle3);
        box.changeTokenOracle(token1, oracle3);

        vm.stopPrank();

        // Curator still guardian after wind-down + slippage duration
        vm.startPrank(curator);

        vm.expectRevert(ErrorsLib.OnlyGuardian.selector);
        box.changeTokenOracle(token1, oracle3);

        vm.expectRevert(ErrorsLib.CannotDuringWinddown.selector);
        box.setGuardian(curator);

        vm.stopPrank();
    }

    /////////////////////////////
    /// TIMELOCK GOVERNANCE TESTS
    /////////////////////////////

    function testTimelockPattern() public {
        vm.startPrank(curator);

        // Test setting max slippage with new timelock pattern
        uint256 newSlippage = 0.001234 ether; // 0.1234%
        bytes memory slippageData = abi.encodeWithSelector(box.setMaxSlippage.selector, newSlippage);
        box.submit(slippageData);

        // Try to execute too early - should fail
        vm.expectRevert(ErrorsLib.TimelockNotExpired.selector);
        (bool success, ) = address(box).call(slippageData);

        // Warp to after timelock
        vm.warp(block.timestamp + 1 days + 1);

        // Execute the change
        (success, ) = address(box).call(slippageData);
        require(success, "Failed to set slippage");
        assertEq(box.maxSlippage(), newSlippage);

        vm.stopPrank();
    }

    function testTimelockSubmitNonCurator() public {
        bytes memory slippageData = abi.encodeWithSelector(box.setMaxSlippage.selector, 0.02 ether);
        vm.expectRevert(ErrorsLib.OnlyCurator.selector);
        vm.prank(nonAuthorized);
        box.submit(slippageData);
    }

    function testTimelockRevoke() public {
        // Curator should be able to revoke a submitted action
        vm.startPrank(curator);
        bytes memory slippageData = abi.encodeWithSelector(box.setMaxSlippage.selector, 0.02 ether);
        box.submit(slippageData);
        assertEq(box.executableAt(slippageData), block.timestamp + 1 days);

        box.revoke(slippageData);
        assertEq(box.executableAt(slippageData), 0);

        // Should fail to execute after revoke
        vm.warp(block.timestamp + 1 days + 1);
        vm.expectRevert(ErrorsLib.DataNotTimelocked.selector);
        (bool success, ) = address(box).call(slippageData);
        vm.stopPrank();

        // Curator should also be able to revoke a submitted action
        vm.startPrank(curator);
        uint256 currentTime = block.timestamp;
        bytes4 selector = box.setMaxSlippage.selector;
        uint256 timelockDuration = box.timelock(selector);
        uint256 timelockDurationExplicit = 1 days;
        assertEq(box.timelock(selector), 1 days);
        assertEq(timelockDuration, timelockDurationExplicit);

        box.submit(slippageData);
        assertEq(box.executableAt(slippageData), currentTime + timelockDuration);
        vm.stopPrank();

        vm.startPrank(guardian);
        box.revoke(slippageData);
        assertEq(box.executableAt(slippageData), 0);
        vm.stopPrank();

        // Should fail to execute after revoke
        vm.startPrank(curator);
        vm.warp(block.timestamp + 1 days + 1);
        vm.expectRevert(ErrorsLib.DataNotTimelocked.selector);
        (success, ) = address(box).call(slippageData);
        vm.stopPrank();
    }

    function testTimelockRevokeNonCurator() public {
        vm.prank(curator);
        bytes memory slippageData = abi.encodeWithSelector(box.setMaxSlippage.selector, 0.02 ether);
        box.submit(slippageData);

        vm.expectRevert(ErrorsLib.OnlyCuratorOrGuardian.selector);
        vm.prank(nonAuthorized);
        box.revoke(slippageData);
    }

    function testTimelockManipulation() public {
        vm.startPrank(curator);

        assert(box.timelock(box.setGuardian.selector) == 1 days);

        // Can't decrease from 1 day to 2 days
        bytes memory data = abi.encodeWithSelector(box.decreaseTimelock.selector, box.setGuardian.selector, 2 days);
        box.submit(data);

        // Check that the timelock of 1 days on setGuardian has not passed
        vm.expectRevert(ErrorsLib.TimelockNotExpired.selector);
        box.decreaseTimelock(box.setGuardian.selector, 2 days);

        // Let's go to the end of the timelock
        vm.warp(1 days + 1);

        // Then the issue is that we can't decrease from 1 day to 2 days
        vm.expectRevert(ErrorsLib.TimelockNotDecreasing.selector);
        box.decreaseTimelock(box.setGuardian.selector, 2 days);

        vm.expectEmit(true, true, true, true);
        emit EventsLib.TimelockRevoked(box.decreaseTimelock.selector, data, address(curator));
        box.revoke(data);

        // Can't increase from 1 day to 0 days (no timelock needed)
        vm.expectRevert(ErrorsLib.TimelockNotIncreasing.selector);
        box.increaseTimelock(box.setGuardian.selector, 0 days);

        data = abi.encodeWithSelector(box.decreaseTimelock.selector, box.setGuardian.selector, 0 days);
        box.submit(data);

        assert(box.timelock(box.setGuardian.selector) == 1 days);

        // Check that the timelock of 1 days on setGuardian has not passed
        vm.expectRevert(ErrorsLib.TimelockNotExpired.selector);
        box.decreaseTimelock(box.setGuardian.selector, 0 days);

        vm.warp(2 days + 1); // + 1 day

        vm.expectEmit(true, true, true, true);
        emit EventsLib.TimelockDecreased(box.setGuardian.selector, 0 days, address(curator));
        box.decreaseTimelock(box.setGuardian.selector, 0 days);
        assert(box.timelock(box.setGuardian.selector) == 0 days);

        vm.expectEmit(true, true, true, true);
        emit EventsLib.TimelockIncreased(box.setGuardian.selector, 1 days, address(curator));
        box.increaseTimelock(box.setGuardian.selector, 1 days);
        assert(box.timelock(box.setGuardian.selector) == 1 days);

        // We submit again to decrease to 0 days
        box.submit(data);

        assert(box.timelock(box.setGuardian.selector) == 1 days);

        box.abdicateTimelock(box.setGuardian.selector);
        assert(box.timelock(box.setGuardian.selector) == TIMELOCK_DISABLED);

        vm.warp(10 days + 1); // Far later

        // We check that we can't call the decrease timelock after having abdicated
        vm.expectRevert(ErrorsLib.InvalidTimelock.selector);
        box.decreaseTimelock(box.setGuardian.selector, 0 days);

        vm.stopPrank();
    }

    function testTimelockAbdicate() public {
        vm.startPrank(curator);

        box.abdicateTimelock(box.setGuardian.selector);
        bytes memory data = abi.encodeWithSelector(box.decreaseTimelock.selector, box.setGuardian.selector, 2 days);

        vm.expectRevert();
        box.submit(data);

        vm.stopPrank();
    }

    function testTimelockNotCurator() public {
        vm.startPrank(nonAuthorized);

        // Can't decrease from 1 day to 2 days
        bytes memory data = abi.encodeWithSelector(box.decreaseTimelock.selector, box.setGuardian.selector, 0 days);
        vm.expectRevert(ErrorsLib.OnlyCurator.selector);
        box.submit(data);

        vm.expectRevert(ErrorsLib.OnlyCurator.selector);
        box.increaseTimelock(box.setGuardian.selector, 5 days);

        vm.expectRevert(ErrorsLib.OnlyCurator.selector);
        box.abdicateTimelock(box.setGuardian.selector);

        vm.stopPrank();
    }

    function testCuratorSubmitAccept() public {
        address newCurator = address(0x99);

        vm.prank(owner); // setCurator requires owner
        box.setCurator(newCurator);

        assertEq(box.curator(), newCurator);
    }

    function testGuardianSubmitAccept() public {
        address newGuardian = address(0x99);

        vm.startPrank(curator);
        bytes memory guardianData = abi.encodeWithSelector(box.setGuardian.selector, newGuardian);
        box.submit(guardianData);
        vm.warp(block.timestamp + 1 days + 1);
        (bool success, ) = address(box).call(guardianData);
        require(success, "Failed to set guardian");
        vm.stopPrank();

        assertEq(box.guardian(), newGuardian);
    }

    function testAllocatorSubmitAccept() public {
        address newAllocator = address(0x99);

        vm.startPrank(curator);
        bytes memory allocatorData = abi.encodeWithSelector(box.setIsAllocator.selector, newAllocator, true);
        box.submit(allocatorData);
        vm.warp(block.timestamp + 1 days + 1);
        (bool success, ) = address(box).call(allocatorData);
        require(success, "Failed to set allocator");
        vm.stopPrank();

        assertTrue(box.isAllocator(newAllocator));
    }

    function testAllocatorRemove() public {
        vm.startPrank(curator);
        bytes memory allocatorData = abi.encodeWithSelector(box.setIsAllocator.selector, allocator, false);
        box.submit(allocatorData);
        vm.warp(block.timestamp + 1 days + 1);
        (bool success, ) = address(box).call(allocatorData);
        require(success, "Failed to remove allocator");
        vm.stopPrank();

        assertFalse(box.isAllocator(allocator));
    }

    function testFeederSubmitAccept() public {
        address newFeeder = address(0x99);

        vm.startPrank(curator);
        bytes memory feederData = abi.encodeWithSelector(box.setIsFeeder.selector, newFeeder, true);
        box.submit(feederData);
        vm.warp(block.timestamp + 1 days + 1);
        (bool success, ) = address(box).call(feederData);
        require(success, "Failed to set feeder");
        vm.stopPrank();

        assertTrue(box.isFeeder(newFeeder));
    }

    function testSlippageSubmitAccept(uint256 newSlippage) public {
        vm.assume(newSlippage < MAX_SLIPPAGE_LIMIT);

        vm.startPrank(curator);
        bytes memory slippageData = abi.encodeWithSelector(box.setMaxSlippage.selector, newSlippage);
        box.submit(slippageData);
        vm.warp(block.timestamp + 1 days + 1);
        (bool success, ) = address(box).call(slippageData);
        require(success, "Failed to set slippage");
        vm.stopPrank();

        assertEq(box.maxSlippage(), newSlippage);
    }

    function testSlippageSubmitTooHigh() public {
        vm.startPrank(curator);
        bytes memory slippageData = abi.encodeWithSelector(box.setMaxSlippage.selector, 0.15 ether);
        box.submit(slippageData);
        vm.warp(block.timestamp + 1 days + 1);
        vm.expectRevert(ErrorsLib.SlippageTooHigh.selector);
        box.setMaxSlippage(0.15 ether);
        vm.stopPrank();
    }

    function testInvestmentTokenSubmitAccept() public {
        vm.startPrank(curator);
        bytes memory tokenData = abi.encodeWithSelector(box.addToken.selector, token3, oracle3);
        box.submit(tokenData);
        vm.warp(block.timestamp + 1 days + 1);
        (bool success, ) = address(box).call(tokenData);
        require(success, "Failed to add investment token");
        vm.stopPrank();

        assertTrue(box.isToken(token3));
        assertEq(address(box.oracles(token3)), address(oracle3));
        assertEq(box.tokensLength(), 3);
    }

    function testInvestmentTokenRemove() public {
        vm.startPrank(curator);

        vm.expectRevert(ErrorsLib.CannotRemove.selector);
        box.removeToken(token1);

        // Remove it from collateral
        box.removeFundingFacility(fundingMorpho, facilityDataLtv80);
        box.removeFundingCollateral(fundingMorpho, token1);

        box.removeToken(token1);
        vm.stopPrank();

        assertFalse(box.isToken(token1));
        assertEq(address(box.oracles(token1)), address(0));
        assertEq(box.tokensLength(), 1);
    }

    function testInvestmentTokenRemoveWithBalance() public {
        // Allocate to token1 first
        vm.startPrank(feeder);
        asset.approve(address(box), 100e18);
        box.deposit(100e18, feeder);
        vm.stopPrank();

        vm.prank(allocator);
        box.allocate(token1, 50e18, swapper, "");

        // Try to remove token with balance - should fail at execution stage
        vm.startPrank(curator);
        // Remove it from collateral
        box.removeFundingFacility(fundingMorpho, facilityDataLtv80);
        box.removeFundingCollateral(fundingMorpho, token1);

        bytes memory tokenData = abi.encodeWithSelector(box.removeToken.selector, token1);
        box.submit(tokenData);
        vm.expectRevert(ErrorsLib.TokenBalanceMustBeZero.selector);
        box.removeToken(token1);
        vm.stopPrank();
    }

    function testOwnerChange() public {
        address newOwner = address(0x99);

        vm.prank(owner);
        box.transferOwnership(newOwner);

        assertEq(box.owner(), newOwner);
    }

    function testOwnerChangeNonOwner() public {
        vm.expectRevert(ErrorsLib.OnlyOwner.selector);
        vm.prank(nonAuthorized);
        box.transferOwnership(address(0x99));
    }

    function testOwnerChangeInvalidAddress() public {
        vm.expectRevert(ErrorsLib.InvalidAddress.selector);
        vm.prank(owner);
        box.transferOwnership(address(0));
    }

    /////////////////////////////
    /// EDGE CASE TESTS
    /////////////////////////////

    function testTooManyTokensAdded() public {
        vm.startPrank(curator);
        for (uint256 i = box.tokensLength(); i < MAX_TOKENS; i++) {
            box.addTokenInstant(IERC20(address(uint160(i))), IOracle(address(uint160(i))));
        }

        bytes memory token1Data = abi.encodeWithSelector(box.addToken.selector, address(uint160(MAX_TOKENS)), address(uint160(MAX_TOKENS)));
        box.submit(token1Data);
        vm.expectRevert(ErrorsLib.TooManyTokens.selector);
        box.addToken(IERC20(address(uint160(MAX_TOKENS))), IOracle(address(uint160(MAX_TOKENS))));
        vm.stopPrank();
    }

    function testDepositWithPriceChanges() public {
        // Initial deposit
        vm.startPrank(feeder);
        asset.approve(address(box), 200e18);
        box.deposit(100e18, feeder);
        vm.stopPrank();

        // Allocate
        vm.prank(allocator);
        box.allocate(token1, 50e18, swapper, "");

        // Change asset price to 2x
        oracle1.setPrice(2e36);

        // Second deposit should get fewer shares due to increased total assets
        vm.startPrank(feeder);
        uint256 shares = box.deposit(100e18, feeder);
        vm.stopPrank();

        // Total assets before second deposit = 50 asset + 50 token1 * 2 = 150
        // Shares for 100 asset = 100 * 100 / 150 = 66.666...
        assertEq(shares, 66666666666666666666);
    }

    function testWithdrawWithInsufficientLiquidity() public {
        vm.startPrank(feeder);
        asset.approve(address(box), 100e18);
        box.deposit(100e18, feeder);
        vm.stopPrank();

        // Allocate all asset
        vm.prank(allocator);
        box.allocate(token1, 100e18, swapper, "");

        // Try to withdraw - should fail due to insufficient liquidity
        vm.expectRevert(ErrorsLib.InsufficientLiquidity.selector);
        vm.prank(feeder);
        box.withdraw(50e18, feeder, feeder);
    }

    function testConvertFunctionsEdgeCases() public view {
        // Test with zero total supply
        assertEq(box.convertToShares(100e18), 100e18);
        assertEq(box.convertToAssets(100e18), 100e18);

        // Test with zero amounts
        assertEq(box.convertToShares(0), 0);
        assertEq(box.convertToAssets(0), 0);
    }

    function testPreviewFunctionsConsistency() public {
        vm.startPrank(feeder);
        asset.approve(address(box), 200e18);

        // Test preview deposit
        uint256 previewShares = box.previewDeposit(100e18);
        uint256 actualShares = box.deposit(100e18, feeder);
        assertEq(previewShares, actualShares);

        // Test preview mint
        uint256 previewAssets = box.previewMint(50e18);
        uint256 actualAssets = box.mint(50e18, feeder);
        assertEq(previewAssets, actualAssets);

        // Test preview withdraw
        uint256 previewWithdrawShares = box.previewWithdraw(50e18);
        uint256 actualWithdrawShares = box.withdraw(50e18, feeder, feeder);
        assertEq(previewWithdrawShares, actualWithdrawShares);

        // Test preview redeem
        uint256 previewRedeemAssets = box.previewRedeem(50e18);
        uint256 actualRedeemAssets = box.redeem(50e18, feeder, feeder);
        assertEq(previewRedeemAssets, actualRedeemAssets);

        vm.stopPrank();
    }

    function testMaxFunctionsAfterShutdown() public {
        vm.startPrank(feeder);
        asset.approve(address(box), 100e18);
        box.deposit(100e18, feeder);
        vm.stopPrank();

        vm.prank(guardian);
        box.shutdown();

        assertEq(box.maxDeposit(feeder), 0);
        assertEq(box.maxMint(feeder), 0);
        assertEq(box.maxWithdraw(feeder), 100e18); // Can still withdraw
        assertEq(box.maxRedeem(feeder), 100e18); // Can still redeem
    }

    function testRecoverFromShutdown() public {
        vm.startPrank(feeder);
        asset.approve(address(box), 100e18);
        box.deposit(100e18, feeder);
        vm.stopPrank();

        assertEq(box.isShutdown(), false);

        vm.prank(guardian);
        box.shutdown();
        assertEq(box.isShutdown(), true);

        assertEq(box.maxDeposit(feeder), 0);
        assertEq(box.maxMint(feeder), 0);
        assertEq(box.maxWithdraw(feeder), 100e18); // Can still withdraw
        assertEq(box.maxRedeem(feeder), 100e18); // Can still redeem

        vm.prank(curator);
        vm.expectRevert(ErrorsLib.OnlyGuardianCanRecover.selector);
        box.recover();
        assertEq(box.isShutdown(), true);

        vm.prank(guardian);
        box.recover();
        assertEq(box.isShutdown(), false);

        assertEq(box.maxDeposit(feeder), type(uint256).max);
        assertEq(box.maxMint(feeder), type(uint256).max);
        assertEq(box.maxWithdraw(feeder), 100e18); // Can still withdraw
        assertEq(box.maxRedeem(feeder), 100e18); // Can still redeem

        // Test allocators functions
        vm.startPrank(allocator);
        box.allocate(token1, 100e18, swapper, "");
        box.reallocate(token1, token2, 100e18, swapper, "");
        box.deallocate(token2, 100e18, swapper, "");
        vm.stopPrank();

        // Test shurdown and go until wind-down to check that we can't recover during wind-down
        vm.prank(guardian);
        box.shutdown();
        assertEq(box.isShutdown(), true);

        vm.warp(block.timestamp + box.shutdownWarmup() + 1);

        vm.prank(guardian);
        vm.expectRevert(ErrorsLib.CannotRecoverAfterWinddown.selector);
        box.recover();
        assertEq(box.isShutdown(), true);
    }

    function testComplexScenario() public {
        // Complex scenario with multiple users, tokens, and operations

        // Setup multiple users
        asset.mint(user1, 1000e18);
        asset.mint(user2, 1000e18);

        vm.startPrank(curator);
        bytes memory user1Data = abi.encodeWithSelector(box.setIsFeeder.selector, user1, true);
        box.submit(user1Data);
        vm.warp(block.timestamp + 1 days + 1);
        (bool success, ) = address(box).call(user1Data);
        require(success, "Failed to set user1 as feeder");

        bytes memory user2Data = abi.encodeWithSelector(box.setIsFeeder.selector, user2, true);
        box.submit(user2Data);
        vm.warp(block.timestamp + 1 days + 1);
        (success, ) = address(box).call(user2Data);
        require(success, "Failed to set user2 as feeder");
        vm.stopPrank();

        // User1 deposits
        vm.startPrank(user1);
        asset.approve(address(box), 500e18);
        box.deposit(500e18, user1);
        vm.stopPrank();

        // Allocate to token1
        vm.prank(allocator);
        box.allocate(token1, 200e18, swapper, "");

        // Change token1 price
        oracle1.setPrice(1.5e36);

        // User2 deposits (should get fewer shares due to price increase)
        vm.startPrank(user2);
        asset.approve(address(box), 300e18);
        uint256 user2Shares = box.deposit(300e18, user2);
        vm.stopPrank();

        // Total assets = 600 asset + 200 token1 * 1.5 = 900
        // User2 shares = 300 * 500 / 600 = 250 (approximately)
        // But the actual calculation is more complex due to rounding
        assertGt(user2Shares, 150e18);
        assertLt(user2Shares, 300e18);

        // Allocate to token2
        vm.prank(allocator);
        box.allocate(token2, 150e18, swapper, "");

        // User1 transfers some shares to user2
        vm.prank(user1);
        box.transfer(user2, 100e18);

        // Reallocate between assets - set compatible oracle prices first
        oracle2.setPrice(1.5e36); // Match token1 price to avoid slippage issues
        vm.prank(allocator);
        box.reallocate(token1, token2, 50e18, swapper, "");

        // User2 redeems some shares
        vm.prank(user2);
        box.redeem(50e18, user2, user2);

        // Verify final state is consistent
        assertEq(box.totalSupply(), box.balanceOf(user1) + box.balanceOf(user2));
        assertGt(box.totalAssets(), 0);
        assertGt(asset.balanceOf(address(box)) + token1.balanceOf(address(box)) + token2.balanceOf(address(box)), 0);
    }

    function testAllocateReentrancyAttack() public {
        // Setup
        vm.startPrank(feeder);
        asset.approve(address(box), 10e18);
        box.deposit(10e18, feeder);
        vm.stopPrank();

        // Allocate to token1
        vm.prank(allocator);
        box.allocate(token1, 5e18, swapper, "");

        maliciousSwapper.setBox(box);

        maliciousSwapper.setScenario(maliciousSwapper.ALLOCATE());
        vm.prank(allocator);
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        box.allocate(token1, 1e18, maliciousSwapper, "");

        maliciousSwapper.setScenario(maliciousSwapper.DEALLOCATE());
        vm.prank(allocator);
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        box.deallocate(token1, 1e18, maliciousSwapper, "");

        maliciousSwapper.setScenario(maliciousSwapper.REALLOCATE());
        vm.prank(allocator);
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        box.reallocate(token1, token2, 1e18, maliciousSwapper, "");

        assertEq(box.totalAssets(), 10e18);
        assertEq(asset.balanceOf(address(box)), 5e18);
        assertEq(token1.balanceOf(address(box)), 5e18);
    }

    /////////////////////////////
    /// COMPREHENSIVE ALLOCATION EVENT TESTS
    /////////////////////////////

    function testAllocateInvalidSwapper() public {
        vm.startPrank(feeder);
        asset.approve(address(box), 100e18);
        box.deposit(100e18, feeder);
        vm.stopPrank();

        vm.expectRevert();
        vm.prank(allocator);
        box.allocate(token1, 50e18, ISwapper(address(0)), "");
    }

    function testDeallocateInvalidSwapper() public {
        vm.startPrank(feeder);
        asset.approve(address(box), 100e18);
        box.deposit(100e18, feeder);
        vm.stopPrank();

        vm.prank(allocator);
        box.allocate(token1, 50e18, swapper, "");

        vm.expectRevert();
        vm.prank(allocator);
        box.deallocate(token1, 25e18, ISwapper(address(0)), "");
    }

    function testReallocateInvalidSwapper() public {
        vm.startPrank(feeder);
        asset.approve(address(box), 100e18);
        box.deposit(100e18, feeder);
        vm.stopPrank();

        vm.prank(allocator);
        box.allocate(token1, 50e18, swapper, "");

        vm.expectRevert();
        vm.prank(allocator);
        box.reallocate(token1, token2, 25e18, ISwapper(address(0)), "");
    }

    function testAllocateEventWithPositiveSlippage() public {
        // Setup with a better price than oracle (negative slippage = positive performance)
        vm.startPrank(feeder);
        asset.approve(address(box), 100e18);
        box.deposit(100e18, feeder);
        vm.stopPrank();

        // Set oracle to expect fewer tokens
        oracle1.setPrice(1.1e36); // 1 token = 1.1 assets, so we expect 45.45 tokens for 50 assets

        // Expect event with negative slippage percentage (positive performance)
        // Expected: 45.454545454545454546 tokens (50 / 1.1, rounded up), Actual: 50e18 tokens
        vm.expectEmit(true, true, true, true);
        emit Allocation(token1, 50e18, 45454545454545454546, 50e18, -99999999999999999, swapper, ""); // ~-10% slippage

        vm.prank(allocator);
        box.allocate(token1, 50e18, swapper, "");

        assertEq(asset.balanceOf(address(box)), 50e18);
        assertEq(token1.balanceOf(address(box)), 50e18);
    }

    function testDeallocateEventWithPositiveSlippage() public {
        vm.startPrank(feeder);
        asset.approve(address(box), 100e18);
        box.deposit(100e18, feeder);
        vm.stopPrank();

        vm.prank(allocator);
        box.allocate(token1, 50e18, swapper, "");

        // Set oracle to expect fewer assets
        oracle1.setPrice(0.9e36); // 1 token = 0.9 assets, so we expect 22.5 assets for 25 tokens

        // Expect event with negative slippage percentage (positive performance)
        // Expected: 22.5e18 assets (25 * 0.9), Actual: 25e18 assets
        vm.expectEmit(true, true, true, true);
        emit Deallocation(token1, 25e18, 22500000000000000000, 25e18, -0.111111111111111111e18, swapper, ""); // ~-11% slippage

        vm.prank(allocator);
        box.deallocate(token1, 25e18, swapper, "");

        assertEq(asset.balanceOf(address(box)), 75e18);
        assertEq(token1.balanceOf(address(box)), 25e18);
    }

    function testReallocateEventWithPositiveSlippage() public {
        vm.startPrank(feeder);
        asset.approve(address(box), 100e18);
        box.deposit(100e18, feeder);
        vm.stopPrank();

        vm.prank(allocator);
        box.allocate(token1, 50e18, swapper, "");

        // Set oracles to expect fewer token2
        oracle1.setPrice(1e36); // 1 token1 = 1 asset
        oracle2.setPrice(1.1e36); // 1 token2 = 1.1 assets, so we expect ~22.73 token2 for 25 token1

        // Expect event with negative slippage percentage (positive performance)
        // Expected: 22.727272727272727273 token2 (25 * 1 / 1.1, rounded up), Actual: 25e18 token2
        vm.expectEmit(true, true, true, true, address(box));
        emit Reallocation(token1, token2, 25e18, 22727272727272727273, 25e18, -99999999999999999, swapper, ""); // ~-10% slippage

        vm.prank(allocator);
        box.reallocate(token1, token2, 25e18, swapper, "");

        assertEq(token1.balanceOf(address(box)), 25e18);
        assertEq(token2.balanceOf(address(box)), 25e18);
    }

    function testAllocateWithSwapperSpendingLess() public {
        vm.startPrank(feeder);
        asset.approve(address(box), 100e18);
        box.deposit(100e18, feeder);
        vm.stopPrank();

        // The swapper will actually spend the full 50 as authorized
        // Box tracks assetsSpent based on actual balance changes

        // Expect event with 50 assets spent
        vm.expectEmit(true, true, true, true);
        emit Allocation(token1, 50e18, 50e18, 50e18, 0, swapper, "");

        vm.prank(allocator);
        box.allocate(token1, 50e18, swapper, "");

        assertEq(asset.balanceOf(address(box)), 50e18); // 100 - 50
        assertEq(token1.balanceOf(address(box)), 50e18);
    }

    function testDeallocateWithSwapperSpendingLess() public {
        vm.startPrank(feeder);
        asset.approve(address(box), 100e18);
        box.deposit(100e18, feeder);
        vm.stopPrank();

        vm.prank(allocator);
        box.allocate(token1, 50e18, swapper, "");

        // The swapper will actually spend the full 25 as authorized
        // Box tracks tokensSpent based on actual balance changes

        // Expect event with 25 tokens spent
        vm.expectEmit(true, true, true, true);
        emit Deallocation(token1, 25e18, 25e18, 25e18, 0, swapper, "");

        vm.prank(allocator);
        box.deallocate(token1, 25e18, swapper, "");

        assertEq(asset.balanceOf(address(box)), 75e18); // 50 + 25
        assertEq(token1.balanceOf(address(box)), 25e18); // 50 - 25
    }

    function testReallocateWithSwapperSpendingLess() public {
        vm.startPrank(feeder);
        asset.approve(address(box), 100e18);
        box.deposit(100e18, feeder);
        vm.stopPrank();

        vm.prank(allocator);
        box.allocate(token1, 50e18, swapper, "");

        // The swapper will actually spend the full 25 as authorized
        // Box tracks fromSpent based on actual balance changes

        // Expect event with 25 tokens spent and received
        vm.expectEmit(true, true, true, true, address(box));
        emit Reallocation(token1, token2, 25e18, 25e18, 25e18, 0, swapper, "");

        vm.prank(allocator);
        box.reallocate(token1, token2, 25e18, swapper, "");

        assertEq(token1.balanceOf(address(box)), 25e18); // 50 - 25
        assertEq(token2.balanceOf(address(box)), 25e18);
    }

    function testAllocateWithCustomData() public {
        vm.startPrank(feeder);
        asset.approve(address(box), 100e18);
        box.deposit(100e18, feeder);
        vm.stopPrank();

        bytes memory customData = abi.encode("custom", 123, address(0x999));

        // Expect event with custom data
        vm.expectEmit(true, true, true, true);
        emit Allocation(token1, 50e18, 50e18, 50e18, 0, swapper, customData);

        vm.prank(allocator);
        box.allocate(token1, 50e18, swapper, customData);

        assertEq(asset.balanceOf(address(box)), 50e18);
        assertEq(token1.balanceOf(address(box)), 50e18);
    }

    function testDeallocateDuringShutdownSlippageTolerance() public {
        vm.startPrank(feeder);
        asset.approve(address(box), 100e18);
        box.deposit(100e18, feeder);
        vm.stopPrank();

        vm.prank(allocator);
        box.allocate(token1, 50e18, swapper, "");

        vm.prank(guardian);
        box.shutdown();

        // Set high slippage swapper
        MockSwapper highSlippageSwapper = new MockSwapper();
        highSlippageSwapper.setSlippage(0.005 ether); // 0.5% slippage
        token1.mint(address(highSlippageSwapper), 1000e18);
        asset.mint(address(highSlippageSwapper), 1000e18);

        // Wait for warmup period
        vm.warp(block.timestamp + box.shutdownWarmup() + 1);

        // At start of shutdown slippage duration, should fail with 5% slippage
        vm.expectRevert(ErrorsLib.TokenSaleNotGeneratingEnoughAssets.selector);
        vm.prank(nonAuthorized);
        box.deallocate(token1, 25e18, highSlippageSwapper, "");

        // Warp halfway through shutdown slippage duration (5 days out of 10)
        vm.warp(block.timestamp + box.shutdownSlippageDuration() / 2);

        // Now slippage tolerance should be ~0.5%, so this should work
        vm.expectEmit(true, true, true, true);
        emit Deallocation(token1, 25e18, 25e18, 24.875e18, 5000000000000000, highSlippageSwapper, ""); // 0.5% slippage

        vm.prank(nonAuthorized);
        box.deallocate(token1, 25e18, highSlippageSwapper, "");

        assertEq(token1.balanceOf(address(box)), 25e18);
    }

    function testAllocateEventSlippageCalculation() public {
        vm.startPrank(feeder);
        asset.approve(address(box), 1000e18);
        box.deposit(1000e18, feeder);
        vm.stopPrank();

        // Test exact slippage boundary (1% max slippage)
        swapper.setSlippage(0.01 ether); // Exactly 1% slippage

        // With 1% slippage on 100 assets, we get 99 tokens
        // Expected: 100, Actual: 99, Slippage: 1/100 = 1%
        vm.expectEmit(true, true, true, true);
        emit Allocation(token1, 100e18, 100e18, 99e18, 0.01e18, swapper, ""); // 1% slippage

        vm.prank(allocator);
        (uint256 expected, uint256 received) = box.allocate(token1, 100e18, swapper, "");
        assertEq(expected, 100e18);
        assertEq(received, 99e18);

        assertEq(token1.balanceOf(address(box)), 99e18);
    }

    function testDeallocateEventSlippageCalculation() public {
        vm.startPrank(feeder);
        asset.approve(address(box), 1000e18);
        box.deposit(1000e18, feeder);
        vm.stopPrank();

        vm.prank(allocator);
        box.allocate(token1, 100e18, swapper, "");

        // Reset swapper slippage for deallocation
        swapper.setSlippage(0.01 ether); // Exactly 1% slippage

        // With 1% slippage on 50 tokens, we get 49.5 assets
        // Expected: 50, Actual: 49.5, Slippage: 0.5/50 = 1%
        vm.expectEmit(true, true, true, true);
        emit Deallocation(token1, 50e18, 50e18, 49.5e18, 0.01e18, swapper, ""); // 1% slippage

        vm.prank(allocator);
        (uint256 expected, uint256 received) = box.deallocate(token1, 50e18, swapper, "");
        assertEq(expected, 50e18);
        assertEq(received, 49.5e18);

        assertEq(asset.balanceOf(address(box)), 949.5e18); // 900 + 49.5
    }

    function testDeallocateSlippageAccountingNoDoubleConversion() public {
        // Deposit and allocate
        vm.startPrank(feeder);
        asset.approve(address(box), 1000e18);
        box.deposit(1000e18, feeder);
        vm.stopPrank();

        // Allocate 500 assets to token1 at price 1:1 to build a position
        vm.prank(allocator);
        box.allocate(token1, 500e18, swapper, "");

        // Raise oracle price significantly so price != 1
        oracle1.setPrice(5e36); // 1 token = 5 assets

        // Use a price-aware swapper that pays according to oracle price with 1% slippage
        PriceAwareSwapper pSwapper = new PriceAwareSwapper(oracle1);
        pSwapper.setSlippage(0.01 ether); // Exactly 1% slippage

        // Provide liquidity to the swapper
        asset.mint(address(pSwapper), 10000e18);

        // Deallocate 40 tokens. Expected assets = 40 * 5 = 200; actual = 198; loss = 2 assets
        // Get NAV before deallocate for slippage calculation (now uses cached pre-swap NAV)
        uint256 totalBefore = box.totalAssets();

        vm.prank(allocator);
        box.deallocate(token1, 40e18, pSwapper, "");

        // Expected accumulated slippage is loss / totalAssetsBefore (cached NAV used during swap)
        uint256 expectedLoss = 2e18; // 2 assets lost
        uint256 expectedAccumulated = (expectedLoss * 1e18) / totalBefore;

        // Ensure value matches what contract recorded (no extra price multiplication)
        assertApproxEqAbs(box.accumulatedSlippage(), expectedAccumulated, 1); // within 1 wei
        assertLt(box.accumulatedSlippage(), box.maxSlippage()); // should be well under 1%
    }

    function testDeallocateSlippageConversion() public {
        // Setup: deposit and allocate
        vm.startPrank(feeder);
        asset.approve(address(box), 1000e18);
        box.deposit(1000e18, feeder);
        vm.stopPrank();

        // Allocate 500 assets to token1 at 1:1 via simple swapper
        vm.prank(allocator);
        box.allocate(token1, 500e18, swapper, "");

        // Set a high oracle price so the buggy double-conversion would explode
        uint256 price = 500e36; // 1 token = 500 assets
        oracle1.setPrice(price);

        // Price-aware swapper paying per oracle with 1% slippage
        PriceAwareSwapper pSwapper = new PriceAwareSwapper(oracle1);
        pSwapper.setSlippage(0.01 ether); // Exactly 1% slippage
        asset.mint(address(pSwapper), 10000e18);

        // Sell a small amount of tokens so true slippage is small vs total assets
        uint256 tokensToSell = 2e18; // expects 1000 assets, loses 10 assets (1%)

        // Hypothetical values under the old bug (loss converted by price again)
        uint256 expectedAssets = (tokensToSell * price) / ORACLE_PRECISION; // 1000 assets
        uint256 expectedLoss = expectedAssets / 100; // 1% loss = 10 assets
        uint256 inflatedValue = (expectedLoss * price) / ORACLE_PRECISION; // 10 * 500 = 5000 assets

        // Get NAV before deallocate for slippage calculation (now uses cached pre-swap NAV)
        uint256 totalBefore = box.totalAssets();

        // Execute deallocation with fixed logic - should NOT revert
        vm.prank(allocator);
        box.deallocate(token1, tokensToSell, pSwapper, "");

        // With the buggy logic, accumulated slippage would have been inflatedValue / totalAssets
        uint256 totalAfter = box.totalAssets();
        uint256 oldBugPct = (inflatedValue * PRECISION) / totalAfter; // in 1e18 precision
        assertGe(oldBugPct, box.maxSlippage(), "Old buggy accounting would not have reverted as expected");

        // Actual accumulated slippage must equal actual loss / totalBefore (cached NAV used during swap)
        uint256 expectedAccumulated = (expectedLoss * PRECISION) / totalBefore;
        assertApproxEqAbs(box.accumulatedSlippage(), expectedAccumulated, 1);
        assertLt(box.accumulatedSlippage(), box.maxSlippage());
    }

    function testReallocateEventSlippageCalculation() public {
        vm.startPrank(feeder);
        asset.approve(address(box), 1000e18);
        box.deposit(1000e18, feeder);
        vm.stopPrank();

        vm.prank(allocator);
        box.allocate(token1, 100e18, swapper, "");

        // Set swapper with 0.5% slippage
        swapper.setSlippage(0); // Reset to 0 first
        backupSwapper.setSlippage(0.01 ether); // Use backup swapper with 1% slippage

        // Same price oracles, with 1% slippage on swap
        // From 50 token1 we expect 50 token2, but get 49.5 due to slippage
        vm.expectEmit(true, true, true, true, address(box));
        emit Reallocation(token1, token2, 50e18, 50e18, 49.5e18, 10000000000000000, backupSwapper, ""); // 1% slippage

        vm.prank(allocator);
        (uint256 expected, uint256 received) = box.reallocate(token1, token2, 50e18, backupSwapper, "");
        assertEq(expected, 50e18);
        assertEq(received, 49.5e18);

        assertEq(token1.balanceOf(address(box)), 50e18); // 100 - 50
        assertEq(token2.balanceOf(address(box)), 49.5e18);
    }

    function testMultipleAllocationsEventSequence() public {
        vm.startPrank(feeder);
        asset.approve(address(box), 1000e18);
        box.deposit(1000e18, feeder);
        vm.stopPrank();

        // First allocation
        vm.expectEmit(true, true, true, true);
        emit Allocation(token1, 100e18, 100e18, 100e18, 0, swapper, "");

        vm.startPrank(allocator);
        box.allocate(token1, 100e18, swapper, "");

        // Second allocation to different token
        vm.expectEmit(true, true, true, true);
        emit Allocation(token2, 150e18, 150e18, 150e18, 0, swapper, "");
        box.allocate(token2, 150e18, swapper, "");

        // Reallocate between tokens
        vm.expectEmit(true, true, true, true, address(box));
        emit Reallocation(token1, token2, 50e18, 50e18, 50e18, 0, swapper, "");
        box.reallocate(token1, token2, 50e18, swapper, "");

        // Deallocate from token2
        vm.expectEmit(true, true, true, true);
        emit Deallocation(token2, 100e18, 100e18, 100e18, 0, swapper, "");
        box.deallocate(token2, 100e18, swapper, "");
        vm.stopPrank();

        // Verify final state
        assertEq(asset.balanceOf(address(box)), 850e18); // 1000 - 100 - 150 + 100
        assertEq(token1.balanceOf(address(box)), 50e18); // 100 - 50
        assertEq(token2.balanceOf(address(box)), 100e18); // 150 + 50 - 100
    }

    function testSwapperSpendingTooMuch() public {
        vm.startPrank(feeder);
        asset.approve(address(box), 100e18);
        box.deposit(100e18, feeder);
        vm.stopPrank();

        // Create a malicious swapper that tries to spend more than authorized
        MockSwapper greedySwapper = new MockSwapper();

        // Mock the behavior: swapper tries to take 60 but is only authorized 50
        // The actual transfer will fail due to insufficient allowance
        // But let's test the require check in the contract

        vm.prank(allocator);
        vm.expectRevert(); // Will revert in transferFrom due to trying to take too much
        box.allocate(token1, 50e18, greedySwapper, "");
    }

    function testConstructorValidations() public {
        // Test invalid asset address
        vm.expectRevert(ErrorsLib.InvalidAddress.selector);
        new Box(address(0), address(0x1), address(0x2), "Test", "TST", 100, 1 days, 7 days, 1 days);

        // Test invalid owner address
        vm.expectRevert(ErrorsLib.InvalidAddress.selector);
        new Box(address(asset), address(0), address(0x2), "Test", "TST", 100, 1 days, 7 days, 1 days);

        // Test slippage too high (MAX_SLIPPAGE_LIMIT is 0.01 ether = 10^16)
        vm.expectRevert(ErrorsLib.SlippageTooHigh.selector);
        new Box(address(asset), address(0x1), address(0x2), "Test", "TST", 0.01 ether + 1, 1 days, 7 days, 1 days);

        // Test invalid slippage epoch duration
        vm.expectRevert(ErrorsLib.InvalidValue.selector);
        new Box(address(asset), address(0x1), address(0x2), "Test", "TST", 100, 0, 7 days, 1 days);

        // Test invalid shutdown slippage duration
        vm.expectRevert(ErrorsLib.InvalidValue.selector);
        new Box(address(asset), address(0x1), address(0x2), "Test", "TST", 100, 1 days, 0, 1 days);

        // Test shutdown warmup too high (MAX_SHUTDOWN_WARMUP is 365 days)
        vm.expectRevert(ErrorsLib.InvalidValue.selector);
        new Box(address(asset), address(0x1), address(0x2), "Test", "TST", 100, 1 days, 7 days, 365 days + 1);
    }

    function testMaxDepositAndMintDuringShutdown() public {
        // First shutdown the box
        vm.prank(guardian);
        box.shutdown();

        // maxDeposit should return 0 during shutdown
        uint256 maxDep = box.maxDeposit(user1);
        assertEq(maxDep, 0, "maxDeposit should be 0 during shutdown");

        // maxMint should return 0 during shutdown
        uint256 maxMnt = box.maxMint(user1);
        assertEq(maxMnt, 0, "maxMint should be 0 during shutdown");
    }

    function testConvertFunctionsWithZeroSupply() public {
        // Deploy a new box with no shares minted
        Box emptyBox = new Box(address(asset), owner, curator, "Empty", "EMPTY", 100, 1 days, 7 days, 1 days);

        // With zero supply, convertToShares should return same as input
        uint256 shares = emptyBox.convertToShares(1000e18);
        assertEq(shares, 1000e18);

        // With zero supply, convertToAssets should return same as input
        uint256 assets = emptyBox.convertToAssets(1000e18);
        assertEq(assets, 1000e18);

        // previewMint with zero supply
        uint256 mintAssets = emptyBox.previewMint(1000e18);
        assertEq(mintAssets, 1000e18);
    }

    function testWithdrawWithMaxAllowance() public {
        // First deposit some assets
        vm.startPrank(feeder);
        asset.approve(address(box), 1000e18);
        box.deposit(1000e18, feeder);
        vm.stopPrank();

        // Give user1 max allowance
        vm.prank(feeder);
        box.approve(user1, type(uint256).max);

        // User1 withdraws using the allowance
        vm.prank(user1);
        box.withdraw(100e18, user1, feeder);

        // Allowance should still be max
        assertEq(box.allowance(feeder, user1), type(uint256).max);
    }

    function testRedeemWithMaxAllowance() public {
        // First deposit some assets
        vm.startPrank(feeder);
        asset.approve(address(box), 1000e18);
        uint256 shares = box.deposit(1000e18, feeder);
        vm.stopPrank();

        // Give user1 max allowance
        vm.prank(feeder);
        box.approve(user1, type(uint256).max);

        // User1 redeems using the allowance
        vm.prank(user1);
        box.redeem(shares / 10, user1, feeder);

        // Allowance should still be max
        assertEq(box.allowance(feeder, user1), type(uint256).max);
    }

    function testSlippageAccumulationAndReset() public {
        // Setup: give box some assets to allocate
        vm.prank(feeder);
        asset.transfer(address(box), 1000e18);

        // Set swapper to have small slippage
        swapper.setSlippage(0.001 ether); // 0.1%

        // First allocation
        vm.prank(allocator);
        box.allocate(token1, 100e18, swapper, "");

        // Get initial slippage
        uint256 initialSlippage = box.accumulatedSlippage();
        assertTrue(initialSlippage > 0, "Should have some slippage");

        // Do another allocation in same epoch - should accumulate
        vm.prank(allocator);
        box.allocate(token1, 100e18, swapper, "");

        uint256 accumulatedSlippageAmount = box.accumulatedSlippage();
        assertTrue(accumulatedSlippageAmount > initialSlippage, "Slippage should accumulate within epoch");

        // Move past epoch duration
        skip(box.slippageEpochDuration() + 1);

        // Allocate again - should reset accumulator first
        vm.prank(allocator);
        box.allocate(token1, 100e18, swapper, "");

        // Accumulator should have reset and only contain slippage from latest allocation
        uint256 newSlippage = box.accumulatedSlippage();
        assertTrue(newSlippage < accumulatedSlippageAmount, "Accumulator should reset after epoch");
    }

    function testGuardianRecoveryFlow() public {
        // Cannot recover when not shutdown
        vm.prank(guardian);
        vm.expectRevert(ErrorsLib.NotShutdown.selector);
        box.recover();

        // Shutdown the box
        vm.prank(guardian);
        box.shutdown();
        assertTrue(box.isShutdown());

        // Guardian can recover before winddown
        vm.prank(guardian);
        box.recover();
        assertFalse(box.isShutdown());

        // Shutdown again and wait for winddown
        vm.prank(guardian);
        box.shutdown();
        skip(8 days); // Past warmup period

        // Cannot recover after winddown
        vm.prank(guardian);
        vm.expectRevert(ErrorsLib.CannotRecoverAfterWinddown.selector);
        box.recover();
    }

    function testTimelockSubmitAndRevoke() public {
        vm.startPrank(curator);

        // Submit a timelocked transaction
        bytes memory data = abi.encodeWithSelector(box.setMaxSlippage.selector, 500);
        box.submit(data);

        // Cannot submit same data again
        vm.expectRevert(ErrorsLib.DataAlreadyTimelocked.selector);
        box.submit(data);

        // Revoke the transaction
        box.revoke(data);

        // After revoke, can submit again
        box.submit(data);

        vm.stopPrank();

        // Guardian can also revoke
        vm.prank(guardian);
        box.revoke(data);
    }

    function testIncreaseAndDecreaseTimelock() public {
        vm.startPrank(curator);

        // Increase timelock for a function
        box.increaseTimelock(box.setMaxSlippage.selector, 2 days);
        assertEq(box.timelock(box.setMaxSlippage.selector), 2 days);

        // Cannot decrease without going through timelock
        vm.expectRevert(ErrorsLib.DataNotTimelocked.selector);
        box.decreaseTimelock(box.setMaxSlippage.selector, 1 days);

        // Submit decrease through timelock
        bytes memory data = abi.encodeWithSelector(box.decreaseTimelock.selector, box.setMaxSlippage.selector, 1 days);
        box.submit(data);
        skip(2 days);
        box.decreaseTimelock(box.setMaxSlippage.selector, 1 days);
        assertEq(box.timelock(box.setMaxSlippage.selector), 1 days);

        // Test abdicate - makes function permanently timelocked
        box.abdicateTimelock(box.addToken.selector);
        assertEq(box.timelock(box.addToken.selector), TIMELOCK_DISABLED);

        vm.stopPrank();
    }

    function testWinddownSlippageTolerance() public {
        // Give box assets
        vm.prank(feeder);
        asset.transfer(address(box), 1000e18);

        // Allocate some tokens first
        vm.prank(allocator);
        box.allocate(token1, 100e18, swapper, "");

        // Deallocate can work during winddown without debt requirement
        vm.prank(guardian);
        box.shutdown();

        // During warmup, normal operations work
        vm.prank(allocator);
        box.deallocate(token1, 50e18, swapper, "");

        uint256 assetsAfterWarmup = asset.balanceOf(address(box));
        assertTrue(assetsAfterWarmup > 900e18, "Deallocation should work during warmup");

        // Skip to winddown phase
        skip(8 days); // Past warmup, now in winddown

        // During winddown, deallocate should work for anyone (no debt required for deallocate)
        vm.prank(user1); // Anyone can deallocate during winddown
        box.deallocate(token1, 20e18, swapper, "");

        uint256 assetsAfterWinddown = asset.balanceOf(address(box));
        assertTrue(assetsAfterWinddown > assetsAfterWarmup, "Deallocation should work during winddown");

        // Additional test: verify winddown increases slippage tolerance over time
        // The longer we wait in winddown, the more slippage is tolerated
        uint256 remainingTokens = token1.balanceOf(address(box));

        // Skip further into winddown - slippage tolerance increases
        skip(box.shutdownSlippageDuration() / 2);

        // Deallocate remaining tokens with normal slippage
        if (remainingTokens > 0) {
            vm.prank(allocator);
            box.deallocate(token1, remainingTokens / 2, swapper, "");
        }

        // Verify deallocation worked
        assertTrue(token1.balanceOf(address(box)) < remainingTokens, "Deallocation in late winddown should work");
    }

    function testWinddownAllocationLimitWithDebt() public {
        // Setup: deposit assets and add token to whitelist
        vm.startPrank(feeder);
        asset.approve(address(box), 1000e18);
        box.deposit(1000e18, feeder);
        vm.stopPrank();

        // Add the funding module to the box
        vm.startPrank(curator);
        box.submit(abi.encodeWithSelector(box.addFunding.selector, mockFunding));
        vm.warp(block.timestamp + 1);
        box.addFunding(mockFunding);
        vm.stopPrank();

        // Set up debt of 100 token1 (worth 100 assets at 1:1 price)
        mockFunding.setDebtBalance(token1, 100e18);

        // Trigger shutdown and move to winddown
        vm.prank(guardian);
        box.shutdown();
        vm.warp(block.timestamp + box.shutdownWarmup() + 1);
        assertTrue(box.isWinddown(), "Should be in winddown");

        // At this point, with 100 token1 debt and 1:1 price, we should be able to allocate up to ~100 assets worth
        // The exact limit depends on slippage tolerance which increases over time during winddown

        // Get current slippage tolerance
        uint256 currentTime = block.timestamp;
        uint256 winddownStart = box.shutdownTime() + box.shutdownWarmup();
        uint256 timeElapsed = currentTime - winddownStart;
        uint256 slippageTolerance = (timeElapsed * MAX_SLIPPAGE_LIMIT) / box.shutdownSlippageDuration();

        // Calculate maximum allowed allocation
        // The formula converts debt tokens to assets value, then adjusts for slippage
        // debtBalance = 100e18 tokens
        // oraclePrice = 1e36 (price scaled by ORACLE_PRECISION = 1e36)
        // debtValue in assets = debtBalance * oraclePrice / ORACLE_PRECISION = 100e18 * 1e36 / 1e36 = 100e18
        // maxAllocation = debtValue * PRECISION / (PRECISION - slippageTolerance)
        // Note: Contract rounds up both neededValue and maxAllocation, so we must do the same
        uint256 neededTokens = 100e18; // debtBalance
        uint256 neededValue = Math.mulDiv(neededTokens, 1e36, ORACLE_PRECISION, Math.Rounding.Ceil);
        uint256 maxAllocation = Math.mulDiv(neededValue, PRECISION, PRECISION - slippageTolerance, Math.Rounding.Ceil);

        // Try to allocate more than allowed - should fail
        vm.prank(nonAuthorized);
        vm.expectRevert(ErrorsLib.InvalidAmount.selector);
        box.allocate(token1, maxAllocation + 1, swapper, "");

        // Allocate exactly at the limit - should succeed
        vm.prank(nonAuthorized);
        box.allocate(token1, maxAllocation, swapper, "");

        // Verify allocation happened
        assertTrue(token1.balanceOf(address(box)) > 0, "Should have allocated tokens");
    }

    function testWinddownAllocationWithoutDebtShouldFail() public {
        // Setup: deposit assets and add token to whitelist
        vm.startPrank(feeder);
        asset.approve(address(box), 1000e18);
        box.deposit(1000e18, feeder);
        vm.stopPrank();

        // Trigger shutdown and move to winddown
        vm.prank(guardian);
        box.shutdown();
        vm.warp(block.timestamp + box.shutdownWarmup() + 1);
        assertTrue(box.isWinddown(), "Should be in winddown");

        // With no debt, allocation should not be allowed during winddown
        vm.prank(nonAuthorized);
        vm.expectRevert(ErrorsLib.OnlyAllocatorsOrWinddown.selector);
        box.allocate(token1, 50e18, swapper, "");
    }

    // Test for 5.2 Read-only Reentrancy protection
    // Verifies that totalAssets() returns cached NAV during swaps, preventing manipulation
    function testReadOnlyReentrancyProtection() public {
        // Setup: deposit assets
        vm.startPrank(feeder);
        asset.approve(address(box), 1000e18);
        box.deposit(1000e18, feeder);
        vm.stopPrank();

        // Allocate some tokens to create a non-trivial position
        vm.startPrank(allocator);
        box.allocate(token1, 500e18, swapper, "");
        vm.stopPrank();

        // Set oracle price for token1
        oracle1.setPrice(2e36); // 1 token1 = 2 assets

        // NAV should be: 500 assets + 500 tokens * 2 = 1500
        assertEq(box.totalAssets(), 1500e18, "Initial NAV should be 1500");

        // Create a malicious swapper that attempts read-only reentrancy
        ReadOnlyReentrancySwapper reentrancySwapper = new ReadOnlyReentrancySwapper(box);
        reentrancySwapper.setOracle(oracle1);
        asset.mint(address(reentrancySwapper), 1000e18); // Give it assets to return for the swap

        // The malicious swapper will:
        // 1. Take tokens from Box in sell()
        // 2. Try to read totalAssets() (should get cached value, not manipulated value)
        // 3. Return tokens
        vm.prank(allocator);
        (uint256 expected, uint256 received) = box.deallocate(token1, 100e18, reentrancySwapper, "");

        // Verify the malicious swapper observed the CACHED (pre-swap) NAV, not the manipulated NAV
        uint256 observedNav = reentrancySwapper.observedTotalAssets();
        assertEq(observedNav, 1500e18, "Swapper should observe cached pre-swap NAV");

        // Verify the swapper did NOT see the manipulated NAV (which would be lower)
        // Manipulated NAV would be: 500 assets + 400 tokens * 2 = 1300
        assertTrue(observedNav != 1300e18, "Swapper should NOT see manipulated mid-swap NAV");

        // After the swap completes, totalAssets() should return the real (post-swap) NAV
        // Post-swap NAV: 700 assets + 400 tokens * 2 = 1500 (same because we return equal value)
        assertEq(box.totalAssets(), 1500e18, "Post-swap NAV should be correct");
    }

    // A malicious swapper could use a borrow or depledge and steal the funds
    function testFundingSwapAttack() public {
        // Setup: deposit assets and add token to whitelist
        vm.startPrank(feeder);
        asset.approve(address(box), 1000e18);
        box.deposit(1000e18, feeder);
        vm.stopPrank();

        // Add the funding module to the box
        bytes memory data = "";
        vm.startPrank(curator);
        box.submit(abi.encodeWithSelector(box.addFunding.selector, mockFunding));
        vm.warp(block.timestamp + 1);
        box.addFunding(mockFunding);

        MaliciousFundingSwapper fundingSwapper = new MaliciousFundingSwapper();
        token1.mint(address(mockFunding), 1000e18);

        box.setIsAllocator(address(fundingSwapper), true);
        vm.stopPrank();

        vm.startPrank(allocator);
        fundingSwapper.setBox(box);
        fundingSwapper.setFunding(mockFunding);
        fundingSwapper.setScenario(fundingSwapper.BORROW());

        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        box.allocate(token1, 500e18, fundingSwapper, data);

        fundingSwapper.setScenario(fundingSwapper.DEPLEDGE());

        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        box.allocate(token1, 500e18, fundingSwapper, data);
        vm.stopPrank();
    }
}
