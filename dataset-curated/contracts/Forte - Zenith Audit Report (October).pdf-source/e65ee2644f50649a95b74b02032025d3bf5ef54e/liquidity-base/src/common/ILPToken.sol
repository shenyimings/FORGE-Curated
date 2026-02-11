// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {IERC721} from "../../lib/openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";
import {IERC721Enumerable} from "../../lib/openzeppelin-contracts/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import {packedFloat} from "../amm/mathLibs/MathLibs.sol";

/**
 * @title Interface Liquidity Provider Token
 * @dev This contract serves as the LP Token associated with all ALTBC liquidity positions.
 * @dev Revenue and liquidity position are stored in the LP Token data and updated by the pool contract.
 * @author @palmerg4 @oscarsernarosero @cirsteve
 */

struct LPTokenS {
    packedFloat wj;
    packedFloat rj;
}

interface ILPToken is IERC721, IERC721Enumerable {
    /**
     * @dev Get the liquidity share and last claimed amount for an lpToken
     * @param tokenId The token id of the lpToken being updated
     * @return wj the amount of the lpToken
     * @return rj the last revenue claim of the lpToken
     */
    function getLPToken(uint256 tokenId) external view returns (packedFloat wj, packedFloat rj);

    /**
     * @dev Get the inactive status tokenId
     * @param tokenId The token id of the lpToken being queried
     * @return bool true if the token is inactive
     */
    function inactiveToken(uint256 tokenId) external view returns (bool);

    /**
     * @dev Mints a new lpToken to a liquidity provider and updated the value associated with this new lpToken
     * @notice The internal version of the mint method. Used in the constructor, in order to circumvent ownership transfers.
     * @param lp The address of the liquidity provider owning the lpToken being updated
     * @param wj The amount of liquidity provided by the liquidity provider
     * @param hn The revenue parameter of the pool associated with the lpToken contract
     * @notice this function should be gated to only allwed pools
     */
    function mintTokenAndUpdate(address lp, packedFloat wj, packedFloat hn) external returns (uint256 tokenId);

    /**
     * @dev Updates the values wj and rj of tokenId
     * @param tokenId The token id of the lpToken being updated
     * @param _wj The amount of liquidity associated with the lpToken being updated
     * @param _rj The amount of revenue associated with the lpToken being updated
     * @notice this function should be gated to only Ids that belong to the caller pool
     */
    function updateLPToken(uint256 tokenId, packedFloat _wj, packedFloat _rj) external;

    /**
     * @dev Updates the amount of liquidity associated with an LP Token. Used when withdrawing a full or partial liquidity position.     * @param _tokenId The token id of the lpToken being updated
     * @param _wj The amount of liquidity the LP would like to withdraw
     * @param _rj The new value of _rj
     * @notice this function should be gated to only allwed pools
     */
    function updateLPTokenWithdrawal(uint256 _tokenId, packedFloat _wj, packedFloat _rj) external;

    /**
     * @dev gets current token id which means the latest token id to be minted
     * @return the current token id
     */
    function currentTokenId() external view returns (uint256);

    /**
     * @dev add a pool to the allow list
     * @param pool the address of the pool to be added
     * @notice Only the factory should be able to add pools to the allow list
     */
    function addPoolToAllowList(address pool) external;

    /**
     * @dev tells is a pool is allowed
     * @param pool the address of the pool to be added
     * @return true if the pool is allowed
     */
    function isPoolAllowed(address pool) external view returns (bool);

    /**
     * @dev propose the factory address
     * @param factory the address of the proposed factory
     * @notice Only the owner should be able to propose a factory
     */
    function proposeFactoryAddress(address factory) external;

    /**
     * @dev gets the factory address
     * @return the address of the factory
     */
    function factoryAddressProposed() external view returns (address);

    /**
     * @dev confirm the factory address
     * @notice Only the proposed factory should be able to confirm the factory address
     */
    function confirmFactoryAddress() external;

    /**
     * @dev gets the factory address
     * @return the address of the factory
     */
    function factoryAddress() external view returns (address);
}
