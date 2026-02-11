// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IERC1155 } from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import { Sickle } from "contracts/Sickle.sol";

interface INftTransferLib {
    /// @dev Transfers the ERC721 NFT with {tokenId} from the user to the Sickle
    function transferErc721FromUser(IERC721 nft, uint256 tokenId) external;

    /// @dev Transfers the ERC721 NFT with {tokenId} from the Sickle to the user
    function transferErc721ToUser(IERC721 nft, uint256 tokenId) external;

    /// @dev Transfers the ERC1155 NFT with {tokenId} from the user to Sickle
    function transferErc1155FromUser(
        IERC1155 nft,
        uint256 tokenId,
        uint256 amount
    ) external;

    /// @dev Transfers the ERC1155 NFT with {tokenId} from Sickle to the user
    function transferErc1155ToUser(
        IERC1155 nft,
        uint256 tokenId,
        uint256 amount
    ) external;
}
