// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import { ExecuteParam } from "../uln/dvn/DVN.sol";

contract DVNMock {
    event Executed(uint32 vid, address target, bytes callData, uint256 expiration, bytes signatures);

    uint32 public immutable vid;

    constructor(uint32 _vid) {
        vid = _vid;
    }

    function execute(ExecuteParam[] calldata _params) external {
        for (uint256 i = 0; i < _params.length; i++) {
            emit Executed(
                _params[i].vid,
                _params[i].target,
                _params[i].callData,
                _params[i].expiration,
                _params[i].signatures
            );
        }
    }

    function verify(bytes calldata _packetHeader, bytes32 _payloadHash, uint64 _confirmations) external {}
}
