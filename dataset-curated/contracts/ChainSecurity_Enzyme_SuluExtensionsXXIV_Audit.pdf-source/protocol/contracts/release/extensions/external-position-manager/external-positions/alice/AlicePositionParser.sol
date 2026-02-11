// SPDX-License-Identifier: GPL-3.0

/*
    This file is part of the Enzyme Protocol.

    (c) Enzyme Foundation <security@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.19;

import {IAliceOrderManager} from "../../../../../external-interfaces/IAliceOrderManager.sol";
import {IERC20} from "../../../../../external-interfaces/IERC20.sol";
import {AddressArrayLib} from "../../../../../utils/0.8.19/AddressArrayLib.sol";
import {IExternalPositionParser} from "../../IExternalPositionParser.sol";
import {AlicePositionLibBase1} from "./bases/AlicePositionLibBase1.sol";
import {IAlicePosition} from "./IAlicePosition.sol";

/// @title AlicePositionParser
/// @author Enzyme Foundation <security@enzyme.finance>
/// @notice Parser for Morpho Positions
contract AlicePositionParser is IExternalPositionParser {
    using AddressArrayLib for address[];

    address private constant ALICE_NATIVE_ETH = 0x0000000000000000000000000000000000000000;
    IAliceOrderManager private immutable ALICE_ORDER_MANAGER;
    address private immutable WRAPPED_NATIVE_TOKEN_ADDRESS;

    error InvalidActionId();

    constructor(address _aliceOrderManagerAddress, address _wrappedNativeAssetAddress) {
        ALICE_ORDER_MANAGER = IAliceOrderManager(_aliceOrderManagerAddress);
        WRAPPED_NATIVE_TOKEN_ADDRESS = _wrappedNativeAssetAddress;
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
        if (_actionId == uint256(IAlicePosition.Actions.PlaceOrder)) {
            IAlicePosition.PlaceOrderActionArgs memory placeOrderArgs =
                abi.decode(_encodedActionArgs, (IAlicePosition.PlaceOrderActionArgs));

            IAliceOrderManager.Instrument memory instrument =
                ALICE_ORDER_MANAGER.getInstrument(placeOrderArgs.instrumentId, true);

            assetsToTransfer_ = new address[](1);
            amountsToTransfer_ = new uint256[](1);

            address sellAssetAddress = placeOrderArgs.isBuyOrder ? instrument.quote : instrument.base;

            if (sellAssetAddress == ALICE_NATIVE_ETH) {
                assetsToTransfer_[0] = WRAPPED_NATIVE_TOKEN_ADDRESS;
            } else {
                assetsToTransfer_[0] = sellAssetAddress;
            }
            amountsToTransfer_[0] = placeOrderArgs.quantityToSell;
        } else if (_actionId == uint256(IAlicePosition.Actions.Sweep)) {
            IAlicePosition.SweepActionArgs memory sweepArgs =
                abi.decode(_encodedActionArgs, (IAlicePosition.SweepActionArgs));

            // Sweep can return either the outgoing or incoming asset (depending on if order is settled or cancelled) so we need to include both
            for (uint256 i; i < sweepArgs.orderIds.length; i++) {
                AlicePositionLibBase1.OrderDetails memory orderDetails =
                    IAlicePosition(_externalPositionAddress).getOrderDetails(sweepArgs.orderIds[i]);

                uint256 outgoingAssetBalance = orderDetails.outgoingAssetAddress == ALICE_NATIVE_ETH
                    ? _externalPositionAddress.balance
                    : IERC20(orderDetails.outgoingAssetAddress).balanceOf(_externalPositionAddress);
                uint256 incomingAssetBalance = orderDetails.incomingAssetAddress == ALICE_NATIVE_ETH
                    ? _externalPositionAddress.balance
                    : IERC20(orderDetails.incomingAssetAddress).balanceOf(_externalPositionAddress);

                if (outgoingAssetBalance > 0) {
                    assetsToReceive_ = assetsToReceive_.addUniqueItem(
                        __parseAliceAsset({_rawAssetAddress: orderDetails.outgoingAssetAddress})
                    );
                }

                if (incomingAssetBalance > 0) {
                    assetsToReceive_ = assetsToReceive_.addUniqueItem(
                        __parseAliceAsset({_rawAssetAddress: orderDetails.incomingAssetAddress})
                    );
                }
            }
        } else if (_actionId == uint256(IAlicePosition.Actions.RefundOrder)) {
            IAlicePosition.RefundOrderActionArgs memory refundOrderArgs =
                abi.decode(_encodedActionArgs, (IAlicePosition.RefundOrderActionArgs));

            AlicePositionLibBase1.OrderDetails memory orderDetails =
                IAlicePosition(_externalPositionAddress).getOrderDetails(refundOrderArgs.orderId);

            assetsToReceive_ = new address[](1);
            assetsToReceive_[0] = __parseAliceAsset({_rawAssetAddress: orderDetails.outgoingAssetAddress});
        } else {
            revert InvalidActionId();
        }

        return (assetsToTransfer_, amountsToTransfer_, assetsToReceive_);
    }

    /// @dev Parses Alice Native Asset into the wrapped native asset, otherwise returns the asset unchanged.
    function __parseAliceAsset(address _rawAssetAddress) private view returns (address parsedAssetAddress_) {
        return _rawAssetAddress == ALICE_NATIVE_ETH ? WRAPPED_NATIVE_TOKEN_ADDRESS : _rawAssetAddress;
    }

    /// @notice Parse and validate input arguments to be used when initializing a newly-deployed ExternalPositionProxy
    function parseInitArgs(address, bytes memory) external pure override returns (bytes memory) {
        return "";
    }
}
