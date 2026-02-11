// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "../interfaces/queues/IEigenLayerWithdrawalQueue.sol";
import "../interfaces/vaults/IMultiVault.sol";

contract Claimer {
    function multiAcceptAndClaim(
        address multiVault,
        uint256[] calldata subvaultIndices,
        uint256[][] calldata indices,
        address recipient,
        uint256 maxAssets
    ) public returns (uint256 assets) {
        address sender = msg.sender;
        IMultiVaultStorage.Subvault memory subvault;
        for (uint256 i = 0; i < subvaultIndices.length; i++) {
            subvault = IMultiVault(multiVault).subvaultAt(subvaultIndices[i]);
            if (subvault.protocol == IMultiVaultStorage.Protocol.EIGEN_LAYER) {
                IEigenLayerWithdrawalQueue(subvault.withdrawalQueue).acceptPendingAssets(
                    sender, indices[i]
                );
            }
            if (subvault.withdrawalQueue != address(0) && assets < maxAssets) {
                assets += IWithdrawalQueue(subvault.withdrawalQueue).claim(
                    sender, recipient, maxAssets - assets
                );
            }
        }
    }
}
