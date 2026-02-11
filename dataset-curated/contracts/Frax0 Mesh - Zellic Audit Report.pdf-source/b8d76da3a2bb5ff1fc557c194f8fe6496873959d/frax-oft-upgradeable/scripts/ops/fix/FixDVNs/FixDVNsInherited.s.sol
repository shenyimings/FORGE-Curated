// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";

contract FixDVNsInherited is DeployFraxOFTProtocol {
    using OptionsBuilder for bytes;
    using stdJson for string;
    using Strings for uint256;

    uint256[] public chainIds;

    constructor() {
        // Initialize the chainIds array with the desired chain IDs
        chainIds = [
            1, // ethereum,
            10, // optimism
            56, // bsc
            137, // polygon
            146, // sonic
            196, // xlayer
            252, // fraxtal
            324, // zksync : skip
            1101, // polygon zkevm
            1329, // sei
            2741, // abstract :skip
            8453, // base
            34443, // mode
            42161, // arbitrum
            43114, // avalanche
            57073, // ink
            59144, // linea
            80094, // berachain
            81457, // blast
            480, // worldchain
            130 // unichain
        ];
    }
}
