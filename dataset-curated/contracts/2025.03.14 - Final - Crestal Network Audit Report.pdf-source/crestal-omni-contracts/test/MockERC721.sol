// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract MockERC721 is IERC721 {
    mapping(uint256 => address) private _owners;

    function mint(address to, uint256 tokenId) public {
        _owners[tokenId] = to;
    }

    function ownerOf(uint256 tokenId) public view override returns (address) {
        return _owners[tokenId];
    }

    // The following functions are not implemented for simplicity
    function balanceOf(address /* owner */ ) public pure override returns (uint256) {
        return 0;
    }

    function transferFrom(address from, address to, uint256 tokenId) public override {}
    function approve(address to, uint256 tokenId) public override {}

    function getApproved(uint256 /* tokenId */ ) public pure override returns (address) {
        return address(0);
    }

    function setApprovalForAll(address operator, bool approved) public override {}

    function isApprovedForAll(address, /* owner */ address /* operator */ ) public pure override returns (bool) {
        return false;
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata data) public override {}
    function safeTransferFrom(address from, address to, uint256 tokenId) public override {}

    function supportsInterface(bytes4 /* interfaceId */ ) public pure override returns (bool) {
        return false;
    }
}
