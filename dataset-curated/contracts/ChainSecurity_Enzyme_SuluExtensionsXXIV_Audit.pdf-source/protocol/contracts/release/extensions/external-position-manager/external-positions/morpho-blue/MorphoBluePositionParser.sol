// SPDX-License-Identifier: GPL-3.0

/*
    This file is part of the Enzyme Protocol.

    (c) Enzyme Foundation <security@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.19;

import {
    IMorpho,
    MarketParams as MorphoLibMarketParams,
    MorphoBalancesLib
} from "morpho-blue/periphery/MorphoBalancesLib.sol";

import {IMorphoBlue} from "../../../../../external-interfaces/IMorphoBlue.sol";
import {IExternalPositionParser} from "../../IExternalPositionParser.sol";
import {IMorphoBluePosition} from "./IMorphoBluePosition.sol";
import {MorphoBluePositionDataDecoder} from "./MorphoBluePositionDataDecoder.sol";

/// @title MorphoBluePositionParser
/// @author Enzyme Foundation <security@enzyme.finance>
/// @notice Parser for Morpho Positions
contract MorphoBluePositionParser is MorphoBluePositionDataDecoder, IExternalPositionParser {
    IMorphoBlue private immutable MORPHO_BLUE;

    error InvalidActionId();

    constructor(address _morphoBlueAddress) {
        MORPHO_BLUE = IMorphoBlue(_morphoBlueAddress);
    }

    /// @notice Parses the assets to send and receive for the callOnExternalPosition
    /// @param _externalPositionAddress The address of the ExternalPositionProxy
    /// @param _actionId The _actionId for the callOnExternalPosition
    /// @param _encodedActionArgs The encoded parameters for the callOnExternalPosition
    /// @return assetsToTransfer_ The assets to be transferred from the Vault
    /// @return amountsToTransfer_ The amounts to be transferred from the Vault
    /// @return assetsToReceive_ The assets to be received at the Vault
    function parseAssetsForAction(address _externalPositionAddress, uint256 _actionId, bytes memory _encodedActionArgs)
        external
        view
        override
        returns (
            address[] memory assetsToTransfer_,
            uint256[] memory amountsToTransfer_,
            address[] memory assetsToReceive_
        )
    {
        if (_actionId == uint256(IMorphoBluePosition.Actions.Lend)) {
            (bytes32 marketId, uint256 assetsAmount) = __decodeLendActionArgs(_encodedActionArgs);

            assetsToTransfer_ = new address[](1);
            amountsToTransfer_ = new uint256[](1);

            assetsToTransfer_[0] = MORPHO_BLUE.idToMarketParams({_id: marketId}).loanToken;
            amountsToTransfer_[0] = assetsAmount;
        } else if (_actionId == uint256(IMorphoBluePosition.Actions.Redeem)) {
            (bytes32 marketId,) = __decodeRedeemActionArgs(_encodedActionArgs);

            assetsToReceive_ = new address[](1);
            assetsToReceive_[0] = MORPHO_BLUE.idToMarketParams({_id: marketId}).loanToken;
        } else if (_actionId == uint256(IMorphoBluePosition.Actions.AddCollateral)) {
            (bytes32 marketId, uint256 collateralAmount) = __decodeAddCollateralActionArgs(_encodedActionArgs);

            assetsToTransfer_ = new address[](1);
            amountsToTransfer_ = new uint256[](1);

            assetsToTransfer_[0] = MORPHO_BLUE.idToMarketParams({_id: marketId}).collateralToken;
            amountsToTransfer_[0] = collateralAmount;
        } else if (_actionId == uint256(IMorphoBluePosition.Actions.RemoveCollateral)) {
            (bytes32 marketId,) = __decodeRemoveCollateralActionArgs(_encodedActionArgs);

            assetsToReceive_ = new address[](1);
            assetsToReceive_[0] = MORPHO_BLUE.idToMarketParams({_id: marketId}).collateralToken;
        } else if (_actionId == uint256(IMorphoBluePosition.Actions.Borrow)) {
            (bytes32 marketId,) = __decodeBorrowActionArgs(_encodedActionArgs);

            assetsToReceive_ = new address[](1);

            assetsToReceive_[0] = MORPHO_BLUE.idToMarketParams({_id: marketId}).loanToken;
        } else if (_actionId == uint256(IMorphoBluePosition.Actions.Repay)) {
            (bytes32 marketId, uint256 repayAmount) = __decodeRepayActionArgs(_encodedActionArgs);

            assetsToTransfer_ = new address[](1);
            amountsToTransfer_ = new uint256[](1);

            IMorphoBlue.MarketParams memory marketParams = MORPHO_BLUE.idToMarketParams({_id: marketId});

            assetsToTransfer_[0] = marketParams.loanToken;
            if (repayAmount == type(uint256).max) {
                amountsToTransfer_[0] = MorphoBalancesLib.expectedBorrowAssets({
                    morpho: IMorpho(address(MORPHO_BLUE)),
                    marketParams: MorphoLibMarketParams({
                        loanToken: marketParams.loanToken,
                        collateralToken: marketParams.collateralToken,
                        oracle: marketParams.oracle,
                        irm: marketParams.irm,
                        lltv: marketParams.lltv
                    }),
                    user: _externalPositionAddress
                });
            } else {
                amountsToTransfer_[0] = repayAmount;
            }
        } else {
            revert InvalidActionId();
        }

        return (assetsToTransfer_, amountsToTransfer_, assetsToReceive_);
    }

    /// @notice Parse and validate input arguments to be used when initializing a newly-deployed ExternalPositionProxy
    function parseInitArgs(address, bytes memory) external pure override returns (bytes memory) {
        return "";
    }
}
