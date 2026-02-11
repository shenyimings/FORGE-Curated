// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { OptionsBuilder } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";
import { SendParam, IOFT } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";
import { MessagingFee, MessagingReceipt } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/OFTCore.sol";
import { MessagingReceipt } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OAppSender.sol";
import { OFTMsgCodec } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/libs/OFTMsgCodec.sol";

import { FeeCollectorCore, SafeERC20, IERC20 } from "./FeeCollectorCore.sol";

/// @title SideChainFeeCollector
/// @author Cooper Labs
/// @custom:contact security@cooperlabs.xyz
/// @notice Handles the transfer of fee tokens to the MainFeeDistributor on the receiving chain.
contract SideChainFeeCollector is FeeCollectorCore {
    using SafeERC20 for IERC20;
    using OptionsBuilder for bytes;

    /// @notice BridgeableToken round down amount under the BRIDGEABLE_CONVERSION_DECIMALS
    uint256 private constant BRIDGEABLE_CONVERSION_DECIMALS = 1e12;

    //-------------------------------------------
    // Storage
    //-------------------------------------------
    /// @notice token bridgeableToken contract
    IOFT public bridgeableToken;

    /// @notice LayerZero Eid value of the receiving chain
    uint32 public lzEidReceiver;

    /// @notice Address of the wallet that will receive the fees on the receiving chain.
    address public destinationReceiver;

    //-------------------------------------------
    // Events
    //-------------------------------------------

    /// @notice Emitted when the fee token is released.
    event FeeReleased(address caller, uint256 amountSent);

    /// @notice Emitted when the destination receiver address is updated.
    event DestinationReceiverUpdated(address newDestinationReceiver);

    /// @notice Emitted when the bridgeable token is updated.
    event BridgeableTokenUpdated(address newBridgeableToken);

    //-------------------------------------------
    // Constructor
    //-------------------------------------------

    ///@notice SideChainFeeCollector constructor.
    ///@param _accessManager address of the AccessManager contract.
    ///@param _lzEidReceiver LayerZero Eid value of the receiving chain.
    ///@param _destinationReceiver address of the fee receiver on the destination chain.
    ///@param _bridgeableToken address of the bridgeable token.
    ///@param _feeToken address of the fee token.
    constructor(
        address _accessManager,
        uint32 _lzEidReceiver,
        address _bridgeableToken,
        address _destinationReceiver,
        address _feeToken
    )
        FeeCollectorCore(_accessManager, _feeToken)
    {
        destinationReceiver = _destinationReceiver;
        bridgeableToken = IOFT(_bridgeableToken);
        lzEidReceiver = _lzEidReceiver;
    }

    //-------------------------------------------
    // AccessManaged functions
    //-------------------------------------------

    /// @notice Release the fee token to the MainFeeDistributor on the receiving chain.
    /// @param _options Options to be passed to the bridgeable token.
    /// @return amountSent The amount of fee token that has been bridged.
    function release(bytes memory _options)
        external
        payable
        nonReentrant
        whenNotPaused
        restricted
        returns (uint256 amountSent)
    {
        amountSent = _calcBridgeableAmount();
        if (amountSent == 0) {
            revert NothingToRelease();
        }
        SendParam memory sendParam = SendParam(
            lzEidReceiver,
            OFTMsgCodec.addressToBytes32(destinationReceiver),
            amountSent,
            amountSent,
            _options,
            abi.encode(true),
            ""
        );

        feeToken.approve(address(bridgeableToken), amountSent);
        emit FeeReleased(msg.sender, amountSent);
        bridgeableToken.send{ value: msg.value }(sendParam, MessagingFee(msg.value, 0), payable(msg.sender));
    }

    /// @notice Update the destination receiver address.
    /// @param _newDestinationReceiver The new destination receiver address.
    function updateDestinationReceiver(address _newDestinationReceiver) external restricted {
        destinationReceiver = _newDestinationReceiver;
        emit DestinationReceiverUpdated(_newDestinationReceiver);
    }

    /// @notice Update the bridgeable token.
    /// @param _newBridgeableToken The new bridgeable token address.
    function updateBridgeableToken(address _newBridgeableToken) external restricted {
        bridgeableToken = IOFT(_newBridgeableToken);
        emit BridgeableTokenUpdated(_newBridgeableToken);
    }

    //-------------------------------------------
    // Internal/Private functions
    //-------------------------------------------

    /// @notice Calculate the amount of fee token that can be bridged
    /// @dev BridgeableToken contract remove dust under BRIDGEABLE_CONVERSION_DECIMALS
    /// @return The amount of fee token that will be bridged
    function _calcBridgeableAmount() private view returns (uint256) {
        uint256 feeTokenBalance = feeToken.balanceOf(address(this));
        return (feeTokenBalance / BRIDGEABLE_CONVERSION_DECIMALS) * BRIDGEABLE_CONVERSION_DECIMALS;
    }
}
