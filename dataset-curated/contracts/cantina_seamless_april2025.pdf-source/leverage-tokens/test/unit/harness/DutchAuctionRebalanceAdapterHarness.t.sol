// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

import {DutchAuctionRebalanceAdapter} from "src/rebalance/DutchAuctionRebalanceAdapter.sol";
import {ILeverageToken} from "src/interfaces/ILeverageToken.sol";
import {LeverageTokenState} from "src/types/DataTypes.sol";
import {ILeverageManager} from "src/interfaces/ILeverageManager.sol";
import {IDutchAuctionRebalanceAdapter} from "src/interfaces/IDutchAuctionRebalanceAdapter.sol";
import {ICollateralRatiosRebalanceAdapter} from "src/interfaces/ICollateralRatiosRebalanceAdapter.sol";
import {IRebalanceAdapter} from "src/interfaces/IRebalanceAdapter.sol";

/// @notice Wrapper contract that exposes internal functions of DutchAuctionRebalanceAdapter for testing
contract DutchAuctionRebalanceAdapterHarness is DutchAuctionRebalanceAdapter {
    bool public isEligible;
    bool public isValidState;
    uint256 public targetCollateralRatio;
    ILeverageManager public leverageManager;

    function initialize(uint256 _auctionDuration, uint256 _initialPriceMultiplier, uint256 _minPriceMultiplier)
        external
        initializer
    {
        __DutchAuctionRebalanceAdapter_init(_auctionDuration, _initialPriceMultiplier, _minPriceMultiplier);
    }

    function exposed_getDutchAuctionRebalanceAdapterStorageSlot() external pure returns (bytes32 slot) {
        DutchAuctionRebalanceAdapterStorage storage $ = _getDutchAuctionRebalanceAdapterStorage();

        assembly {
            slot := $.slot
        }
    }

    function exposed_executeRebalanceUp(uint256 collateralAmount, uint256 debtAmount) external {
        _executeRebalanceUp(collateralAmount, debtAmount);
    }

    function exposed_executeRebalanceDown(uint256 collateralAmount, uint256 debtAmount) external {
        _executeRebalanceDown(collateralAmount, debtAmount);
    }

    function exposed_setAuctionDuration(uint256 newDuration) external {
        _getDutchAuctionRebalanceAdapterStorage().auctionDuration = newDuration;
    }

    function exposed_setInitialPriceMultiplier(uint256 newMultiplier) external {
        _getDutchAuctionRebalanceAdapterStorage().initialPriceMultiplier = newMultiplier;
    }

    function exposed_setMinPriceMultiplier(uint256 newMultiplier) external {
        _getDutchAuctionRebalanceAdapterStorage().minPriceMultiplier = newMultiplier;
    }

    function exposed_setLeverageToken(ILeverageToken _leverageToken) external {
        _setLeverageToken(_leverageToken);
    }

    function isEligibleForRebalance(ILeverageToken token, LeverageTokenState memory state, address caller)
        public
        view
        override
        returns (bool)
    {
        if (!isEligible) {
            return false;
        }

        return super.isEligibleForRebalance(token, state, caller);
    }

    function isStateAfterRebalanceValid(ILeverageToken, LeverageTokenState memory)
        public
        view
        override
        returns (bool)
    {
        return isValidState;
    }

    function getLeverageManager() public view override returns (ILeverageManager) {
        return leverageManager;
    }

    function getLeverageTokenTargetCollateralRatio() public view override returns (uint256) {
        return targetCollateralRatio;
    }

    function mock_isStateAfterRebalanceValid(bool _isValidState) external {
        isValidState = _isValidState;
    }

    function mock_isEligible(bool _isEligible) external {
        isEligible = _isEligible;
    }

    function mock_setLeverageManager(ILeverageManager _leverageManager) external {
        leverageManager = _leverageManager;
    }

    function mock_setTargetCollateralRatio(uint256 _targetCollateralRatio) external {
        targetCollateralRatio = _targetCollateralRatio;
    }
}
