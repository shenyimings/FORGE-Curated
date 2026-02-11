// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {OFT} from "@layerzerolabs/oft-evm/contracts/OFT.sol";

/// @notice OFT is an ERC-20 token that extends the OFTCore contract.
contract MyOFT is OFT {

    uint8 public underlyingDecimals;
    
    constructor(
        string memory _name,
        string memory _symbol,
        address _lzEndpoint,
        address _delegate,
        uint8 _underlyingDecimals
    ) OFT(_name, _symbol, _lzEndpoint, _delegate) Ownable(_delegate) {
        underlyingDecimals = _underlyingDecimals;
    }

    /**
     * @notice Returns the shared token decimals for OFT
     */
    function sharedDecimals() public view virtual override returns (uint8) {
        return decimals();
    }

    /**
     * @notice Returns the token decimals
     */
    function decimals() public view virtual override returns (uint8) {
        return underlyingDecimals;
    }
}
