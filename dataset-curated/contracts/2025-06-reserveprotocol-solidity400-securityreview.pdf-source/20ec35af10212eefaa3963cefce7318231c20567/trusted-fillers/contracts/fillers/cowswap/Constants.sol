// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IEIP712 {
    function domainSeparator() external view returns (bytes32);
}

// Same addresses on Mainnet, Base
IEIP712 constant GPV2_SETTLEMENT = IEIP712(0x9008D19f58AAbD9eD0D60971565AA8510560ab41);
address constant GPV2_VAULT_RELAYER = address(0xC92E8bdf79f0507f65a392b0ab4667716BFE0110);

uint256 constant D27 = 1e27; // D27
