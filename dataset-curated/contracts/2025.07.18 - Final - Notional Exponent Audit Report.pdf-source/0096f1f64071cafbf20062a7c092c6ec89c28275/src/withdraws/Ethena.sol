// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

import "../interfaces/IEthena.sol";
import {ClonedCoolDownHolder} from "./ClonedCoolDownHolder.sol";
import {AbstractWithdrawRequestManager} from "./AbstractWithdrawRequestManager.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

contract EthenaCooldownHolder is ClonedCoolDownHolder {

    constructor(address _manager) ClonedCoolDownHolder(_manager) { }

    /// @notice There is no way to stop a cool down
    function _stopCooldown() internal pure override { revert(); }

    function _startCooldown(uint256 cooldownBalance) internal override {
        uint24 duration = sUSDe.cooldownDuration();
        if (duration == 0) {
            // If the cooldown duration is set to zero, can redeem immediately
            sUSDe.redeem(cooldownBalance, address(this), address(this));
        } else {
            // If we execute a second cooldown while one exists, the cooldown end
            // will be pushed further out. This holder should only ever have one
            // cooldown ever.
            require(sUSDe.cooldowns(address(this)).cooldownEnd == 0);
            sUSDe.cooldownShares(cooldownBalance);
        }
    }

    function _finalizeCooldown() internal override returns (uint256 tokensClaimed, bool finalized) {
        uint24 duration = sUSDe.cooldownDuration();
        IsUSDe.UserCooldown memory userCooldown = sUSDe.cooldowns(address(this));

        if (block.timestamp < userCooldown.cooldownEnd && 0 < duration) {
            // Cooldown has not completed, return a false for finalized
            return (0, false);
        }

        uint256 balanceBefore = USDe.balanceOf(address(this));
        // If a cooldown has been initiated, need to call unstake to complete it. If
        // duration was set to zero then the USDe will be on this contract already.
        if (0 < userCooldown.cooldownEnd) sUSDe.unstake(address(this));
        uint256 balanceAfter = USDe.balanceOf(address(this));

        // USDe is immutable. It cannot have a transfer tax and it is ERC20 compliant
        // so we do not need to use the additional protections here.
        tokensClaimed = balanceAfter - balanceBefore;
        USDe.transfer(manager, tokensClaimed);
        finalized = true;
    }
}

contract EthenaWithdrawRequestManager is AbstractWithdrawRequestManager {

    address public HOLDER_IMPLEMENTATION;

    constructor() AbstractWithdrawRequestManager(address(USDe), address(sUSDe), address(USDe)) { }

    function _initialize(bytes calldata /* data */) internal override {
        HOLDER_IMPLEMENTATION = address(new EthenaCooldownHolder(address(this)));
    }

    function _stakeTokens(
        uint256 usdeAmount,
        bytes memory /* stakeData */
    ) internal override {
        USDe.approve(address(sUSDe), usdeAmount);
        sUSDe.deposit(usdeAmount, address(this));
    }

    function _initiateWithdrawImpl(
        address /* account */,
        uint256 balanceToTransfer,
        bytes calldata /* data */
    ) internal override returns (uint256 requestId) {
        EthenaCooldownHolder holder = EthenaCooldownHolder(Clones.clone(HOLDER_IMPLEMENTATION));
        sUSDe.transfer(address(holder), balanceToTransfer);
        holder.startCooldown(balanceToTransfer);

        return uint256(uint160(address(holder)));
    }

    function _finalizeWithdrawImpl(
        address /* account */,
        uint256 requestId
    ) internal override returns (uint256 tokensClaimed, bool finalized) {
        EthenaCooldownHolder holder = EthenaCooldownHolder(address(uint160(requestId)));
        (tokensClaimed, finalized) = holder.finalizeCooldown();
    }

    function canFinalizeWithdrawRequest(uint256 requestId) public view override returns (bool) {
        uint24 duration = sUSDe.cooldownDuration();
        address holder = address(uint160(requestId));
        // This valuation is the amount of USDe the account will receive at cooldown, once
        // a cooldown is initiated the account is no longer receiving sUSDe yield. This balance
        // of USDe is transferred to a Silo contract and guaranteed to be available once the
        // cooldown has passed.
        IsUSDe.UserCooldown memory userCooldown = sUSDe.cooldowns(holder);
        return (userCooldown.cooldownEnd < block.timestamp || 0 == duration);
    }

}
