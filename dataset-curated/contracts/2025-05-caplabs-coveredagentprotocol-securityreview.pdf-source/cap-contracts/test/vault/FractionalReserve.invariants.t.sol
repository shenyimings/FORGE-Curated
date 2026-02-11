// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { Vault } from "../../contracts/vault/Vault.sol";
import { MockAccessControl } from "../mocks/MockAccessControl.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";
import { MockERC4626 } from "../mocks/MockERC4626.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { RandomAssetUtils } from "../deploy/utils/RandomAssetUtils.sol";
import { StdUtils } from "forge-std/StdUtils.sol";
import { Test } from "forge-std/Test.sol";
import { Vm } from "forge-std/Vm.sol";

contract TestVault is Vault {
    function initialize(
        string memory _name,
        string memory _symbol,
        address _accessControl,
        address _feeAuction,
        address _oracle,
        address[] calldata _assets,
        address _insuranceFund
    ) external initializer {
        __Vault_init(_name, _symbol, _accessControl, _feeAuction, _oracle, _assets, _insuranceFund);
    }
}

contract VaultInvariantsTest is Test {
    TestVaultHandler public handler;
    TestVault public vault;
    address[] public assets;
    MockAccessControl public accessControl;
    address public constant MOCK_FEE_AUCTION = address(2);

    // Mock tokens and vaults
    MockERC20[] private mockTokens;
    MockERC4626[] private mockVaults;

    function setUp() public {
        // Deploy and initialize mock access control
        accessControl = new MockAccessControl();

        // Setup mock assets
        mockTokens = new MockERC20[](3);
        mockVaults = new MockERC4626[](3);
        assets = new address[](3);

        // Create mock tokens with different decimals
        mockTokens[0] = new MockERC20("Mock Token 1", "MT1", 18);
        mockTokens[1] = new MockERC20("Mock Token 2", "MT2", 6);
        mockTokens[2] = new MockERC20("Mock Token 3", "MT3", 8);

        // Create mock vaults with different interest rates
        for (uint256 i = 0; i < 3; i++) {
            assets[i] = address(mockTokens[i]);
            mockVaults[i] = new MockERC4626(
                assets[i],
                0.1e18, // 10% interest rate
                string(abi.encodePacked("Mock Vault ", vm.toString(i))),
                string(abi.encodePacked("MV", vm.toString(i)))
            );
        }

        // Deploy and initialize vault
        vault = new TestVault();
        vault.initialize(
            "Test Vault",
            "TV",
            address(accessControl),
            MOCK_FEE_AUCTION,
            address(3), // Mock oracle
            assets,
            address(4) // Mock insurance fund
        );

        // Create and target handler
        uint256[] memory maxReserves = new uint256[](3);
        maxReserves[0] = 1000e18;
        maxReserves[1] = 1000e6;
        maxReserves[2] = 1000e8;
        handler = new TestVaultHandler(vault, assets, maxReserves, mockVaults);
        targetContract(address(handler));

        // Label contracts for better traces
        vm.label(address(vault), "VAULT");
        vm.label(address(handler), "HANDLER");
        vm.label(address(accessControl), "ACCESS_CONTROL");
    }

    /// @dev Test that current reserve never exceeds max reserve
    function invariant_reserveLimits() public view {
        for (uint256 i = 0; i < assets.length; i++) {
            address asset = assets[i];
            uint256 currentReserve = vault.reserve(asset);
            uint256 maxReserve = handler.maxReserves(asset);
            assertLe(currentReserve, maxReserve, "Current reserve must not exceed max reserve");
        }
    }

    /// @dev Test that total invested + reserve equals total assets
    function invariant_totalAssetsBalance() public view {
        for (uint256 i = 0; i < assets.length; i++) {
            address asset = assets[i];
            uint256 invested = handler.getInvestedAmount(asset);
            uint256 currentReserve = vault.reserve(asset);
            uint256 totalAssets = handler.getTotalAssets(asset);

            assertEq(invested + currentReserve, totalAssets, "Invested + reserve must equal total assets");
        }
    }

    /// @dev Test that interest calculations are accurate
    function invariant_interestAccuracy() public view {
        for (uint256 i = 0; i < assets.length; i++) {
            address asset = assets[i];
            uint256 actualInterest = vault.claimableInterest(asset);
            uint256 expectedInterest = mockVaults[i].__estimateMockErc4626Yield();

            // Allow for small rounding error (1 wei)
            assertApproxEqAbs(actualInterest, expectedInterest, 1, "Interest calculation should be accurate");
        }
    }

    /// @dev Test that divesting is always possible up to invested amount
    function invariant_divestingPossible() public view {
        for (uint256 i = 0; i < assets.length; i++) {
            address asset = assets[i];
            uint256 invested = handler.getInvestedAmount(asset);
            uint256 maxDivestable = handler.getMaxDivestableAmount(asset);

            assertLe(maxDivestable, invested, "Cannot divest more than invested");
            if (invested > 0) {
                assertTrue(maxDivestable > 0, "Should be able to divest when invested");
            }
        }
    }
}

/**
 * @notice Handler contract for testing Vault invariants
 */
contract TestVaultHandler is StdUtils, RandomAssetUtils {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    TestVault public vault;
    mapping(address => MockERC4626) public vaults;

    // Ghost variables for tracking state
    mapping(address => uint256) public maxReserves;
    mapping(address => uint256) public totalInvested;
    mapping(address => uint256) public lastInterestUpdate;
    mapping(address => uint256) public accumulatedInterest;

    constructor(
        TestVault _vault,
        address[] memory _assets,
        uint256[] memory _max_reserves,
        MockERC4626[] memory _vaults
    ) RandomAssetUtils(_assets) {
        vault = _vault;

        // Initialize vaults and max reserves
        address[] memory assets = allAssets();
        for (uint256 i = 0; i < assets.length; i++) {
            address asset = assets[i];
            vaults[asset] = _vaults[i];
            maxReserves[asset] = _max_reserves[i];

            // Setup initial state
            vault.setFractionalReserveVault(asset, address(_vaults[i]));
            vault.setReserve(asset, _max_reserves[i]);
        }
    }

    function depositMockToken(uint256 assetSeed, uint256 amount) external {
        amount = bound(amount, 0, 1e50);
        address asset = randomAsset(assetSeed);

        MockERC20(asset).mint(address(this), amount);
        IERC20(asset).transfer(address(vault), amount);
    }

    function withdrawMockToken(uint256 assetSeed, uint256 amount) external {
        address asset = randomAsset(assetSeed);
        uint256 balance = MockERC20(asset).balanceOf(address(this));
        amount = bound(amount, 0, balance);
        vm.prank(address(vault));
        IERC20(asset).transfer(address(this), amount);
    }

    function invest(uint256 assetSeed) external {
        address asset = randomAsset(assetSeed);
        uint256 available = IERC20(asset).balanceOf(address(vault));
        if (available == 0) return;

        vault.investAll(asset);

        // Update ghost variables
        totalInvested[asset] += available;
        lastInterestUpdate[asset] = block.timestamp;
    }

    function divest(uint256 assetSeed) external {
        address asset = randomAsset(assetSeed);
        uint256 invested = getInvestedAmount(asset);
        if (invested == 0) return;

        vault.divestAll(asset);

        // Update ghost variables
        totalInvested[asset] -= invested;
        lastInterestUpdate[asset] = block.timestamp;
    }

    function investAll(uint256 assetSeed) external {
        address asset = randomAsset(assetSeed);
        vault.investAll(asset);

        // Update ghost variables
        uint256 newInvested = IERC20(asset).balanceOf(address(vaults[asset]));
        totalInvested[asset] = newInvested;
        lastInterestUpdate[asset] = block.timestamp;
    }

    function divestAll(uint256 assetSeed) external {
        address asset = randomAsset(assetSeed);
        vault.divestAll(asset);

        // Update ghost variables
        totalInvested[asset] = 0;
    }

    function realizeInterest(uint256 assetSeed) external {
        address asset = randomAsset(assetSeed);
        uint256 interest = vault.claimableInterest(asset);
        vault.realizeInterest(asset);

        // Update ghost variables
        accumulatedInterest[asset] += interest;
        lastInterestUpdate[asset] = block.timestamp;
    }

    function setReserve(uint256 assetSeed, uint256 amount) external {
        address asset = randomAsset(assetSeed);
        amount = bound(amount, 0, maxReserves[asset]);

        vault.setReserve(asset, amount);

        // Update ghost variables
        maxReserves[asset] = amount;
    }

    // View functions for invariant testing
    function getInvestedAmount(address asset) public view returns (uint256) {
        return IERC20(asset).balanceOf(address(vaults[asset]));
    }

    function getTotalAssets(address asset) public view returns (uint256) {
        return getInvestedAmount(asset) + vault.reserve(asset);
    }

    function getMaxDivestableAmount(address asset) public view returns (uint256) {
        uint256 invested = getInvestedAmount(asset);
        if (invested == 0) return 0;

        uint256 currentReserve = vault.reserve(asset);
        uint256 maxReserve = maxReserves[asset];

        if (currentReserve >= maxReserve) {
            return invested;
        }

        uint256 neededReserve = maxReserve - currentReserve;
        return invested > neededReserve ? invested - neededReserve : 0;
    }
}
