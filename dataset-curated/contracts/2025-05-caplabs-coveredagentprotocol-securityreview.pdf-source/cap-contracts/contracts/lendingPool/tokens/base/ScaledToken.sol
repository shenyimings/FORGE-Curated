// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { IScaledToken } from "../../../interfaces/IScaledToken.sol";
import { ScaledTokenStorageUtils } from "../../../storage/ScaledTokenStorageUtils.sol";

import { WadRayMath } from "../../libraries/math/WadRayMath.sol";
import { MintableERC20 } from "./MintableERC20.sol";

/// @title ScaledToken
/// @author kexley, @capLabs
/// @notice A token that scales with an index, meant to be inherited by interest debt tokens
/// @dev The scaled balance of the user is multiplied by the change in index to get the actual balance
abstract contract ScaledToken is IScaledToken, MintableERC20, ScaledTokenStorageUtils {
    using WadRayMath for uint256;

    /// @dev Initialize the scaled token
    /// @param _name Name of the token
    /// @param _symbol Symbol of the token
    /// @param _decimals Decimals of the token
    function __ScaledToken_init(string memory _name, string memory _symbol, uint8 _decimals)
        internal
        onlyInitializing
    {
        __MintableERC20_init(_name, _symbol, _decimals);
    }

    /// @notice Mints a token to an address
    /// @param _agent The address to mint the token to
    /// @param _amount The amount of tokens to mint
    /// @param _index The index of the token
    function _mintScaled(address _agent, uint256 _amount, uint256 _index) internal {
        ScaledTokenStorage storage $ = getScaledTokenStorage();
        uint256 amountScaled = _amount.rayDiv(_index);

        if (amountScaled == 0) revert InvalidMintAmount();

        uint256 scaledBalance = super.balanceOf(_agent);
        uint256 balanceIncrease = scaledBalance.rayMul(_index) - scaledBalance.rayMul($.storedIndex[_agent]);

        $.storedIndex[_agent] = _index;

        _mint(_agent, amountScaled);

        uint256 amountToMint = _amount + balanceIncrease;
        emit Transfer(address(0), _agent, amountToMint);
    }

    /// @notice Burns a token from an address
    /// @param _agent The address to burn the token from
    /// @param _amount The amount of tokens to burn
    /// @param _index The index of the token
    function _burnScaled(address _agent, uint256 _amount, uint256 _index) internal {
        ScaledTokenStorage storage $ = getScaledTokenStorage();
        uint256 amountScaled = _amount.rayDiv(_index);

        if (amountScaled == 0) revert InvalidBurnAmount();

        uint256 scaledBalance = super.balanceOf(_agent);
        uint256 balanceIncrease = scaledBalance.rayMul(_index) - scaledBalance.rayMul($.storedIndex[_agent]);

        $.storedIndex[_agent] = _index;

        _burn(_agent, amountScaled);

        if (balanceIncrease > _amount) {
            uint256 amountToMint = balanceIncrease - _amount;
            emit Transfer(address(0), _agent, amountToMint);
        } else {
            uint256 amountToBurn = _amount - balanceIncrease;
            emit Transfer(_agent, address(0), amountToBurn);
        }
    }
}
