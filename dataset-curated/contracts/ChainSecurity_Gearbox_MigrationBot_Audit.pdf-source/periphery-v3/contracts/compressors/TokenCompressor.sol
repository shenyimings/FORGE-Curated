// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2025.
pragma solidity ^0.8.23;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {LibString} from "@solady/utils/LibString.sol";
import {ITokenCompressor} from "../interfaces/ITokenCompressor.sol";
import {AP_TOKEN_COMPRESSOR} from "../libraries/Literals.sol";
import {TokenData} from "../types/TokenData.sol";
import {BaseCompressor} from "./BaseCompressor.sol";

address constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

contract TokenCompressor is BaseCompressor, ITokenCompressor {
    uint256 public constant override version = 3_10;
    bytes32 public constant override contractType = AP_TOKEN_COMPRESSOR;

    constructor(address addressProvider_) BaseCompressor(addressProvider_) {}

    function getTokens(address[] memory tokens) external view returns (TokenData[] memory result) {
        result = new TokenData[](tokens.length);
        for (uint256 i; i < tokens.length; ++i) {
            result[i] = getTokenInfo(tokens[i]);
        }
    }

    function getTokenInfo(address token) public view returns (TokenData memory) {
        if (token == ETH_ADDRESS) return TokenData({addr: ETH_ADDRESS, symbol: "ETH", name: "Ether", decimals: 18});
        return TokenData({
            addr: token,
            symbol: _getStringField(token, "symbol()"),
            name: _getStringField(token, "name()"),
            decimals: ERC20(token).decimals()
        });
    }

    function _getStringField(address token, string memory signature) internal view returns (string memory) {
        (bool success, bytes memory data) = token.staticcall(abi.encodeWithSignature(signature));
        if (!success) revert(string.concat(signature, " call failed"));
        // account for some non-standard ERC20 implementations that return bytes32 for symbol and name
        return data.length == 32 ? LibString.fromSmallString(bytes32(data)) : abi.decode(data, (string));
    }
}
