// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

// https://eips.ethereum.org/EIPS/eip-7579
// https://eips.ethereum.org/EIPS/eip-7821
bytes1 constant CALL_TYPE_BATCH = 0x01;
bytes1 constant EXEC_TYPE_DEFAULT = 0x00;
bytes4 constant EXEC_MODE_DEFAULT = 0x00000000;
bytes4 constant EXEC_MODE_OP_DATA = 0x78210001;

// https://eips.ethereum.org/EIPS/eip-4337
address constant ENTRY_POINT_V8 = 0x4337084D9E255Ff0702461CF8895CE9E3b5Ff108;

address constant NATIVE_TOKEN = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
