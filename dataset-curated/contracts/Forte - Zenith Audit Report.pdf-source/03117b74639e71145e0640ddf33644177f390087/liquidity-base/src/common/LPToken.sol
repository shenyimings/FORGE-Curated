// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {ERC721} from "../../lib/openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";
import {ERC721Enumerable} from "../../lib/openzeppelin-contracts/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {IPoolEvents} from "./IEvents.sol";
import {packedFloat, MathLibs} from "../amm/mathLibs/MathLibs.sol";

/**
 * @title Liquidity provider token
 * @dev This contract serves as the LP Token associated with a liquidity position.
 * @dev Revenue and liquidity position are stored in the LP Token metadata and updated by the pool contract.
 * @author @palmerg4 @oscarsernarosero @cirsteve
 */
contract LPToken is ERC721, ERC721Enumerable {
    using MathLibs for packedFloat;

    uint256 public currentTokenId = 2;
    uint256 public constant INACTIVE_ID = 1;
    bool private inactiveCreated = false;

    mapping(address lp => mapping(uint256 tokenId => LPTokenS lpToken)) public lpToken;

    struct LPTokenS {
        packedFloat wj;
        packedFloat rj;
    }

    constructor(string memory _name, string memory _symbol) ERC721(_name, _symbol) {}

    /**
     * @dev Get the liquidity share and last claimed amount for an lpToken
     * @param lp The address of the liquidity provider owning the lpToken being updated
     * @param tokenId The token id of the lpToken being updated
     * @return wj the amount of the lpToken
     * @return rj the last revenue claim of the lpToken
     */
    function getLPToken(address lp, uint256 tokenId) public view returns (packedFloat wj, packedFloat rj) {
        LPTokenS memory token = lpToken[lp][tokenId];
        return (token.wj, token.rj);
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC721Enumerable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    /**
     * @dev Mints a new lpToken to a liquidity provider and updated the value associated with this new lpToken
     * @notice The internal version of the mint method. Used in the constructor, in order to circumvent ownership transfers.
     * @param lp The address of the liquidity provider owning the lpToken being updated
     * @param wj The amount of liquidity provided by the liquidity provider
     * @param hn The revenue parameter of the pool associated with the lpToken contract
     */
    function _mintTokenAndUpdate(address lp, packedFloat wj, packedFloat hn, bool inactive, uint256 tokenXAmount, uint256 tokenYAmount) internal {
        if(inactive) {
            if(!inactiveCreated) {
                inactiveCreated = true;
                _mint(lp, INACTIVE_ID);
                _updateLPTokenVarsDeposit(lp, 0, wj, hn);
            }
        } else {
            _mint(lp, currentTokenId);
            _updateLPTokenVarsDeposit(lp, currentTokenId, wj, hn);
            currentTokenId += 1;
        }
        emit IPoolEvents.LPTokenMinted(lp, currentTokenId, tokenXAmount, tokenYAmount);
    }

    /**
     * @dev Updates the values wj and rj of tokenId
     * @notice The internal version of the updateLPToken method. Used in the constructor, in order to circumvent ownership transfers.
     * @param lp The address of the liquidity provider owning the lpToken being updated
     * @param tokenId The token id of the lpToken being updated
     * @param wj The amount of liquidity associated with the lpToken being updated
     * @param rj The amount of revenue associated with the lpToken being updated
     */
    function _updateLPTokenVarsDeposit(address lp, uint256 tokenId, packedFloat wj, packedFloat rj) internal {
        lpToken[lp][tokenId].rj = rj;
        lpToken[lp][tokenId].wj =  lpToken[lp][tokenId].wj.add(wj);
    }

    /**
     * @dev Updates the values wj and rj of tokenId
     * @param lp The address of the liquidity provider owning the lpToken being updated
     * @param tokenId The token id of the lpToken being updated
     * @param addedRj The amount of revenue claimed to add to the lpToken being updated
     */
    function _updateLPTokenLastRevenueClaim(address lp, uint256 tokenId, packedFloat addedRj) internal {
        lpToken[lp][tokenId].rj = lpToken[lp][tokenId].rj.add(addedRj);
    }

    /**
     * @dev Calculates the value of rj for _tokenId. Used when updating a liquidity position.
     * @param _lp The address of the liquidity provider owning the lpToken being updated
     * @param _tokenId The token id of the lpToken being updated
     * @param _hn The amount of revenue associated with the lpToken being updated
     */
    /*function _calculateRj(address _lp, uint256 _tokenId, uint256 _wj, uint256 _hn) internal view returns (uint256 result) {
        uint256 w_hat = lpToken[_lp][_tokenId].wj;
        uint256 r_hat = lpToken[_lp][_tokenId].rj;
        r_hat == 0 ? result = (_hn * _wj) / (w_hat + _wj) : result = ((_hn * _wj) + (r_hat * w_hat) / (w_hat + _wj));
    }*/

    /**
     * @dev Updates the amount of liquidity associated with an LP Token. Used when withdrawing a full or partial liquidity position.
     * @notice If an LP is withdrawing their entire position, the LP Token associated will be burned.
     * @param _lp The address of the liquidity provider owning the lpToken being updated
     * @param _tokenId The token id of the lpToken being updated
     * @param _uj The amount of liquidity the LP would like to withdraw
     */
    function _updateLPTokenVarsWithdrawal(address _lp, uint256 _tokenId, packedFloat _uj) internal returns (packedFloat) {
        packedFloat wj = lpToken[_lp][_tokenId].wj;
        if (wj.lt(_uj)) revert("LPToken: withdrawal amount exceeds allowance");

        if (wj.gt(_uj)) {
            lpToken[_lp][_tokenId].wj =  lpToken[_lp][_tokenId].wj.sub(_uj);
        } else {
            _burn(_tokenId);
            lpToken[_lp][_tokenId].wj = packedFloat.wrap(0);
            emit IPoolEvents.LPTokenBurned(_lp, _tokenId, uint(_uj.convertpackedFloatToWAD()));
        }
        return lpToken[_lp][_tokenId].rj;
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
}
