// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {SignatureCheckerLib} from "solady/utils/SignatureCheckerLib.sol";

/// @notice Mock account contract for testing ERC-1271 signature validation
contract MockAccount is IERC1271 {
    /// @notice The EOA owner that controls this contract
    address public owner;

    /// @notice Flag for if accepting native tokens
    bool public acceptNativeToken;

    /// @notice ERC-1271 magic value for valid signatures
    bytes4 internal constant MAGICVALUE = 0x1626ba7e;

    /// @notice Constructor to set the EOA owner
    ///
    /// @param owner_ The EOA address that will control this contract
    constructor(address owner_, bool acceptNativeToken_) {
        owner = owner_;
        acceptNativeToken = acceptNativeToken_;
    }

    /// @notice Receiver for native token
    /// @dev Reverts if not accepting native token
    receive() external payable {
        if (!acceptNativeToken) revert("Native token not accepted");
    }

    /// @notice Set status for accepting native token
    ///
    /// @param acceptNativeToken_ Flag for if accepting or not
    function setAcceptNativeToken(bool acceptNativeToken_) external {
        acceptNativeToken = acceptNativeToken_;
    }

    /// @notice ERC-1271 signature validation
    ///
    /// @param hash The hash that was signed
    /// @param signature The signature to validate
    ///
    /// @return magicValue The ERC-1271 magic value if signature is valid
    function isValidSignature(bytes32 hash, bytes calldata signature)
        external
        view
        override
        returns (bytes4 magicValue)
    {
        if (SignatureCheckerLib.isValidSignatureNow(owner, hash, signature)) {
            return MAGICVALUE;
        }
        return bytes4(0);
    }
}
