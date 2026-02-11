// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { ITheoDepositVault } from './external/ITheoDepositVault.sol';
import { StdTally } from './StdTally.sol';

contract TheoTally is StdTally {
  ITheoDepositVault internal immutable _theo;

  constructor(ITheoDepositVault theo_) {
    _theo = theo_;
  }

  function _totalBalance(bytes memory) internal view override returns (uint256 totalBalance_) {
    uint256 decimals = _theo.decimals();
    (uint256 heldByAccount, uint256 heldByVault) = _theo.shareBalances(msg.sender);
    return _sharesToAsset(heldByAccount + heldByVault, _theo.pricePerShare(), decimals);
  }

  function _pendingWithdrawBalance(bytes memory) internal view override returns (uint256 pendingWithdrawBalance_) {
    uint256 decimals = _theo.decimals();
    ITheoDepositVault.Withdrawal memory withdrawal = _theo.withdrawals(msg.sender);

    uint256 currentRound = _theo.round();
    uint256 pricePerShare;
    if (currentRound == withdrawal.round) {
      pricePerShare = _theo.pricePerShare();
    } else {
      pricePerShare = _theo.roundPricePerShare(withdrawal.round);
    }
    return _sharesToAsset(withdrawal.shares, pricePerShare, decimals);
  }

  // ShareMath

  function _sharesToAsset(uint256 shares, uint256 assetPerShare, uint256 decimals) internal pure returns (uint256) {
    // If this throws, it means that vault's roundPricePerShare[currentRound] has not been set yet
    // which should never happen.
    // Has to be larger than 1 because `1` is used in `initRoundPricePerShares` to prevent cold writes.
    require(assetPerShare > 1, 'Invalid assetPerShare');

    return (shares * assetPerShare) / (10 ** decimals);
  }
}
