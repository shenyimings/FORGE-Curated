// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {NeuV1} from "../old/NeuV1.sol";
import {NeuV2} from "../old/NeuV2.sol";
import {NeuV3} from "../current/NeuV3.sol";

contract NeuHarnessV1 is NeuV1 {
    function $_mint(address account, uint256 tokenId) external {
        _mint(account, tokenId);
    }

    function $_safeMint(address to, uint256 tokenId) external {
        _safeMint(to, tokenId);
    }

    function $_safeMint(address to, uint256 tokenId, bytes memory data) external {
        _safeMint(to, tokenId, data);
    }

    function $_burn(uint256 tokenId) external {
        _burn(tokenId);
    }

    function $_safeTransfer(address from, address to, uint256 tokenId) external {
        _safeTransfer(from, to, tokenId, "");
    }

    function $_safeTransfer(address from, address to, uint256 tokenId, bytes memory data) external {
        _safeTransfer(from, to, tokenId, data);
    }

    function $_transfer(address from, address to, uint256 tokenId) external {
        _transfer(from, to, tokenId);
    }

    function $_unsafeOwnerOf(uint256 tokenId) external view returns (address) {
        return _ownerOf(tokenId);
    }

    function $_unsafeGetApproved(uint256 tokenId) external view returns (address) {
        return _getApproved(tokenId);
    }
}

contract NeuHarnessV2 is NeuV2 {
    function $_mint(address account, uint256 tokenId) external {
        _mint(account, tokenId);
    }

    function $_safeMint(address to, uint256 tokenId) external {
        _safeMint(to, tokenId);
    }

    function $_safeMint(address to, uint256 tokenId, bytes memory data) external {
        _safeMint(to, tokenId, data);
    }

    function $_burn(uint256 tokenId) external {
        _burn(tokenId);
    }

    function $_safeTransfer(address from, address to, uint256 tokenId) external {
        _safeTransfer(from, to, tokenId, "");
    }

    function $_safeTransfer(address from, address to, uint256 tokenId, bytes memory data) external {
        _safeTransfer(from, to, tokenId, data);
    }

    function $_transfer(address from, address to, uint256 tokenId) external {
        _transfer(from, to, tokenId);
    }

    function $_unsafeOwnerOf(uint256 tokenId) external view returns (address) {
        return _ownerOf(tokenId);
    }

    function $_unsafeGetApproved(uint256 tokenId) external view returns (address) {
        return _getApproved(tokenId);
    }
}

contract NeuHarnessV3 is NeuV3 {
    function $_mint(address account, uint256 tokenId) external {
        _mint(account, tokenId);
    }

    function $_safeMint(address to, uint256 tokenId) external {
        _safeMint(to, tokenId);
    }

    function $_safeMint(address to, uint256 tokenId, bytes memory data) external {
        _safeMint(to, tokenId, data);
    }

    function $_burn(uint256 tokenId) external {
        _burn(tokenId);
    }

    function $_safeTransfer(address from, address to, uint256 tokenId) external {
        _safeTransfer(from, to, tokenId, "");
    }

    function $_safeTransfer(address from, address to, uint256 tokenId, bytes memory data) external {
        _safeTransfer(from, to, tokenId, data);
    }

    function $_transfer(address from, address to, uint256 tokenId) external {
        _transfer(from, to, tokenId);
    }

    function $_unsafeOwnerOf(uint256 tokenId) external view returns (address) {
        return _ownerOf(tokenId);
    }

    function $_unsafeGetApproved(uint256 tokenId) external view returns (address) {
        return _getApproved(tokenId);
    }
}