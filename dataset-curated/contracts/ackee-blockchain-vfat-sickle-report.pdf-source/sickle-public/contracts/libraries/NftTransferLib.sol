// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IERC1155 } from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import { Sickle } from "contracts/Sickle.sol";
import { INftTransferLib } from
    "contracts/interfaces/libraries/INftTransferLib.sol";

contract NftTransferLib is INftTransferLib {
    /// @dev Transfers the ERC721 NFT with {tokenId} from the user to the Sickle
    function transferErc721FromUser(
        IERC721 nft,
        uint256 tokenId
    ) external override {
        nft.safeTransferFrom(
            Sickle(payable(address(this))).owner(), address(this), tokenId
        );
    }

    /// @dev Transfers the ERC721 NFT with {tokenId} from the Sickle to the user
    function transferErc721ToUser(
        IERC721 nft,
        uint256 tokenId
    ) external override {
        IERC721(nft).safeTransferFrom(
            address(this), Sickle(payable(address(this))).owner(), tokenId
        );
    }

    /// @dev Transfers the ERC1155 NFT with {tokenId} from the user to Sickle
    function transferErc1155FromUser(
        IERC1155 nft,
        uint256 tokenId,
        uint256 amount
    ) external override {
        nft.safeTransferFrom(
            Sickle(payable(address(this))).owner(),
            address(this),
            tokenId,
            amount,
            ""
        );
    }

    /// @dev Transfers the ERC1155 NFT with {tokenId} from Sickle to the user
    function transferErc1155ToUser(
        IERC1155 nft,
        uint256 tokenId,
        uint256 amount
    ) external override {
        nft.safeTransferFrom(
            address(this),
            Sickle(payable(address(this))).owner(),
            tokenId,
            amount,
            ""
        );
    }
}
