// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import { ExecuteParam } from "../uln/dvn/DVN.sol";

library DVNDecoder {
    uint8 internal constant DVN_INDEX_SIZE = 2; // uint16
    uint8 internal constant PARAMS_LENGTH_SIZE = 1; // uint8
    uint8 internal constant TARGET_INDEX_SIZE = 1; // uint8
    uint8 internal constant EXPIRATION_SIZE = 16; // uint128
    uint8 internal constant SIGNATURES_LENGTH_SIZE = 2; // uint16
    uint8 internal constant CALL_DATA_LENGTH_SIZE = 8; // uint64

    function execute(
        bytes calldata _encoded,
        uint32 _vid,
        mapping(uint8 index => address target) storage _targets
    ) internal view returns (uint16 dvnIndex, ExecuteParam[] memory params) {
        uint256 cursor = 0;

        dvnIndex = uint16(bytes2(_encoded[cursor:cursor + DVN_INDEX_SIZE]));
        cursor += DVN_INDEX_SIZE;

        uint8 length = uint8(bytes1(_encoded[cursor:cursor + PARAMS_LENGTH_SIZE]));
        cursor += PARAMS_LENGTH_SIZE;

        params = new ExecuteParam[](length);

        for (uint256 i = 0; i < length; i++) {
            uint8 targetIndex = uint8(bytes1(_encoded[cursor:cursor + TARGET_INDEX_SIZE]));
            cursor += TARGET_INDEX_SIZE;

            uint128 expiration = uint128(bytes16(_encoded[cursor:cursor + EXPIRATION_SIZE]));
            cursor += EXPIRATION_SIZE;

            uint16 signaturesLength = uint16(bytes2(_encoded[cursor:cursor + SIGNATURES_LENGTH_SIZE]));
            cursor += SIGNATURES_LENGTH_SIZE;

            bytes memory signatures = _encoded[cursor:cursor + signaturesLength];
            cursor += signaturesLength;

            uint64 callDataLength = uint64(bytes8(_encoded[cursor:cursor + CALL_DATA_LENGTH_SIZE]));
            cursor += CALL_DATA_LENGTH_SIZE;

            bytes memory callData = _encoded[cursor:cursor + callDataLength];
            cursor += callDataLength;

            params[i] = ExecuteParam(_vid, _targets[targetIndex], callData, expiration, signatures);
        }
    }
}
