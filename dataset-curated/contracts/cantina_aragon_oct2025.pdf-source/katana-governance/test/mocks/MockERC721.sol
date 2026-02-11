// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

contract MockERC721 is ERC721 {
    uint256 private _nextTokenId = 1;
    address public underlying = address(0x1111111111111111111111111111111111111111);

    constructor() ERC721("name", "symbol") { }

    function mint(address to) external returns (uint256) {
        uint256 tokenId = _nextTokenId++;
        _mint(to, tokenId);
        return tokenId;
    }

    function burn(uint256 tokenId) external {
        _burn(tokenId);
    }

    function isApprovedOrOwner(uint256 tokenId) external view returns (bool) {
        return _isApprovedOrOwner(msg.sender, tokenId);
    }
}

contract ERC721ReceiverMock is MockERC721, IERC721Receiver {
    function onERC721Received(address, address, uint256, bytes calldata) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
}
