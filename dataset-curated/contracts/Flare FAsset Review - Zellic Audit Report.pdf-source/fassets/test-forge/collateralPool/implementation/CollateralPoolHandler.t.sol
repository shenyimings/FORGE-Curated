// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "forge-std/Test.sol";
import {CollateralPool} from "../../../contracts/collateralPool/implementation/CollateralPool.sol";
import {ICollateralPoolToken} from "../../../contracts/userInterfaces/ICollateralPoolToken.sol";
import {FAsset} from "../../../contracts/fassetToken/implementation/FAsset.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {SafePct} from "../../../contracts/utils/library/SafePct.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract CollateralPoolHandler is Test {
    using SafeCast for uint256;
    using SafePct for uint256;

    CollateralPool private collateralPool;
    FAsset private fAsset;
    address private assetManager;
    ICollateralPoolToken private token;

    address[] private accounts;

    uint256 public mul;
    uint256 public div;

    constructor(
        CollateralPool _collateralPool,
        FAsset _fAsset
    ) {
        collateralPool = _collateralPool;
        fAsset = _fAsset;
        assetManager = address(fAsset.assetManager());
        token = collateralPool.poolToken();
        // create 10 accounts
        for (uint256 i = 0; i < 10; i++) {
            address account = makeAddr(string(abi.encodePacked("account", i)));
            accounts.push(account);
            vm.deal(account, 100 * 1e9 ether); // fund accounts
        }
        mul = 1;
        div = 10;
    }

    function enter(uint128 _amount, uint8 _accIndex) public {
        uint256 totalPoolTokens = token.totalSupply();
        uint256 totalCollateral = collateralPool.totalCollateral();
        uint256 lowerBound = 1 ether;
        uint256 upperBound = 1 ether * 1e5;
        if (totalPoolTokens == 0) {
            uint256 totalFAssetFees = collateralPool.totalFAssetFees();
            uint256 totalFAssetsFeesWorth = totalFAssetFees.mulDiv(mul, div);
            lowerBound = Math.max(1 ether, Math.max(totalFAssetsFeesWorth, totalCollateral));
            upperBound = lowerBound > upperBound ? lowerBound * 2 : upperBound;
        }
        _amount = bound(_amount, lowerBound, upperBound).toUint128();

        if (totalCollateral != 0 && totalPoolTokens != 0) {
            lowerBound = totalCollateral / totalPoolTokens * 2;
            if (_amount < lowerBound) {
                _amount = lowerBound.toUint128();
            }
        }

        _accIndex = bound(_accIndex, 0, accounts.length - 1).toUint8();
        address account = accounts[_accIndex % accounts.length];
        vm.prank(account);
        collateralPool.enter{value: _amount}();

        // for each account except the one that entered, exit
        for (uint256 i = 0; i < accounts.length; i++) {
            if (i != _accIndex) {
                account = accounts[_accIndex];
                uint256 balance = token.balanceOf(account);
                if (balance == 0) return;
                if (totalPoolTokens > 1 ether) {
                    vm.prank(account);
                    uint256 maxExitAmount = totalPoolTokens - 1 ether;
                    uint256 tokenShare = Math.min(maxExitAmount / 2, balance/2);
                    collateralPool.exit(tokenShare);
                }
            }
        }
    }

    function exit(uint128 _tokenShare, uint8 _accIndex) public {
        _accIndex = bound(_accIndex, 0, accounts.length - 1).toUint8();
        address account = accounts[_accIndex];
        uint256 balance = token.balanceOf(account);
        // tokeShare must be between 1 and balance
        if (balance == 0) return;
        _tokenShare = bound(_tokenShare, 1, balance).toUint128();
        vm.prank(account);
        collateralPool.exit(_tokenShare);
    }

    function selfCloseExit(uint128 _tokenShare, uint8 _accIndex, bool _redeemToCollateral) public {
        _accIndex = bound(_accIndex, 0, accounts.length - 1).toUint8();
        address account = accounts[_accIndex];
        uint256 balance = token.balanceOf(account);
        // tokeShare must be between 1 and balance
        if (balance == 0) return;
        _tokenShare = bound(_tokenShare, 1, balance).toUint128();
        vm.prank(account);
        collateralPool.selfCloseExit(
            _tokenShare,
            _redeemToCollateral,
            "underlyingAddress",
            payable(makeAddr("executor"))
        );
    }

    function withdrawFees(
        uint128 _amountWithdraw,
        uint8 _accIndex,
        uint128 _amountMint,
        uint16 _feePercentageBIPS,
        uint128 _amountEnter
    ) public {
        _amountMint = bound(_amountMint, 1 ether, 1 ether * 1e3).toUint128();
        _feePercentageBIPS = bound(_feePercentageBIPS, 1, 6000).toUint16();
        fAssetFeeDeposited(
            _amountMint,
            _accIndex,
            _feePercentageBIPS,
            _accIndex,
            _amountEnter
        );

        fAssetFeeDeposited(
            _amountMint / 2,
            _accIndex,
            _feePercentageBIPS / 2,
            _accIndex,
            _amountEnter / 2
        );
        _accIndex = bound(_accIndex, 0, accounts.length - 1).toUint8();
        address account = accounts[_accIndex];
        uint256 fAssetFeesOf = collateralPool.fAssetFeesOf(account);
        if (fAssetFeesOf == 0) return;
        _amountWithdraw = bound(_amountWithdraw, 1, fAssetFeesOf).toUint128();
        vm.prank(account);
        collateralPool.withdrawFees(_amountWithdraw);
    }

    function mint(uint128 _amount, uint8 _accIndex) public {
        _amount = bound(_amount, 1 ether, 1 ether * 1e2).toUint128();
        _accIndex = bound(_accIndex, 0, accounts.length - 1).toUint8();
        address account = accounts[_accIndex];
        vm.prank(assetManager);
        fAsset.mint(account, _amount);
    }

    function depositNat(uint128 _amount) public {
        _amount = bound(_amount, 1 ether, 1 ether * 1e5).toUint128();
        vm.deal(assetManager, _amount); // fund asset manager
        vm.prank(assetManager);
        collateralPool.depositNat{value: _amount}();
    }

    function payout(
        address _recipient,
        uint128 _amountWei,
        uint128 _agentResponsibilityWei
    ) public {
        // Avoid sending payout to the pool itself
        if (_recipient == address(collateralPool)) {
            _recipient = makeAddr("recipient");
        }
        uint256 totalCollateral = collateralPool.totalCollateral();
        // payout amount can't exceed total collateral
        if (totalCollateral == 0) return;
        _amountWei = bound(_amountWei, 1, totalCollateral).toUint128();
        _agentResponsibilityWei = bound(_agentResponsibilityWei, 0,  _amountWei).toUint128();
        vm.prank(assetManager);
        collateralPool.payout(_recipient, _amountWei, _agentResponsibilityWei);
    }

    function fAssetFeeDeposited(
        uint128 _amountMint,
        uint8 _accIndex,
        uint16 _feePercentageBIPS,
        uint8 _accIndexEnter,
        uint128 _amountEnter
    ) public {
        _amountEnter = bound(_amountEnter, 1 ether, 1 ether * 4).toUint128();
        enter(_amountEnter, _accIndexEnter); // without entering first sum(_fAssetFeesOf(account)) == 0
        _amountMint = bound(_amountMint, 1 ether, 1 ether * 1e2).toUint128();
        _accIndex = bound(_accIndex, 0, accounts.length - 1).toUint8();
        _feePercentageBIPS = bound(_feePercentageBIPS, 1, 2000).toUint16();
        address _account = accounts[_accIndex];
        uint256 fee = (_amountMint * _feePercentageBIPS) / 10000;
        vm.startPrank(assetManager);
        fAsset.mint(_account, _amountMint);
        fAsset.mint(address(collateralPool), fee);
        collateralPool.fAssetFeeDeposited(fee);
        vm.stopPrank();
    }

    function getAccounts() external view returns (address[] memory) {
        return accounts;
    }
}
