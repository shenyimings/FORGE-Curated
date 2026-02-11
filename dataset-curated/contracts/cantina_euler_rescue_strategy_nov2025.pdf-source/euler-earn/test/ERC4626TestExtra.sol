// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.26;

import {IntegrationTest, CAP, IERC4626, MarketConfig} from "./helpers/IntegrationTest.sol";
import {IEVault} from "../lib/euler-vault-kit/src/EVault/IEVault.sol";
import {ErrorsLib} from "../src/libraries/ErrorsLib.sol";

import "forge-std/Test.sol";

abstract contract VaultsLittleHelper is IntegrationTest {
    function setUp() public virtual override {
        super.setUp();

        _setCap(allMarkets[0], CAP);
        _sortSupplyQueueIdleLast();
    }

    function _deposit(uint256 _assets, address _depositor) internal returns (uint256 shares) {
        return _makeDeposit(_assets, _depositor);
    }

    function _mint(uint256 _shares, address _depositor) internal returns (uint256 assets) {
        return _makeMint(_shares, _depositor);
    }

    function _redeem(uint256 _amount, address _depositor) internal returns (uint256 assets) {
        vm.prank(_depositor);
        return vault.redeem(_amount, _depositor, _depositor);
    }

    function _withdraw(uint256 _amount, address _depositor) internal returns (uint256 shares) {
        vm.prank(_depositor);
        return vault.withdraw(_amount, _depositor, _depositor);
    }

    function _makeDeposit(uint256 _assets, address _depositor) internal returns (uint256 shares) {
        vm.prank(_depositor);
        shares = vault.deposit(_assets, _depositor);
    }

    function _makeDeposit(uint256 _assets, address _depositor, bytes4 _error) internal returns (uint256 shares) {
        vm.prank(_depositor);
        vm.expectRevert(_error);
        shares = vault.deposit(_assets, _depositor);
    }

    function _makeMint(uint256 _shares, address _depositor) internal returns (uint256 assets) {
        vm.prank(_depositor);
        assets = vault.mint(_shares, _depositor);
    }
}

contract ERC4626TestExtra is VaultsLittleHelper {
    uint256 internal constant _REAL_ASSETS_LIMIT = type(uint112).max;
    uint256 internal constant _IDLE_CAP = type(uint112).max;

    address public immutable depositor;

    constructor() {
        depositor = makeAddr("Depositor");
    }

    function setUp() public override {
        super.setUp();
        vm.prank(depositor);
        loanToken.approve(address(vault), type(uint256).max);
        loanToken.setBalance(depositor, type(uint112).max);
    }

    function test_deposit_totalAssets() public {
        _deposit(123, depositor);

        assertEq(vault.totalAssets(), 123, "totalAssets match deposit");
    }

    function test_mint() public {
        uint256 shares = 1e18;

        uint256 previewMint = vault.previewMint(shares);

        _mint(shares, depositor);

        assertEq(vault.totalAssets(), previewMint, "previewMint should give us expected assets amount");
    }

    function test_maxDeposit1() public view {
        assertEq(vault.maxDeposit(address(1)), CAP + _IDLE_CAP, "ERC4626 expect to return summary CAP for all markets");
    }

    function test_maxDeposit_withDeposit() public {
        uint256 deposit = 123;

        _deposit(deposit, depositor);

        assertEq(
            vault.maxDeposit(depositor),
            CAP + _IDLE_CAP - deposit,
            "ERC4626 expect to return summary CAP for all markets - deposit"
        );
    }

    function test_maxDeposit_takesIntoAccountAccruedInterest_fuzz(
        uint112 _depositAmount,
        uint112 _aboveDeposit,
        uint8 _days
    ) public {
        vm.assume(_depositAmount > 1e18);
        vm.assume(_aboveDeposit > 1e18);
        vm.assume(_days > 1 && _days <= 10);

        _depositAmount = uint112(bound(_depositAmount, 1e18 + 1, _REAL_ASSETS_LIMIT - 1e18 - 1));
        _aboveDeposit = uint112(bound(_aboveDeposit, 1e18 + 1, _REAL_ASSETS_LIMIT - _depositAmount));

        address anyAddress = makeAddr("AnyAddress");
        uint256 cap = uint256(_depositAmount) + uint256(_aboveDeposit);

        // configuring supply queue and cap
        IERC4626[] memory supplyQueue = new IERC4626[](1);
        supplyQueue[0] = allMarkets[0];
        vm.prank(ALLOCATOR);
        vault.setSupplyQueue(supplyQueue);

        _setCap(allMarkets[0], cap);

        // depositing into the EVault
        _deposit(_depositAmount, depositor);

        // Validating the max deposit after deposit (no interest yet)
        uint256 maxDepositAfterDeposit = vault.maxDeposit(anyAddress);
        uint256 totalAssetsAfterDeposit = vault.totalAssets();

        assertEq(maxDepositAfterDeposit, cap - _depositAmount, "Invalid max deposit after deposit");

        // creating a debt to accrue interest
        collateralToken.setBalance(BORROWER, _depositAmount);

        // Borrow liquidity.
        vm.startPrank(BORROWER);
        collateralVault.deposit(_depositAmount, BORROWER);
        evc.enableController(BORROWER, address(allMarkets[0]));
        _toEVault(allMarkets[0]).borrow(_depositAmount / 2, BORROWER);

        // move time forward to accrue interest
        vm.warp(block.timestamp + _days * 1 days);

        // getting the max deposit after interest
        uint256 maxDepositWithInterest = vault.maxDeposit(anyAddress);
        uint256 totalAssetsAfterInterest = vault.totalAssets();

        uint256 accruedInterest = totalAssetsAfterInterest - totalAssetsAfterDeposit;

        assertNotEq(accruedInterest, 0, "Accrued interest should be greater than 0");

        assertEq(
            maxDepositWithInterest, // max deposit should subtract the accrued interest
            maxDepositAfterDeposit > accruedInterest ? maxDepositAfterDeposit - accruedInterest : 0,
            "Invalid max deposit after interest"
        );
    }

    function test_maxMint() public view {
        assertEq(vault.maxMint(address(1)), (CAP + _IDLE_CAP), "ERC4626 expect to return summary CAP for all markets");
    }

    function test_maxMint_withDeposit() public {
        uint256 deposit = 123;

        _deposit(deposit, depositor);

        assertEq(
            vault.maxMint(depositor),
            (CAP + _IDLE_CAP - deposit),
            "ERC4626 expect to return summary CAP for all markets - deposit"
        );
    }

    function test_maxRedeem_zero() public view {
        uint256 maxRedeem = vault.maxRedeem(depositor);
        assertEq(maxRedeem, 0, "nothing to redeem");
    }

    function test_maxRedeem_deposit_fuzz(uint112 _assets, uint16 _assets2) public {
        vm.assume(_assets > 0);
        vm.assume(_assets2 > 0);

        _deposit(_assets, depositor);

        loanToken.setBalance(address(1), _assets2);
        vm.prank(address(1));
        loanToken.approve(address(vault), _assets2);
        _deposit(_assets2, address(1)); // any

        uint256 maxRedeem = vault.maxRedeem(depositor);
        assertEq(maxRedeem, _assets, "max withdraw == _assets/shares if no interest");

        _assertDepositorCanNotRedeemMore(maxRedeem);
        _assertDepositorHasNothingToRedeem();
    }

    function test_maxRedeem_whenBorrow_1token_fuzz(uint112 _collateral, uint112 _toBorrow) public {
        vm.assume(_toBorrow <= uint256(_collateral) * 7 / 10);
        vm.assume(_toBorrow > 0);

        _reduceLiquidity(_collateral, _toBorrow);

        uint256 maxRedeem = vault.maxRedeem(depositor);
        assertLt(maxRedeem, vault.balanceOf(depositor), "with debt you can not withdraw all");

        _assertDepositorCanNotRedeemMore(maxRedeem);
    }

    function test_maxRedeem_whenInterest_fuzz(uint112 _collateral, uint112 _toBorrow) public {
        vm.assume(_toBorrow > 3);
        vm.assume(_toBorrow <= uint256(_collateral) * 7 / 10);
        vm.assume(_collateral < _REAL_ASSETS_LIMIT * 9 / 10);

        _reduceLiquidity(_collateral, _toBorrow);

        vm.warp(block.timestamp + 100 days);

        uint256 maxRedeem = vault.maxRedeem(depositor);
        assertLt(maxRedeem, vault.balanceOf(depositor), "with debt you can not withdraw all");

        _assertDepositorCanNotRedeemMore(maxRedeem, 3);
    }

    function test_maxWithdraw_zero() public view {
        uint256 maxWithdraw = vault.maxWithdraw(depositor);
        assertEq(maxWithdraw, 0, "nothing to withdraw");
    }

    function test_maxWithdraw_deposit_fuzz(uint112 _assets, uint16 _assets2) public {
        vm.assume(_assets > 0);
        vm.assume(_assets2 > 0);

        _deposit(_assets, depositor);

        loanToken.setBalance(address(1), _assets2);
        vm.prank(address(1));
        loanToken.approve(address(vault), _assets2);
        _deposit(_assets2, address(1)); // any

        uint256 maxWithdraw = vault.maxWithdraw(depositor);
        assertEq(maxWithdraw, _assets, "max withdraw == _assets if no interest");

        _assertDepositorCanNotWithdrawMore(maxWithdraw);
        _assertMaxWithdrawIsZeroAtTheEnd();
    }

    function test_maxWithdraw_notEnoughLiquidity_fuzz(uint112 _collateral, uint64 _percentToReduceLiquidity) public {
        vm.assume(_percentToReduceLiquidity <= 1e18);

        uint256 reduced = uint256(_collateral) * _percentToReduceLiquidity / 1e18;
        vm.assume(reduced > 0);
        vm.assume(reduced < _REAL_ASSETS_LIMIT * 7 / 10); // to preserve LTVs

        _reduceLiquidity(_collateral, reduced);

        uint256 maxWithdraw = vault.maxWithdraw(depositor);
        assertLt(maxWithdraw, _collateral, "with debt you can not withdraw all");

        _assertDepositorCanNotWithdrawMore(maxWithdraw, 1);
        _assertMaxWithdrawIsZeroAtTheEnd();
    }

    function test_maxWithdraw_whenInterest_fuzz(uint112 _collateral) public {
        vm.assume(_collateral > 0);

        loanToken.setBalance(depositor, _collateral);
        vm.prank(depositor);
        vault.deposit(_collateral, depositor);

        _createInterest();

        uint256 maxWithdraw = vault.maxWithdraw(depositor);
        assertGt(maxWithdraw, _collateral, "expect to earn because we have interest");

        _assertDepositorCanNotWithdrawMore(maxWithdraw, 1);
        _assertMaxWithdrawIsZeroAtTheEnd(1);
    }

    function test_previewDeposit_beforeInterest_fuzz(uint112 _assets) public {
        vm.assume(_assets > 0);

        uint256 previewShares = vault.previewDeposit(_assets);
        uint256 shares = _deposit(_assets, depositor);

        assertEq(previewShares, shares, "previewDeposit must return as close but NOT more");
        assertEq(previewShares, vault.convertToShares(_assets), "previewDeposit == convertToShares");
    }

    function test_previewDeposit_afterNoInterest_fuzz(uint112 _assets) public {
        vm.assume(_assets > 0);

        loanToken.setBalance(depositor, _assets);
        uint256 sharesBefore = _deposit(_assets, depositor);

        vm.warp(block.timestamp + 365 days);

        uint256 previewShares = vault.previewDeposit(_assets);
        loanToken.setBalance(depositor, _assets);
        uint256 gotShares = _deposit(_assets, depositor);

        assertEq(previewShares, gotShares, "previewDeposit must return as close but NOT more");
        assertEq(previewShares, sharesBefore, "without interest shares must be the same");
        assertEq(previewShares, vault.convertToShares(_assets), "previewDeposit == convertToShares");
    }

    function test_previewMint_beforeInterest_fuzz(uint256 _shares) public {
        vm.assume(_shares > 0);

        _assertPreviewMint(_shares);
    }

    function test_previewMint_afterNoInterest_fuzz(uint112 _depositAmount, uint112 _shares) public {
        vm.assume(_shares < _REAL_ASSETS_LIMIT / 3);

        _previewMint_afterNoInterest(_depositAmount, _shares);
        _assertPreviewMint(_shares);
    }

    function test_previewMint_withInterest_1token_fuzz(uint112 _shares) public {
        vm.assume(_shares > 1);

        _createInterest();

        _assertPreviewMint(_shares);
    }

    function test_previewMint_withInterest_2tokens_fuzz(uint112 _shares) public {
        vm.assume(_shares > 1);

        _createInterest();

        _assertPreviewMint(_shares);
    }

    function test_previewWithdraw_noInterestNoDebt_fuzz(uint112 _assetsOrShares, bool _partial) public {
        uint256 amountIn = _partial ? uint256(_assetsOrShares) * 37 / 100 : _assetsOrShares;
        vm.assume(amountIn > 1);

        _deposit(_assetsOrShares, depositor);

        amountIn -= 1;

        uint256 preview = _getPreview(amountIn);

        _assertEqPreviewAmountEqSharesWhenNoInterest(preview, amountIn);

        _assertPreviewWithdraw(preview, amountIn);
    }

    function test_previewWithdraw_debt_fuzz(uint112 _assetsOrShares, bool _interest, bool _partial) public {
        vm.assume(_assetsOrShares > 1); // can not create debt with 1 collateral

        uint112 amountToUse = _partial ? uint112(uint256(_assetsOrShares) * 37 / 100) : _assetsOrShares;

        if (_useRedeem()) {
            vm.assume(amountToUse < type(uint112).max);
        }

        vm.assume(amountToUse > 0);

        uint256 assets = _useRedeem() ? _assetsOrShares : _assetsOrShares;
        _deposit(assets, depositor);

        _createUnderlyingUsage();

        if (_interest) _applyInterest();

        uint256 preview = _getPreview(amountToUse);

        if (!_interest) {
            _assertEqPreviewAmountEqSharesWhenNoInterest(preview, amountToUse);
        }

        _assertPreviewWithdraw(preview, amountToUse);
    }

    function test_previewWithdraw_random_fuzz(uint64 _assetsOrShares, bool _interest) public {
        vm.assume(_assetsOrShares > 0);

        _deposit(_assetsOrShares, depositor);

        _createUnderlyingUsage();

        if (_interest) _applyInterest();

        uint256 preview = _getPreview(_assetsOrShares);

        if (!_interest) {
            _assertEqPreviewAmountEqSharesWhenNoInterest(preview, _assetsOrShares);
        }

        _assertPreviewWithdraw(preview, _assetsOrShares);
    }

    function test_previewWithdraw_min_fuzz(uint112 _assetsOrShares, bool _interest) public {
        vm.assume(_assetsOrShares > 0);

        uint256 assets = _useRedeem() ? _assetsOrShares : _assetsOrShares;
        _deposit(assets, depositor);

        _createUnderlyingUsage();

        if (_interest) _applyInterest();

        uint256 minInput = _useRedeem() ? vault.convertToShares(1) : vault.convertToAssets(vault.convertToShares(1) + 1);
        uint256 minPreview = _getPreview(minInput);

        if (!_interest) {
            _assertEqPreviewAmountEqSharesWhenNoInterest(minPreview, minInput);
        }

        _assertPreviewWithdraw(minPreview, minInput);
    }

    function test_previewWithdraw_max_fuzz(uint64 _assets, bool _interest) public {
        vm.assume(_assets > 0);

        _deposit(_assets, depositor);

        _createUnderlyingUsage();

        if (_interest) _applyInterest();

        uint256 maxInput = _useRedeem()
            // we can not use balance of share token, because we not sure about liquidity
            ? vault.maxRedeem(depositor)
            : vault.maxWithdraw(depositor);

        uint256 maxPreview = _getPreview(maxInput);

        if (!_interest) {
            _assertEqPreviewAmountEqSharesWhenNoInterest(maxPreview, maxInput);
        }

        _assertPreviewWithdraw(maxPreview, maxInput);
    }

    function _createUnderlyingUsage() internal {
        uint256 maxDeposit = _REAL_ASSETS_LIMIT - loanToken.balanceOf(address(vault));
        loanToken.setBalance(depositor, maxDeposit);
        vm.prank(depositor);
        vault.deposit(maxDeposit, depositor);

        collateralToken.setBalance(BORROWER, type(uint112).max);

        vm.startPrank(BORROWER);
        collateralVault.deposit(type(uint112).max, BORROWER);
        evc.enableController(BORROWER, address(allMarkets[0]));
        _toEVault(allMarkets[0]).borrow(type(uint64).max, BORROWER);
        vm.stopPrank();
    }

    function _applyInterest() internal {
        vm.warp(block.timestamp + 200 days);
    }

    function _assertPreviewWithdraw(uint256 _preview, uint256 _assetsOrShares) internal {
        vm.assume(_preview > 0);
        vm.prank(depositor);

        uint256 results = _useRedeem()
            ? vault.redeem(_assetsOrShares, depositor, depositor)
            : vault.withdraw(_assetsOrShares, depositor, depositor);

        assertGt(results, 0, "expect any withdraw amount > 0");

        if (_useRedeem()) assertEq(_preview, results, "preview should give us exact result, NOT more");
        else assertEq(_preview, results, "preview should give us exact result, NOT fewer");
    }

    function _getPreview(uint256 _amountToUse) internal view virtual returns (uint256 preview) {
        preview = _useRedeem() ? vault.previewRedeem(_amountToUse) : vault.previewWithdraw(_amountToUse);
    }

    function _useRedeem() internal pure virtual returns (bool) {
        return false;
    }

    function _assertEqPreviewAmountEqSharesWhenNoInterest(uint256 _preview, uint256 _amountIn) private pure {
        if (_useRedeem()) assertEq(_preview, _amountIn, "previewWithdraw == shares, when no interest");
        else assertEq(_preview, _amountIn, "previewWithdraw == assets, when no interest");
    }

    function _assertDepositorCanNotWithdrawMore(uint256 _maxWithdraw) internal {
        _assertDepositorCanNotWithdrawMore(_maxWithdraw, 1);
    }

    function _assertDepositorCanNotWithdrawMore(uint256 _maxWithdraw, uint256 _underestimate) internal {
        assertGt(_underestimate, 0, "_underestimate must be at least 1");

        emit log_named_uint("=== QA [_assertDepositorCanNotWithdrawMore] _maxWithdraw:", _maxWithdraw);
        emit log_named_uint("=== QA [_assertDepositorCanNotWithdrawMore] _underestimate:", _underestimate);

        if (_maxWithdraw > 0) {
            vm.prank(depositor);
            vault.withdraw(_maxWithdraw, depositor, depositor);
        }

        uint256 counterExample = _underestimate;
        emit log_named_uint("=========== [counterexample] testing counterexample for maxWithdraw with", counterExample);

        vm.prank(depositor);
        vm.expectRevert();
        vault.withdraw(counterExample, depositor, depositor);
    }

    function _assertMaxWithdrawIsZeroAtTheEnd() internal {
        _assertMaxWithdrawIsZeroAtTheEnd(0);
    }

    function _assertMaxWithdrawIsZeroAtTheEnd(uint256 _underestimate) internal {
        emit log_named_uint("================= _assertMaxWithdrawIsZeroAtTheEnd ================= +/-", _underestimate);

        uint256 maxWithdraw = vault.maxWithdraw(depositor);

        assertLe(
            maxWithdraw,
            _underestimate,
            string.concat("at this point max should return 0 +/-", string(abi.encodePacked(_underestimate)))
        );
    }

    function _createInterest() internal {
        uint256 maxDeposit = _REAL_ASSETS_LIMIT - loanToken.balanceOf(address(vault));
        loanToken.setBalance(depositor, maxDeposit);
        vm.prank(depositor);
        vault.deposit(maxDeposit, depositor);

        collateralToken.setBalance(BORROWER, type(uint112).max);

        vm.startPrank(BORROWER);
        collateralVault.deposit(type(uint112).max, BORROWER);
        evc.enableController(BORROWER, address(allMarkets[0]));
        _toEVault(allMarkets[0]).borrow(type(uint64).max, BORROWER);

        vm.warp(block.timestamp + 200 days);
        loanToken.approve(address(allMarkets[0]), type(uint256).max);
        _toEVault(allMarkets[0]).repay(_toEVault(allMarkets[0]).debtOf(BORROWER), BORROWER);
        vm.stopPrank();
    }

    function _assertDepositorHasNothingToRedeem() internal view {
        assertEq(vault.maxRedeem(depositor), 0, "expect maxRedeem to be 0");
        assertEq(vault.balanceOf(depositor), 0, "expect share balance to be 0");
    }

    function _assertDepositorCanNotRedeemMore(uint256 _maxRedeem) internal {
        _assertDepositorCanNotRedeemMore(_maxRedeem, 1);
    }

    function _assertDepositorCanNotRedeemMore(uint256 _maxRedeem, uint256 _underestimate) internal {
        emit log_named_uint("------- QA: _assertDepositorCanNotRedeemMore shares", _maxRedeem);

        assertGt(vault.convertToAssets(_underestimate), 0, "_underestimate must be at least 1 asset");

        if (_maxRedeem > 0) {
            vm.prank(depositor);
            vault.redeem(_maxRedeem, depositor, depositor);
        }

        uint256 counterExample = _underestimate;
        emit log_named_uint("=========== [counterexample] testing counterexample for maxRedeem with", counterExample);

        vm.prank(depositor);
        vm.expectRevert();
        vault.redeem(counterExample, depositor, depositor);
    }

    function _assertMaxRedeemIsZeroAtTheEnd() internal {
        _assertMaxRedeemIsZeroAtTheEnd(0);
    }

    function _assertMaxRedeemIsZeroAtTheEnd(uint256 _underestimate) internal {
        emit log_named_uint("================= _assertMaxRedeemIsZeroAtTheEnd ================= +/-", _underestimate);

        uint256 maxRedeem = vault.maxRedeem(depositor);

        assertLe(
            maxRedeem,
            _underestimate,
            string.concat("at this point max should return 0 +/-", string(abi.encodePacked(_underestimate)))
        );
    }

    function _reduceLiquidity(uint256 _depositAssets, uint256 _toBorrow) internal {
        loanToken.setBalance(depositor, _depositAssets);

        _deposit(_depositAssets, depositor);

        collateralToken.setBalance(BORROWER, type(uint112).max);

        vm.startPrank(BORROWER);
        collateralVault.deposit(type(uint112).max, BORROWER);
        evc.enableController(BORROWER, address(allMarkets[0]));
        _toEVault(allMarkets[0]).borrow(_toBorrow, BORROWER);

        vm.stopPrank();
    }

    function _previewMint_afterNoInterest(uint112 _depositAmount, uint112 _shares) internal {
        address any = makeAddr("any");
        vm.assume(_depositAmount > 0);
        vm.assume(_shares > 0);

        // deposit something
        loanToken.setBalance(any, _depositAmount);
        vm.prank(any);
        loanToken.approve(address(vault), type(uint256).max);
        _deposit(_depositAmount, any);

        vm.warp(block.timestamp + 365 days);

        _assertPreviewMint(_shares);
    }

    function _assertPreviewMint(uint256 _shares) internal {
        // we can get overflow on numbers closed to max
        vm.assume(_shares < type(uint112).max);

        uint256 previewMint = vault.previewMint(_shares);

        loanToken.setBalance(depositor, previewMint);
        vm.prank(depositor);
        uint256 depositedAssets = vault.mint(_shares, depositor);

        assertEq(previewMint, depositedAssets, "previewMint == depositedAssets, NOT fewer");

        uint256 convertToAssets = vault.convertToAssets(_shares);
        uint256 diff;

        if (previewMint > convertToAssets) {
            diff = previewMint - convertToAssets;
        } else {
            diff = convertToAssets - previewMint;
        }

        assertLe(diff, 2, "diff should be less or equal than 2");
    }
}
