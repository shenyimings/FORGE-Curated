// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

interface ISignatureBasedPaymaster {
    event SignerChanged(address indexed oldSigner, address indexed newSigner);

    event NonceCanceled(address indexed sender, uint256 newNonce);

    event SenderApproved(address indexed sender, uint256 validUntil);

    event Withdrawn(address indexed token, uint256 amount);
}
