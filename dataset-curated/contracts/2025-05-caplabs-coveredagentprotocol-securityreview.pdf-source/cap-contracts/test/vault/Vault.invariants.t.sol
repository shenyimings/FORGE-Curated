// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { AccessControl } from "../../contracts/access/AccessControl.sol";

import { ProxyUtils } from "../../contracts/deploy/utils/ProxyUtils.sol";
import { FeeAuction } from "../../contracts/feeAuction/FeeAuction.sol";

import { IMinter } from "../../contracts/interfaces/IMinter.sol";
import { Vault } from "../../contracts/vault/Vault.sol";
import { MockAccessControl } from "../mocks/MockAccessControl.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";

import { MockERC4626 } from "../mocks/MockERC4626.sol";
import { MockOracle } from "../mocks/MockOracle.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { StdCheats } from "forge-std/StdCheats.sol";
import { StdUtils } from "forge-std/StdUtils.sol";
import { Test } from "forge-std/Test.sol";

import { Vm } from "forge-std/Vm.sol";
import { console } from "forge-std/console.sol";

import { RandomActorUtils } from "../deploy/utils/RandomActorUtils.sol";
import { RandomAssetUtils } from "../deploy/utils/RandomAssetUtils.sol";

contract VaultInvariantsTest is Test, ProxyUtils {
    TestVaultHandler public handler;
    TestVault public vault;
    FeeAuction public feeAuction;
    address[] public assets;
    address public insuranceFund;

    MockOracle public mockOracle;
    MockAccessControl public accessControl;

    address[] public fractionalReserveVaults;

    // Track token holders for testing
    address[] private tokenHolders;
    mapping(address => bool) private isHolder;

    // Mock tokens
    MockERC20[] private mockTokens;

    function setUp() public {
        // Setup mock assets
        mockTokens = new MockERC20[](3);
        assets = new address[](3);

        // Create mock tokens with different decimals
        mockTokens[0] = new MockERC20("Mock Token 1", "MT1", 18);
        mockTokens[1] = new MockERC20("Mock Token 2", "MT2", 6);
        mockTokens[2] = new MockERC20("Mock Token 3", "MT3", 8);

        for (uint256 i = 0; i < 3; i++) {
            assets[i] = address(mockTokens[i]);
        }

        // Deploy and setup mock oracle
        mockOracle = new MockOracle();
        for (uint256 i = 0; i < assets.length; i++) {
            // Set initial price of 1:1 for each asset
            mockOracle.setPrice(assets[i], 10 ** IERC20Metadata(assets[i]).decimals());
        }

        // Deploy and initialize mock access control
        accessControl = new MockAccessControl();

        // Deploy and initialize fee auction with proxy
        FeeAuction feeAuctionImpl = new FeeAuction();
        address proxy = _proxy(address(feeAuctionImpl));
        feeAuction = FeeAuction(proxy);
        feeAuction.initialize(address(accessControl), address(mockTokens[0]), address(this), 1 days, 1e18);

        // Deploy insurance fund
        insuranceFund = makeAddr("insurance_fund");

        // Deploy and initialize vault
        vault = new TestVault();
        vault.initialize(
            "Test Vault",
            "tVAULT",
            address(accessControl),
            address(feeAuction),
            address(mockOracle),
            assets,
            address(insuranceFund)
        );
        mockOracle.setPrice(address(vault), 1e18);

        // Setup initial test accounts
        for (uint256 i = 0; i < 5; i++) {
            address user = makeAddr(string(abi.encodePacked("User", vm.toString(i))));
            tokenHolders.push(user);
            isHolder[user] = true;
        }

        // Create fractional reserve vaults, one for each asset
        fractionalReserveVaults = new address[](3);
        for (uint256 i = 0; i < 3; i++) {
            address asset = assets[i];
            address frVault = address(new MockERC4626(asset, 1e18, "Fractional Reserve Vault", "FRV"));
            MockERC4626(frVault).setInterestRate(uint256(0.1e18));

            fractionalReserveVaults[i] = frVault;
            vault.setFractionalReserveVault(asset, frVault);

            MockERC4626(frVault).__mockYield();
        }

        // Create and target handler
        handler = new TestVaultHandler(vault, mockOracle, assets, tokenHolders, fractionalReserveVaults);
        targetContract(address(handler));

        // we need to set an appropriate block.number and block.timestamp for the tests
        // otherwise they will default to 0 and the tests will fail trying to subtract staleness from 0
        vm.roll(block.number + 1_000_000);
        vm.warp(block.timestamp + 1_000_000);
    }

    function test_fuzzing_non_regression_loss_from_fractional_reserve_1() public {
        //[FAIL: custom error 0x95969727: 0000000000000000000000002e234dae75c793f67a35089c9d99245e1c58470b000000000000000000000000d6bbde9174b1cdaa358d2cf4d57d1a9f7178fbff0000000000000000000000000000000000000000000000000000000000000001]
        //[Sequence]
        //        sender=0x8d8C714C6790785D0cD4C75935622498F1A76184 addr=[test/vault/Vault.invariants.t.sol:TestVaultHandler]0x212224D2F2d262cd093eE13240ca4873fcCBbA3C calldata=pause(uint256) args=[7675797 [7.675e6]]
        //        sender=0x00000000000000000000000000000000dcD713EE addr=[test/vault/Vault.invariants.t.sol:TestVaultHandler]0x212224D2F2d262cd093eE13240ca4873fcCBbA3C calldata=removeAsset(uint256) args=[14837635802857839438797466 [1.483e25]]
        //        sender=0x00000000000000000000000000000000F6A916fd addr=[test/vault/Vault.invariants.t.sol:TestVaultHandler]0x212224D2F2d262cd093eE13240ca4873fcCBbA3C calldata=donateAsset(uint256,uint256) args=[9745, 3022]
        //        sender=0x0000000000000000000000000000000000001C71 addr=[test/vault/Vault.invariants.t.sol:TestVaultHandler]0x212224D2F2d262cd093eE13240ca4873fcCBbA3C calldata=pause(uint256) args=[9929]
        //        sender=0x0000000000000000000000000000000000000EA1 addr=[test/vault/Vault.invariants.t.sol:TestVaultHandler]0x212224D2F2d262cd093eE13240ca4873fcCBbA3C calldata=addAsset(uint256) args=[76715587 [7.671e7]]
        //        sender=0x3C9425bc7770077e68f6a1477D31a938683C316C addr=[test/vault/Vault.invariants.t.sol:TestVaultHandler]0x212224D2F2d262cd093eE13240ca4873fcCBbA3C calldata=investAll(uint256) args=[15078001 [1.507e7]]
        //        sender=0x000000000000000000000000000000000000249E addr=[test/vault/Vault.invariants.t.sol:TestVaultHandler]0x212224D2F2d262cd093eE13240ca4873fcCBbA3C calldata=setVaultReserve(uint256,uint256) args=[115792089237316195423570985008687907853269984665640564039457584007913129639934 [1.157e77], 11]
        //        sender=0x0000000000000000000000000000000352e302E2 addr=[test/vault/Vault.invariants.t.sol:TestVaultHandler]0x212224D2F2d262cd093eE13240ca4873fcCBbA3C calldata=divestAll(uint256) args=[725553526815472735717947576826637183330969562685975748313 [7.255e56]]
        //        sender=0x0000000000000000000000000000000000000435 addr=[test/vault/Vault.invariants.t.sol:TestVaultHandler]0x212224D2F2d262cd093eE13240ca4873fcCBbA3C calldata=investAll(uint256) args=[13690861936455249355276266665598585 [1.369e34]]
        //        sender=0x00000000000000000000000000000000000005d9 addr=[test/vault/Vault.invariants.t.sol:TestVaultHandler]0x212224D2F2d262cd093eE13240ca4873fcCBbA3C calldata=setFractionalReserveVault(uint256) args=[44123055 [4.412e7]]
        // invariant_mintingIncreaseBalance() (runs: 749, calls: 149800, reverts: 1)

        handler.pause(7675797);
        handler.removeAsset(14837635802857839438797466);
        handler.donateAsset(9745, 3022);
        handler.pause(9929);
        handler.addAsset(76715587);
        handler.investAll(15078001);
        handler.setVaultReserve(115792089237316195423570985008687907853269984665640564039457584007913129639934, 11);
        handler.divestAll(725553526815472735717947576826637183330969562685975748313);
        handler.investAll(13690861936455249355276266665598585);
        handler.setFractionalReserveVault(44123055);
    }

    function test_fuzzing_non_regression_loss_from_fractional_reserve_2() public {
        //[FAIL: custom error 0x95969727: 0000000000000000000000002e234dae75c793f67a35089c9d99245e1c58470b00000000000000000000000082dce515b19ca6c2b03060d7da1a9670fc6ee0740000000000000000000000000000000000000000000000000000000000000001]
        //[Sequence]
        //        sender=0xc7CdCe7CC669d77218fC42e5CC422ea19412eA2D addr=[test/vault/Vault.invariants.t.sol:TestVaultHandler]0x212224D2F2d262cd093eE13240ca4873fcCBbA3C calldata=donateAsset(uint256,uint256) args=[3157, 2799]
        //        sender=0x000000000000000000000000000000000000137B addr=[test/vault/Vault.invariants.t.sol:TestVaultHandler]0x212224D2F2d262cd093eE13240ca4873fcCBbA3C calldata=pause(uint256) args=[3]
        //        sender=0x0000000000000000000000000000000000000763 addr=[test/vault/Vault.invariants.t.sol:TestVaultHandler]0x212224D2F2d262cd093eE13240ca4873fcCBbA3C calldata=investAll(uint256) args=[4154]
        //        sender=0x0000000000000000000000000000000000000FbB addr=[test/vault/Vault.invariants.t.sol:TestVaultHandler]0x212224D2F2d262cd093eE13240ca4873fcCBbA3C calldata=pause(uint256) args=[197286539840145 [1.972e14]]
        //        sender=0x000000000000000000000000000000000000045A addr=[test/vault/Vault.invariants.t.sol:TestVaultHandler]0x212224D2F2d262cd093eE13240ca4873fcCBbA3C calldata=divestAll(uint256) args=[210304242682445377544489621833662242505594976 [2.103e44]]
        //        sender=0x000000000000000000000000000000000000059a addr=[test/vault/Vault.invariants.t.sol:TestVaultHandler]0x212224D2F2d262cd093eE13240ca4873fcCBbA3C calldata=investAll(uint256) args=[30284156 [3.028e7]]
        //        sender=0x0000000000000000000000000000000000000C79 addr=[test/vault/Vault.invariants.t.sol:TestVaultHandler]0x212224D2F2d262cd093eE13240ca4873fcCBbA3C calldata=setFractionalReserveVault(uint256) args=[124512733235148509670984850249661524172173354937 [1.245e47]]
        // invariant_totalAssetsExceedBorrowed() (runs: 1180, calls: 236000, reverts: 1)

        handler.donateAsset(3157, 2799);
        handler.pause(3);
        handler.investAll(4154);
        handler.pause(197286539840145);
        handler.divestAll(210304242682445377544489621833662242505594976);
        handler.investAll(30284156);
        handler.setFractionalReserveVault(124512733235148509670984850249661524172173354937);
    }

    /// @dev Test that total assets >= total borrowed
    function invariant_totalAssetsExceedBorrowed() public view {
        for (uint256 i = 0; i < assets.length; i++) {
            address asset = assets[i];
            uint256 totalAssets = vault.totalSupplies(asset);
            uint256 totalBorrowed = vault.totalBorrows(asset);
            assertGe(totalAssets, totalBorrowed, "Total assets must exceed borrowed");
        }
    }

    /// @dev Test that minting increases asset balance correctly
    function invariant_mintingIncreaseBalance() public {
        address[] memory unpausedAssets = handler.getVaultUnpausedAssets();

        for (uint256 i = 0; i < unpausedAssets.length; i++) {
            address asset = unpausedAssets[i];

            uint256 amount = 1000 * (10 ** IERC20Metadata(asset).decimals());
            if (amount == 0) continue;

            uint256 balanceBefore = IERC20(asset).balanceOf(address(vault));
            uint256 supplyBefore = vault.totalSupplies(asset);

            address minter = makeAddr("Minter");
            MockERC20(asset).mint(minter, amount);

            vm.startPrank(minter);
            IERC20(asset).approve(address(vault), amount);
            vault.mint(asset, amount, 0, minter, block.timestamp);
            vm.stopPrank();

            uint256 balanceAfter = IERC20(asset).balanceOf(address(vault));
            uint256 supplyAfter = vault.totalSupplies(asset);

            assertEq(balanceAfter - balanceBefore, amount, "Asset balance should increase by exact amount");
            assertTrue(supplyAfter > supplyBefore, "Total supply should increase");
        }
    }
}

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
/**
 * @notice This is a helper contract to test the vault invariants in a meaningful way
 */

contract TestVaultHandler is StdUtils, RandomActorUtils, RandomAssetUtils {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    Vault public vault;
    MockOracle public mockOracle;

    address[] public assets;
    address[] public actors;
    address[] public fractionalReserveVaults;
    uint256 private constant MAX_ASSETS = 10;

    constructor(
        Vault _vault,
        MockOracle _mockOracle,
        address[] memory _assets,
        address[] memory _actors,
        address[] memory _fractionalReserveVaults
    ) RandomActorUtils(_actors) RandomAssetUtils(_assets) {
        vault = _vault;
        mockOracle = _mockOracle;
        assets = _assets;
        actors = _actors;
        fractionalReserveVaults = _fractionalReserveVaults;

        for (uint256 i = 0; i < _fractionalReserveVaults.length; i++) {
            MockERC4626(_fractionalReserveVaults[i]).setInterestRate(uint256(0.1e18));
            MockERC4626(_fractionalReserveVaults[i]).__mockYield();
        }
    }

    function getVaultUnpausedAssets() public view returns (address[] memory) {
        address[] memory vaultAssets = vault.assets();
        address[] memory tmp = new address[](vaultAssets.length);
        uint256 tmpIndex = 0;
        for (uint256 i = 0; i < vaultAssets.length; i++) {
            address asset = vaultAssets[i];
            if (!vault.paused(asset)) {
                tmp[tmpIndex++] = asset;
            }
        }

        address[] memory result = new address[](tmpIndex);
        for (uint256 i = 0; i < tmpIndex; i++) {
            result[i] = tmp[i];
        }
        return result;
    }

    function _isAssetInVault(address asset) internal view returns (bool) {
        address[] memory vaultAssets = vault.assets();
        for (uint256 i = 0; i < vaultAssets.length; i++) {
            if (vaultAssets[i] == asset) {
                return true;
            }
        }
        return false;
    }

    function wrapTime(uint256 timeSeed, uint256 blockNumberSeed) external returns (uint256) {
        uint256 timestamp = bound(timeSeed, block.timestamp, block.timestamp + 100 days);
        vm.warp(timestamp);

        uint256 blockNumber = bound(blockNumberSeed, block.number, block.number + 1000000);
        vm.roll(blockNumber);

        return timestamp;
    }

    function addAsset(uint256 assetSeed) external {
        address currentAsset = randomAsset(assets, assetSeed);
        if (currentAsset == address(0)) return;
        if (_isAssetInVault(currentAsset)) return;

        address[] memory unpausedAssets = getVaultUnpausedAssets();
        if (unpausedAssets.length >= MAX_ASSETS) return;

        vault.addAsset(currentAsset);
    }

    function approve(uint256 actorSeed, uint256 spenderSeed, uint256 amount) external {
        address currentSpender = randomActor(spenderSeed);
        if (currentSpender == address(0)) return;
        address currentActor = randomActor(actorSeed);
        if (currentActor == address(0)) return;
        amount = bound(amount, 0, type(uint96).max); // Reasonable bound for approval
        if (amount == 0) return;

        vm.startPrank(currentActor);
        vault.approve(currentSpender, amount);
        vm.stopPrank();
    }

    function borrow(uint256 actorSeed, uint256 assetSeed, uint256 amount) external {
        address currentAsset = randomAsset(getVaultUnpausedAssets(), assetSeed);
        if (currentAsset == address(0)) return;

        address currentActor = randomActor(actorSeed);
        if (currentActor == address(0)) return;

        uint256 maxBorrow = vault.availableBalance(currentAsset);
        amount = bound(amount, 0, Math.min(maxBorrow, type(uint96).max)); // Reasonable bound for borrow

        vm.startPrank(currentActor);
        vault.borrow(currentAsset, amount, currentActor);
        vm.stopPrank();
    }

    function burn(uint256 actorSeed, uint256 assetSeed, uint256 amount) external {
        address currentAsset = randomAsset(getVaultUnpausedAssets(), assetSeed);
        if (currentAsset == address(0)) return;

        address currentActor = randomActor(actorSeed);
        if (currentActor == address(0)) return;

        uint256 maxBurn = vault.balanceOf(currentActor);
        if (maxBurn == 0) return;

        amount = bound(amount, 1, Math.min(maxBurn, type(uint96).max)); // Reasonable bound for burn

        vm.startPrank(currentActor);
        vault.burn(currentAsset, amount, 0, currentActor, block.timestamp);
        vm.stopPrank();
    }

    function divestAll(uint256 assetSeed) external {
        address currentAsset = randomAsset(getVaultUnpausedAssets(), assetSeed);
        if (currentAsset == address(0)) return;

        uint256 loaned = vault.loaned(currentAsset);
        if (loaned < 1e6) return;

        vm.warp(block.timestamp + 1 days);

        vault.divestAll(currentAsset);
    }

    function investAll(uint256 assetSeed) external {
        address currentAsset = randomAsset(getVaultUnpausedAssets(), assetSeed);
        if (currentAsset == address(0)) return;
        vault.investAll(currentAsset);
    }

    function mint(uint256 actorSeed, uint256 assetSeed, uint256 amountSeed) external {
        address currentAsset = randomAsset(getVaultUnpausedAssets(), assetSeed);
        if (currentAsset == address(0)) return;

        address currentActor = randomActor(actorSeed);
        if (currentActor == address(0)) return;

        uint256 maxMint = vault.availableBalance(currentAsset);
        if (maxMint == 0) return;
        uint256 amount = bound(amountSeed, 1, Math.min(maxMint, type(uint96).max)); // Reasonable bound for mint

        vm.startPrank(currentActor);
        // Mint tokens to the actor first
        MockERC20(currentAsset).mint(currentActor, amount);

        IERC20(currentAsset).approve(address(vault), amount);
        vault.mint(currentAsset, amount, 0, currentActor, block.timestamp);
        vm.stopPrank();
    }

    function redeem(uint256 actorSeed, uint256 amount) external {
        address currentActor = randomActor(actorSeed);
        if (currentActor == address(0)) return;

        uint256 maxRedeem = vault.balanceOf(currentActor);
        if (maxRedeem == 0) return;

        amount = bound(amount, 1, Math.min(maxRedeem, type(uint96).max)); // Reasonable bound for redeem

        uint256[] memory amountsOut = new uint256[](1);
        amountsOut[0] = 0;

        vm.startPrank(currentActor);
        vault.redeem(amount, amountsOut, currentActor, block.timestamp);
        vm.stopPrank();
    }

    function removeAsset(uint256 assetSeed) external {
        address currentAsset = randomAsset(getVaultUnpausedAssets(), assetSeed);
        if (currentAsset == address(0)) return;

        vault.removeAsset(currentAsset);
    }

    function repay(uint256 actorSeed, uint256 assetSeed, uint256 amount) external {
        address currentAsset = randomAsset(getVaultUnpausedAssets(), assetSeed);
        if (currentAsset == address(0)) return;

        address currentActor = randomActor(actorSeed);
        if (currentActor == address(0)) return;

        uint256 maxRepay = vault.availableBalance(currentAsset);
        amount = bound(amount, 0, Math.min(maxRepay, type(uint96).max)); // Reasonable bound for repay

        vm.startPrank(currentActor);
        // Mint tokens to the actor first
        MockERC20(currentAsset).mint(currentActor, amount);

        IERC20(currentAsset).approve(address(vault), amount);
        vault.repay(currentAsset, amount);
    }

    function rescueERC20(IERC20 asset, uint256 receiverSeed) external {
        address currentActor = randomActor(receiverSeed);
        if (currentActor == address(0)) return;
        if (address(asset).code.length == 0) {
            return;
        }
        if (_isAssetInVault(address(asset))) return;

        try IERC20(asset).balanceOf(address(vault)) returns (uint256 amount) {
            if (amount > 0) {
                vault.rescueERC20(address(asset), currentActor);
            }
        } catch {
            // Do nothing if the asset is not in the vault
        }
    }

    function pause(uint256 assetSeed) external {
        address currentAsset = randomAsset(getVaultUnpausedAssets(), assetSeed);
        if (currentAsset == address(0)) return;

        vault.pause(currentAsset);
    }

    function unpause(uint256 assetSeed) external {
        address currentAsset = randomAsset(getVaultUnpausedAssets(), assetSeed);
        if (currentAsset == address(0)) return;

        vault.unpause(currentAsset);
    }

    function setAssetOraclePrice(uint256 assetSeed, uint256 price) external {
        address currentAsset = randomAsset(getVaultUnpausedAssets(), assetSeed);
        if (currentAsset == address(0)) return;

        uint256 decimals = IERC20Metadata(currentAsset).decimals();
        uint256 boundPrice = bound(price, 10 ** (decimals - 1), 10 ** decimals);
        mockOracle.setPrice(currentAsset, boundPrice);
    }

    // TODO: make it external again after fixing the tests
    function ______________________setVaultFeeData(
        uint256 assetSeed,
        uint256 slope0Seed,
        uint256 slope1Seed,
        uint256 mintKinkRatioSeed,
        uint256 burnKinkRatioSeed,
        uint256 optimalRatioSeed
    ) internal {
        address currentAsset = randomAsset(getVaultUnpausedAssets(), assetSeed);
        if (currentAsset == address(0)) return;

        uint256 slope0 = bound(slope0Seed, 0.0000000000001e27, 100000001e27);
        uint256 slope1 = bound(slope1Seed, slope0, 100000001e27);
        uint256 mintKinkRatio = bound(mintKinkRatioSeed, 0.0000000000001e27, 100000001e27);
        uint256 burnKinkRatio = bound(burnKinkRatioSeed, 0.0000000000001e27, 100000001e27);
        uint256 optimalRatio = bound(optimalRatioSeed, 0.0000000000001e27, 100000001e27);

        vault.setFeeData(
            currentAsset,
            IMinter.FeeData({
                minMintFee: 0.005e27,
                slope0: slope0,
                slope1: slope1,
                mintKinkRatio: mintKinkRatio,
                burnKinkRatio: burnKinkRatio,
                optimalRatio: optimalRatio
            })
        );
    }

    function setVaultRedeemFee(uint256 redeemFeeSeed) external {
        uint256 redeemFee = bound(redeemFeeSeed, 0, type(uint256).max);
        vault.setRedeemFee(redeemFee);
    }

    function setVaultReserve(uint256 assetSeed, uint256 reserve) external {
        address currentAsset = randomAsset(getVaultUnpausedAssets(), assetSeed);
        if (currentAsset == address(0)) return;
        vault.setReserve(currentAsset, reserve);
    }

    function realizeInterest(uint256 assetSeed) external {
        address currentAsset = randomAsset(getVaultUnpausedAssets(), assetSeed);
        if (currentAsset == address(0)) return;
        vault.realizeInterest(currentAsset);
    }

    function setFractionalReserveVault(uint256 assetSeed) external {
        address currentAsset = randomAsset(getVaultUnpausedAssets(), assetSeed);
        if (currentAsset == address(0)) return;

        uint256 loaned = vault.loaned(currentAsset);
        if (loaned < 1e6) return;

        address newFractionalReserveVault =
            address(new MockERC4626(currentAsset, 1e18, "Fractional Reserve Vault", "FRV"));

        vm.warp(block.timestamp + 1 days);

        vault.setFractionalReserveVault(currentAsset, newFractionalReserveVault);
    }

    // @dev Donate tokens to the lender's vault
    function donateAsset(uint256 assetSeed, uint256 amountSeed) external {
        address currentAsset = randomAsset(assetSeed);
        if (currentAsset == address(0)) return;

        uint256 amount = bound(amountSeed, 1, 1e50);
        MockERC20(currentAsset).mint(address(vault), amount);
    }

    function donateGasToken(uint256 amountSeed) external {
        uint256 amount = bound(amountSeed, 1, 1e50);
        vm.deal(address(vault), amount /* we need gas to send gas */ );
    }
}
