// SPDX-License-Identifier: GNU General Public License Version 3
// See license at: https://github.com/forta-network/forta-firewall-contracts/blob/master/LICENSE-GPLv3.md

pragma solidity ^0.8.25;

import {ERC2771Forwarder} from "@openzeppelin/contracts/metatx/ERC2771Forwarder.sol";

/**
 * @notice Helps with sponsoring SecurityValidator.storeAttestation() requests.
 */
contract AttestationForwarder is ERC2771Forwarder {
    constructor() ERC2771Forwarder("AttestationForwarder") {}

    /**
     * @inheritdoc ERC2771Forwarder
     * @notice Overridden to exclude nonce usage and gas checks. Nonce usage is not preferred due
     * to gas costs added to SecurityValidator.storeAttestation() transactions. Gas checks are
     * not necessary because this forwarder is only for sponsoring the whole storeAttestation()
     * transactions that arrive in any shape - which would otherwise be sent by the users as a
     * direct transaction to the security validator.
     */
    function _execute(ForwardRequestData calldata request, bool requireValidRequest)
        internal
        override
        returns (bool success)
    {
        (bool isTrustedForwarder, bool active, bool signerMatch, address signer) = _validate(request);

        // Need to explicitly specify if a revert is required since non-reverting is default for
        // batches and reversion is opt-in since it could be useful in some scenarios
        if (requireValidRequest) {
            if (!isTrustedForwarder) {
                revert ERC2771UntrustfulTarget(request.to, address(this));
            }

            if (!active) {
                revert ERC2771ForwarderExpiredRequest(request.deadline);
            }

            if (!signerMatch) {
                revert ERC2771ForwarderInvalidSigner(signer, request.from);
            }
        }

        if (isTrustedForwarder && signerMatch && active) {
            uint256 reqGas = request.gas;
            address to = request.to;
            uint256 value = request.value;
            bytes memory data = abi.encodePacked(request.data, request.from);
            assembly {
                success := call(reqGas, to, value, add(data, 0x20), mload(data), 0, 0)
            }
            emit ExecutedForwardRequest(signer, 0, success);
        }
    }
}
