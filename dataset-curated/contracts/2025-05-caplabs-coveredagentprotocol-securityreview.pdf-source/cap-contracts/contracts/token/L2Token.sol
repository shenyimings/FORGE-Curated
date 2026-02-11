// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { OFTPermit } from "./OFTPermit.sol";

/// @title L2 Token
/// @author kexley, @capLabs
/// @notice L2 Token with permit functions
contract L2Token is OFTPermit {
    /// @dev Initialize the L2 token
    /// @param _name Name of the token
    /// @param _symbol Symbol of the token
    /// @param _lzEndpoint Layerzero endpoint
    /// @param _delegate Delegate capable of making OApp changes
    constructor(
        string memory _name,
        string memory _symbol,
        address _lzEndpoint,
        address _delegate
    ) OFTPermit(_name, _symbol, _lzEndpoint, _delegate) {}
}
