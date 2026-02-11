// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

contract WalletUtils {
    function getWalletAddress() public view returns (address wallet) {
        wallet = tx.origin;
        if (wallet == address(0)) {
            wallet = msg.sender;
        }

        if (wallet == address(0)) {
            revert("Wallet address not set");
        }

        if (wallet == 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38) {
            revert(
                "Wallet address is set to the default foundry address. Plz provide --sender $(cast wallet address --account cap-dev)"
            );
        }
    }
}
