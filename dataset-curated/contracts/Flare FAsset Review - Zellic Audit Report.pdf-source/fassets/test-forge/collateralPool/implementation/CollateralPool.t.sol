// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "forge-std/Test.sol";
import {CollateralPool} from "../../../contracts/collateralPool/implementation/CollateralPool.sol";
import {FAsset} from "../../../contracts/fassetToken/implementation/FAsset.sol";
import {FAssetProxy} from "../../../contracts/fassetToken/implementation/FAssetProxy.sol";
import {CollateralPoolToken} from "../../../contracts/collateralPool/implementation/CollateralPoolToken.sol";
import {CollateralPoolHandler} from "./CollateralPoolHandler.t.sol";
import {AssetManagerMock} from "../../../contracts/assetManager/mock/AssetManagerMock.sol";
import {WNatMock} from "../../../contracts/flareSmartContracts/mock/WNatMock.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {SafePct} from "../../../contracts/utils/library/SafePct.sol";
import {MathUtils} from "../../../contracts/utils/library/MathUtils.sol";

// solhint-disable func-name-mixedcase
contract CollateralPoolTest is Test {
    using SafeCast for uint256;
    using SafeCast for int256;
    using SafePct for uint256;

    CollateralPool private collateralPool;
    FAsset private fAsset;
    FAssetProxy private fAssetProxy;
    FAsset private fAssetImpl;
    CollateralPoolToken private collateralPoolToken;
    CollateralPoolHandler private handler;

    address private governance;
    address private agentVault;
    AssetManagerMock private assetManagerMock;
    WNatMock private wNat;

    uint32 private exitCR = 12000;
    address[] private accounts;

    bytes4[] private selectors;

    function setUp() public {
        governance = makeAddr("governance");
        wNat = new WNatMock(makeAddr("governance"), "wNative", "wNat");
        assetManagerMock = new AssetManagerMock(wNat);
        agentVault = makeAddr("agentVault");

        fAssetImpl = new FAsset();
        fAssetProxy = new FAssetProxy(
            address(fAssetImpl),
            "fBitcoin",
            "fBTC",
            "Bitcoin",
            "BTC",
            18
        );
        fAsset = FAsset(address(fAssetProxy));
        fAsset.setAssetManager(address(assetManagerMock));

        collateralPool = new CollateralPool(
            agentVault,
            address(assetManagerMock),
            address(fAsset),
            exitCR
        );

        collateralPoolToken = new CollateralPoolToken(
            address(collateralPool),
            "FAsset Collateral Pool Token BTC-AG1",
            "FCPT-BTC-AG1"
        );

        vm.prank(address(assetManagerMock));
        collateralPool.setPoolToken(address(collateralPoolToken));

        handler = new CollateralPoolHandler(
            collateralPool,
            fAsset
        );
        accounts = handler.getAccounts();

        assetManagerMock.setCheckForValidAgentVaultAddress(false);
        assetManagerMock.registerFAssetForCollateralPool(fAsset);
        assetManagerMock.setAssetPriceNatWei(handler.mul(), handler.div());

        targetContract(address(handler));
        selectors.push(handler.enter.selector);
        selectors.push(handler.exit.selector);
        selectors.push(handler.selfCloseExit.selector);
        selectors.push(handler.withdrawFees.selector);
        selectors.push(handler.mint.selector);
        selectors.push(handler.depositNat.selector);
        selectors.push(handler.payout.selector);
        selectors.push(handler.fAssetFeeDeposited.selector);
        targetSelector(
            FuzzSelector({
                addr: address(handler),
                selectors: selectors
            })
        );
    }

    function invariant_1() public view {
        // sum(_fAssetFeeDebtOf[account]) = totalFAssetFeeDebt
        int256 totalFAssetFeeDebt = collateralPool.totalFAssetFeeDebt();
        int256 sumFAssetFeeDebt = 0;
        for (uint256 i = 0; i < accounts.length; i++) {
            address account = accounts[i];
            sumFAssetFeeDebt += collateralPool.fAssetFeeDebtOf(account);
        }
        assertEq(totalFAssetFeeDebt, sumFAssetFeeDebt,
            "Invariant 1 failed: totalFAssetFeeDebt does not match sum of fAssetFeeDebtOf"
        );
    }

    function invariant_2() public view {
        // totalFAssetFees + totalFAssetFeeDebt >= 0
        uint256 totalFAssetFees = collateralPool.totalFAssetFees();
        int256 totalFAssetFeeDebt = collateralPool.totalFAssetFeeDebt();
        require(totalFAssetFees <= uint256(type(int256).max), "totalFAssetFees too large");
        assertGe(int256(totalFAssetFees) + totalFAssetFeeDebt, 0,
            "Invariant 2 failed: totalFAssetFees + totalFAssetFeeDebt is negative"
        );
    }

    function invariant_3() public view {
        // 0 <= _fAssetFeesOf(account) <= totalFAssetFees
        uint256 totalFAssetFees = collateralPool.totalFAssetFees();
        for (uint256 i = 0; i < accounts.length; i++) {
            address account = accounts[i];
            uint256 fAssetFeesOf = collateralPool.fAssetFeesOf(account);
            assertGe(fAssetFeesOf, 0, "fAssetFeesOf should be non-negative");
            assertLe(fAssetFeesOf, totalFAssetFees, "fAssetFeesOf should not exceed totalFAssetFees");
        }
    }

    function invariant_3_1() public view {
        // 0 <= _fAssetFeesOf(account)
        // using non-restricted version of _fAssetFeesOf
        // invariant won't hold, error accumulates
        for (uint256 i = 0; i < accounts.length; i++) {
            address account = accounts[i];
            int256 fAssetFeesOf = _fAssetFeesOf(account);
            assertGe(fAssetFeesOf, -30, "_fAssetFeesOf should be greater than or equal to -30");
        }
    }

    function invariant_3_2() public view {
        // _fAssetFeesOf(account) <= totalFAssetFees
        // using non-restricted version of _fAssetFeesOf
        // invariant won't hold, error accumulates
        uint256 totalFAssetFees = collateralPool.totalFAssetFees();
        for (uint256 i = 0; i < accounts.length; i++) {
            address account = accounts[i];
            int256 fAssetFeesOf = _fAssetFeesOf(account);
            assertLe(MathUtils.positivePart(fAssetFeesOf), totalFAssetFees + 100,
                "_fAssetFeesOf should not exceed totalFAssetFees");
        }
    }

    function invariant_4() public view {
        // sum(_fAssetFeesOf(account)) = totalFAssetFees
        uint256 totalFAssetFees = collateralPool.totalFAssetFees();
        uint256 sumFAssetFees = 0;
        for (uint256 i = 0; i < accounts.length; i++) {
            address account = accounts[i];
            sumFAssetFees += collateralPool.fAssetFeesOf(account);
        }
        uint256 absDiff = totalFAssetFees > sumFAssetFees ?
            totalFAssetFees - sumFAssetFees : sumFAssetFees - totalFAssetFees;
        assertLe(absDiff, 4 * accounts.length,
            "Invariant 4 failed: totalFAssetFees does not match sum of fAssetFeesOf"
        );
    }

    function invariant_4_1() public view {
        // sum(_fAssetFeesOf(account)) = totalFAssetFees
        // using non-restricted version of _fAssetFeesOf
        int256 totalFAssetFees = int256(collateralPool.totalFAssetFees());
        int256 sumFAssetFees = 0;
        for (uint256 i = 0; i < accounts.length; i++) {
            address account = accounts[i];
            sumFAssetFees += _fAssetFeesOf(account);
        }
        int256 absDiff = totalFAssetFees > sumFAssetFees ?
            totalFAssetFees - sumFAssetFees : sumFAssetFees - totalFAssetFees;
        assertLe(absDiff, int256(accounts.length),
            "Invariant 4 failed: totalFAssetFees does not match sum of _fAssetFeesOf"
        );
    }

    function invariant_5() public view {
        // 0 <= _debtFreeTokensOf(account) <= token.balanceOf(_account)
        for (uint256 i = 0; i < accounts.length; i++) {
            address account = accounts[i];
            uint256 debtFreeTokensOf = collateralPool.debtFreeTokensOf(account);
            uint256 balance = collateralPoolToken.balanceOf(account);
            assertGe(debtFreeTokensOf, 0, "debtFreeTokensOf should be non-negative");
            assertLe(debtFreeTokensOf, balance, "debtFreeTokensOf should not exceed balance");
        }
    }

    function invariant_5_1() public view {
        // _debtFreeTokensOf(account) <= token.balanceOf(_account)
        // using non-restricted version of _debtFreeTokensOf
        for (uint256 i = 0; i < accounts.length; i++) {
            address account = accounts[i];
            int256 debtFreeTokensOf = _debtFreeTokensOf(account);
            int256 balance = collateralPoolToken.balanceOf(account).toInt256();
            assertLe(debtFreeTokensOf, balance, "_debtFreeTokensOf should not exceed balance");
        }
    }

    function invariant_6() public view {
        // totalFAssetFees >= fasset.balanceOf(collateralPool)
        uint256 totalFAssetFees = collateralPool.totalFAssetFees();
        uint256 fAssetBalance = fAsset.balanceOf(address(collateralPool));
        assertGe(totalFAssetFees, fAssetBalance,
            "Invariant 6 failed: totalFAssetFees is less than fasset balance in collateralPool"
        );
    }

    function invariant_7() public view {
        // totalCollateral >= wNat.balanceOf(collateralPool)
        uint256 totalCollateral = collateralPool.totalCollateral();
        uint256 wNatBalance = wNat.balanceOf(address(collateralPool));
        assertGe(totalCollateral, wNatBalance,
            "Invariant 7 failed: totalCollateral is less than wNat balance of collateralPool"
        );
    }


    // ---- Helper functions ----
    function _fAssetFeesOf(address _account) internal view returns (int256) {
        int256 virtualFAssetFees = _virtualFAssetFeesOf(_account).toInt256();
        int256 accountFeeDebt = collateralPool.fAssetFeeDebtOf(_account);
        int256 userFees = virtualFAssetFees - accountFeeDebt;
        return userFees;
    }

    function _virtualFAssetFeesOf(
        address _account
    )
        internal view
        returns (uint256)
    {
        uint256 tokens = collateralPoolToken.balanceOf(_account);
        return _tokensToVirtualFeeShare(tokens);
    }

    function _tokensToVirtualFeeShare(
        uint256 _tokens
    )
        internal view
        returns (uint256)
    {
        if (_tokens == 0) return 0;
        uint256 totalPoolTokens = collateralPoolToken.totalSupply();
        assert(_tokens <= totalPoolTokens);
        return _totalVirtualFees().mulDiv(_tokens, totalPoolTokens);
    }

    function _totalVirtualFees()
        internal view
        returns (uint256)
    {
        int256 virtualFees = collateralPool.totalFAssetFees().toInt256() + collateralPool.totalFAssetFeeDebt();
        return virtualFees.toUint256();
    }

    function _debtFreeTokensOf(
        address _account
    )
        internal view
        returns (int256)
    {
        int256 accountFeeDebt = collateralPool.fAssetFeeDebtOf(_account);
        if (accountFeeDebt <= 0) {
            // with no debt, all tokens are free
            // this avoids the case where freeFassets == poolVirtualFAssetFees == 0
            return int256(collateralPoolToken.balanceOf(_account));
        }
        uint256 virtualFassets = collateralPool.virtualFAssetOf(_account);
        assert(virtualFassets <= _totalVirtualFees());
        int256 freeFassets = virtualFassets.toInt256() - accountFeeDebt;
        if (freeFassets == 0) return 0;
        // nonzero divisor: _totalVirtualFees() >= virtualFassets >= freeFassets > 0
        return _mulDivNeg(collateralPoolToken.totalSupply(), freeFassets, _totalVirtualFees());
    }

    function _mulDivNeg(uint256 x, int256 y, uint256 z) internal pure returns (int256) {
        require(z > 0, "Division by zero");
        if (y == 0 || x == 0) return 0;
        bool negative = y < 0;
        uint256 absY = uint256(y < 0 ? -y : y);
        uint256 result = x.mulDiv(absY, z); // use the uint256 version
        return negative ? -int256(result) : int256(result);
    }

}