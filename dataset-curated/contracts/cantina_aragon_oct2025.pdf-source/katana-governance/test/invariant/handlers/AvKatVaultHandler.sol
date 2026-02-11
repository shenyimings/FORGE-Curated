pragma solidity ^0.8.17;

import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import { MockERC20 } from "@mocks/MockERC20.sol";
import { AvKATVault } from "src/AvKATVault.sol";

import { BaseHandler } from "./BaseHandler.sol";
import { deployAutoCompoundStrategy } from "src/utils/Deployers.sol";
import { Swapper } from "src/Swapper.sol";

contract AvKatVaultHandler is BaseHandler {
    using EnumerableSet for EnumerableSet.AddressSet;

    // This is not public in vault, so hardcode it.
    uint256 public constant VIRTUAL_DECIMAL_OFFSET = 0;

    address public token; // token of escrow.
    AvKATVault internal vault;
    Swapper internal swapper;

    MockERC20 internal assetToken;

    // Ghost variables
    EnumerableSet.AddressSet internal actorsWithDepositedAssets;
    uint256 public totalDeposited;
    uint256 public totalWithdrawn;
    uint256 public totalDonated;

    constructor(AvKATVault _vault, Swapper _swapper) {
        vault = _vault;
        swapper = _swapper;

        assetToken = MockERC20(address(vault.asset()));

        totalDeposited = vault.totalAssets();
    }

    function deposit(uint256 _seed, uint256 _amount) public {
        address actor = useSender(_seed);

        // Ensure that user gets at least 1 share
        // to avoid 100% donations through `deposit`.
        uint256 atLeast = _minAssetsForNonZeroShares();
        _amount = _bound(_amount, atLeast, type(uint128).max);

        deal(address(assetToken), actor, _amount);

        vm.startPrank(actor);
        assetToken.approve(address(vault), _amount);
        vault.deposit(_amount, actor);
        vm.stopPrank();

        // Ghost state.
        actorsWithDepositedAssets.add(actor);
        totalDeposited += _amount;
    }

    function depositToken(uint256 _seed, uint256 _amount) public {
        address actor = useSender(_seed);

        // Ensure that user gets at least 1 share
        // to avoid 100% donations through `deposit`.
        uint256 atLeast = _minAssetsForNonZeroShares();
        _amount = _bound(_amount, atLeast, type(uint128).max);

        deal(address(assetToken), actor, _amount);

        // Create a lock on escrow first
        vm.startPrank(actor);
        assetToken.approve(address(vault.escrow()), _amount);
        uint256 tokenId = vault.escrow().createLock(_amount);

        // Deposit the token into vault
        vault.lockNft().approve(address(vault), tokenId);
        vault.depositTokenId(tokenId, actor);
        vm.stopPrank();

        // Ghost state.
        actorsWithDepositedAssets.add(actor);
        totalDeposited += _amount;
    }

    function withdraw(uint256 _seed, uint256 _amount) public {
        uint256 len = actorsWithDepositedAssets.length();
        if (len == 0) return;

        address actor = actorsWithDepositedAssets.at(_bound(_seed, 0, len - 1));
        _amount = _bound(_amount, 1, vault.convertToAssets(vault.balanceOf(actor)));

        vm.prank(actor);
        vault.withdraw(_amount, actor, actor);

        // Ghost state
        uint256 balance = vault.balanceOf(actor);
        if (balance == 0 || vault.convertToAssets(balance) == 0) {
            actorsWithDepositedAssets.remove(actor);
        }

        totalWithdrawn += _amount;
    }

    function redeem(uint256 _seed, uint256 _sharesPct) public {
        uint256 len = actorsWithDepositedAssets.length();
        if (len == 0) return;

        address actor = actorsWithDepositedAssets.at(_bound(_seed, 0, len - 1));
        uint256 actorShares = vault.balanceOf(actor);

        // Redeem a percentage of actor's shares (1-100%)
        uint256 sharesToRedeem = (_bound(_sharesPct, 1, 100) * actorShares) / 100;
        if (sharesToRedeem == 0) sharesToRedeem = 1;

        vm.prank(actor);
        uint256 assets = vault.redeem(sharesToRedeem, actor, actor);

        // Ghost state
        uint256 balance = vault.balanceOf(actor);
        if (balance == 0 || vault.convertToAssets(balance) == 0) {
            actorsWithDepositedAssets.remove(actor);
        }

        totalWithdrawn += assets;
    }

    function donate(uint256 _seed, uint256 _amount) public {
        address actor = useSender(_seed);
        _amount = _bound(_amount, 1, type(uint128).max);

        deal(address(assetToken), actor, _amount);

        vm.startPrank(actor);
        assetToken.approve(address(vault), _amount);
        vault.donate(_amount);
        vm.stopPrank();

        // Donation increases totalAssets but does NOT mint shares
        // This increases share value for all existing holders
        totalDonated += _amount;
    }

    function setStrategy(bool _deployNewStrategy) public {
        address strategy = address(0);

        if (_deployNewStrategy) {
            (, strategy) = deployAutoCompoundStrategy(
                address(vault.dao()),
                address(vault.escrow()),
                address(swapper),
                address(vault),
                address(swapper.rewardDistributor())
            );
        }

        vm.startPrank(address(vault.dao()));
        vault.setStrategy(strategy);
        vault.lockNft().setWhitelisted(address(strategy), true);
        vault.escrow().setEnableSplit(address(strategy), true);
        vm.stopPrank();
    }

    // ======== Helper Functions =========

    function _minAssetsForNonZeroShares() private view returns (uint256) {
        uint256 numerator = vault.totalAssets() + 1;
        uint256 denominator = vault.totalSupply() + 10 ** VIRTUAL_DECIMAL_OFFSET;

        // ceil(numerator / denominator)
        return (numerator + denominator - 1) / denominator;
    }

    function sumOfActorShares() public view returns (uint256 total) {
        for (uint256 i = 0; i < actorsWithDepositedAssets.length(); i++) {
            address actor = actorsWithDepositedAssets.at(i);
            total += vault.balanceOf(actor);
        }
    }
}
