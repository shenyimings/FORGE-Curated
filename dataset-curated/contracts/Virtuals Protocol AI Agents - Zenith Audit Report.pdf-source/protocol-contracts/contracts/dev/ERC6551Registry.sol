// SPDX-License-Identifier: UNLICENSED
// This is a fake ERC6551 Registry
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Create2.sol";

import "../libs/IERC6551Registry.sol";
import "./ERC6551BytecodeLib.sol";

contract ERC6551Registry is IERC6551Registry {
    error InitializationFailed();

    function createAccount(
        address implementation,
        bytes32 salt,
        uint256 chainId,
        address tokenContract,
        uint256 tokenId
    ) external returns (address) {
        return 0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc;
    }

    function account(
        address implementation,
        uint256 chainId,
        address tokenContract,
        uint256 tokenId,
        uint256 salt
    ) external view returns (address) {
        return 0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc;
    }
}
