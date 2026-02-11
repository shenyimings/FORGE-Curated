// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC20, IERC20, IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IBoldToken} from "../external/IBoldToken.sol";

contract MockStabilityPool {
    bool doRevert;
    string revertMsg = "oops";
    uint256 compoundedBoldGain;
    uint256 pendingBoldGain;
    uint256 collGain;
    uint256 stashedCollAmount;
    uint256 transferCollateralAmount;
    address bold;
    address coll;

    function setRevert(bool _doRevert) external {
        doRevert = _doRevert;
    }

    function setCompoundedBoldDeposit(uint256 _compoundedBoldGain) external {
        compoundedBoldGain = _compoundedBoldGain;
    }

    function setBold(address _bold) external {
        bold = _bold;
    }

    function setColl(address _coll) external {
        coll = _coll;
    }

    function provideToSP(uint256 _amount, bool) external {
        require(!doRevert, "MockSP: call failed");
        compoundedBoldGain += _amount;
        IBoldToken(bold).sendToPool(msg.sender, address(this), _amount);
    }

    function withdrawFromSP(uint256 _amount, bool doClaim) external {
        require(!doRevert, "MockSP: call failed");

        if (_amount == compoundedBoldGain) {
            _amount = compoundedBoldGain;
            compoundedBoldGain = 0;
        }

        if (doClaim) {
            _amount += pendingBoldGain;
            pendingBoldGain = 0;
            collGain = 0;
            stashedCollAmount = 0;
        }

        IERC20(bold).transfer(msg.sender, _amount);
        IERC20(coll).transfer(msg.sender, transferCollateralAmount);
    }

    function setDepositorCollGain(uint256 _collGain) external {
        collGain = _collGain;
    }

    function setDepositorYieldGainWithPending(uint256 _pendingBoldGain) external returns (uint256) {
        pendingBoldGain = _pendingBoldGain;
    }

    function getDepositorYieldGainWithPending(address) external view returns (uint256) {
        return pendingBoldGain;
    }

    function setStashedColl(uint256 _stashedColl) external {
        stashedCollAmount = _stashedColl;
    }

    function stashedColl(address) external view returns (uint256) {
        return stashedCollAmount;
    }

    function getCompoundedBoldDeposit(address) external view returns (uint256) {
        return compoundedBoldGain;
    }

    function setTransferCollAmount(uint256 _transferCollateralAmount) external {
        transferCollateralAmount = _transferCollateralAmount;
    }

    function getDepositorCollGain(address) external view returns (uint256) {
        return collGain;
    }

    function collToken() external view returns (address) {
        return coll;
    }
}
