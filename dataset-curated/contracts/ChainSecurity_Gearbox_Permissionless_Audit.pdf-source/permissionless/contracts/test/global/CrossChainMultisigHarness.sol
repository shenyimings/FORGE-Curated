// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {CrossChainMultisig} from "../../global/CrossChainMultisig.sol";
import {CrossChainCall} from "../../interfaces/ICrossChainMultisig.sol";

contract CrossChainMultisigHarness is CrossChainMultisig {
    constructor(address[] memory initialSigners, uint8 _confirmationThreshold, address _owner)
        CrossChainMultisig(initialSigners, _confirmationThreshold, _owner)
    {}

    // Expose internal functions for testing
    function exposed_addSigner(address newSigner) external {
        _addSigner(newSigner);
    }

    function exposed_setConfirmationThreshold(uint8 newConfirmationThreshold) external {
        _setConfirmationThreshold(newConfirmationThreshold);
    }

    function exposed_verifyProposal(CrossChainCall[] memory calls, bytes32 prevHash) external view {
        _verifyProposal(calls, prevHash);
    }

    function exposed_verifySignatures(bytes[] memory signatures, bytes32 structHash) external view returns (uint256) {
        return _verifySignatures(signatures, structHash);
    }

    function exposed_executeProposal(CrossChainCall[] memory calls, bytes32 proposalHash) external {
        _executeProposal(calls, proposalHash);
    }

    // Add setter for lastProposalHash
    function setLastProposalHash(bytes32 newHash) external {
        lastProposalHash = newHash;
    }
}
