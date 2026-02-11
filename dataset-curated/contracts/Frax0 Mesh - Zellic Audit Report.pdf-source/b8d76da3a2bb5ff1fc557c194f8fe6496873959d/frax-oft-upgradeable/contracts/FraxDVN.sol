// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import { DVN } from "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/dvn/DVN.sol";

contract FraxDVN is DVN {
    constructor(
        uint32 _localEidV2,
        uint32 _vid,
        address[] memory _messageLibs,
        address _priceFeed,
        address[] memory _signers,
        uint64 _quorum,
        address[] memory _admins
    ) DVN(_localEidV2, _vid, _messageLibs, _priceFeed, _signers, _quorum, _admins) {}
}
