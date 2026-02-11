// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { OFTAdapter } from "@layerzerolabs/oft-evm/contracts/OFTAdapter.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/// @title OFT Lockbox
/// @author kexley, @capLabs
contract OFTLockbox is OFTAdapter {
    /// @dev Initialize the cap token lockbox
    /// @param _token Token address
    /// @param _lzEndpoint Layerzero endpoint
    /// @param _delegate Delegate capable of making OApp changes
    constructor(address _token, address _lzEndpoint, address _delegate)
        OFTAdapter(_token, _lzEndpoint, _delegate)
        Ownable(_delegate)
    { }
}
