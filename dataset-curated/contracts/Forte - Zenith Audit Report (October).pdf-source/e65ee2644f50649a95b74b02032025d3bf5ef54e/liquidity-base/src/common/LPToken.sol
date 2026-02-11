// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {ERC721, IERC165} from "../../lib/openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";
import {ERC721Enumerable} from "../../lib/openzeppelin-contracts/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {ILPTokenEvents} from "./IEvents.sol";
import "./IErrors.sol";
import {packedFloat, MathLibs} from "../amm/mathLibs/MathLibs.sol";
import {ILPToken, LPTokenS} from "./ILPToken.sol";
import {Descriptor} from "../common/SVG/NFTSVG.sol";
import "../../lib/openzeppelin-contracts/contracts/access/Ownable2Step.sol";

/**
 * @title Liquidity provider token
 * @dev This contract serves as the LP Token associated with a liquidity position.
 * @dev Revenue and liquidity position are stored in the LP Token metadata and updated by the pool contract.
 * @author @palmerg4 @oscarsernarosero @cirsteve
 */
contract LPToken is Ownable2Step, ERC721, ERC721Enumerable, ILPToken {
    using MathLibs for packedFloat;

    uint256 public currentTokenId;
    address public factoryAddress;
    address public factoryAddressProposed;

    // id => (wj, rj)
    mapping(uint256 tokenId => LPTokenS lpToken) lpToken;
    // id => pool it belongs to
    mapping(uint256 tokenId => address pool) public idToPool;
    // pool allowlist
    mapping(address pool => bool isAllowed) allowedPool;
    // inactive tokens
    mapping(uint256 tokenId => bool isInactive) public inactiveToken;

    modifier onlyAllowedPools() {
        if (!allowedPool[msg.sender]) revert PoolNotAllowed();
        _;
    }

    modifier onlyTokensFromPool(uint256 tokenId) {
        if (msg.sender != idToPool[tokenId]) revert TokenNotFromPool();
        _;
    }

    modifier onlyFactory() {
        if (msg.sender != factoryAddress) revert NotFactory();
        _;
    }

    constructor(string memory _name, string memory _symbol) Ownable(msg.sender) ERC721(_name, _symbol) {
        emit ILPTokenEvents.ALTBCPositionTokenDeployed();
    }

    /**
     * @dev Get the liquidity share and last claimed amount for an lpToken
     * @param tokenId The token id of the lpToken being updated
     * @return wj the amount of the lpToken
     * @return rj the last revenue claim of the lpToken
     */
    function getLPToken(uint256 tokenId) public view returns (packedFloat wj, packedFloat rj) {
        LPTokenS memory token = lpToken[tokenId];
        return (token.wj, token.rj);
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC721Enumerable, IERC165) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    /**
     * @dev Mints a new lpToken to a liquidity provider and updated the value associated with this new lpToken
     * @notice The internal version of the mint method. Used in the constructor, in order to circumvent ownership transfers.
     * @param lp The address of the liquidity provider owning the lpToken being updated
     * @param wj The amount of liquidity provided by the liquidity provider
     * @param hn The revenue parameter of the pool associated with the lpToken contract
     */
    function mintTokenAndUpdate(address lp, packedFloat wj, packedFloat hn) external onlyAllowedPools returns (uint256 tokenId) {
        currentTokenId++;
        _mint(lp, currentTokenId);
        idToPool[currentTokenId] = msg.sender;
        updateLPToken(currentTokenId, wj, hn);
        tokenId = currentTokenId;
    }

    /**
     * @dev Updates the values wj and rj of tokenId
     * @notice The internal version of the updateLPToken method. Used in the constructor, in order to circumvent ownership transfers.
     * @param tokenId The token id of the lpToken being updated
     * @param _wj The amount of liquidity associated with the lpToken being updated
     * @param _rj The amount of revenue associated with the lpToken being updated
     */
    function updateLPToken(uint256 tokenId, packedFloat _wj, packedFloat _rj) public onlyTokensFromPool(tokenId) {
        lpToken[tokenId].rj = _rj;
        lpToken[tokenId].wj = _wj;
        emit ILPTokenEvents.LPTokenUpdated(tokenId, _wj, _rj);
    }

    /**
     * @dev Updates the amount of liquidity associated with an LP Token. Used when withdrawing a full or partial liquidity position.
     * @notice If an LP is withdrawing their entire position, the LP Token associated will be burned.
     * @param _tokenId The token id of the lpToken being updated
     * @param _wj The amount of liquidity the LP would like to withdraw
     * @param _rj The new value of _rj
     */
    function updateLPTokenWithdrawal(uint256 _tokenId, packedFloat _wj, packedFloat _rj) external {
        updateLPToken(_tokenId, _wj, _rj);
        if (_wj.eq(packedFloat.wrap(0))) {
            if (msg.sender != idToPool[_tokenId]) revert TokenNotFromPool();
            _burn(_tokenId);
            delete lpToken[_tokenId];
        }
    }

    /**
     * @dev See {ERC721-_update}.
     */
    function _update(address to, uint256 tokenId, address auth) internal override(ERC721, ERC721Enumerable) returns (address) {
        return super._update(to, tokenId, auth);
    }

    /**
     * See {ERC721-_increaseBalance}. We need that to account tokens that were minted in batch
     */
    function _increaseBalance(address account, uint128 value) internal override(ERC721, ERC721Enumerable) {
        super._increaseBalance(account, value);
    }

    /**
     * @dev add a pool to the allow list
     * @param pool the address of the pool to be added
     * @notice Only the factory should be able to add pools to the allow list
     */
    function addPoolToAllowList(address pool) external onlyFactory {
        if (pool == address(0)) revert ZeroAddress();
        if (allowedPool[pool]) revert PoolAlreadyAllowed();
        allowedPool[pool] = true;
        inactiveToken[currentTokenId + 1] = true;
        emit ILPTokenEvents.PoolAddedToAllowList(pool, currentTokenId + 1);
    }

    /**
     * @dev tells is a pool is allowed
     * @param pool the address of the pool to be added
     * @return true if the pool is allowed
     */
    function isPoolAllowed(address pool) external view returns (bool) {
        return allowedPool[pool];
    }

    /**
     * @dev propose the factory address
     * @param factory the address of the proposed factory
     * @notice Only the owner should be able to propose a factory
     */
    function proposeFactoryAddress(address factory) external onlyOwner {
        if (factory == address(0)) revert ZeroAddress();
        factoryAddressProposed = factory;
        emit ILPTokenEvents.FactoryProposed(factory);
    }

    /**
     * @dev confirm the factory address
     * @notice Only the proposed factory should be able to confirm the factory address
     */
    function confirmFactoryAddress() external {
        if (msg.sender != factoryAddressProposed) revert NotProposedFactory(factoryAddressProposed);
        delete factoryAddressProposed;
        factoryAddress = msg.sender;
        emit ILPTokenEvents.FactoryConfirmed(msg.sender);
    }

    /**
     * @dev Overrides the tokenURI function from ERC721 to generate an NFT with pool information
     * @param tokenId The token ID to generate the URI for
     * @return The token URI with SVG image and metadata
     */
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        if (_ownerOf(tokenId) == address(0)) revert URIQueryForNonexistentToken();
        return Descriptor.constructTokenURI(tokenId, idToPool[tokenId], inactiveToken[tokenId]);
    }
}
