// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IBridgeCoordinatorL1Outbound } from "../../src/interfaces/IBridgeCoordinatorL1Outbound.sol";

contract MockBridgeCoordinatorL1 is IBridgeCoordinatorL1Outbound {
    using SafeERC20 for IERC20;

    IERC20 public immutable shareToken;

    struct BridgeCallParams {
        uint16 bridgeType;
        uint256 chainId;
        address onBehalf;
        bytes32 remoteRecipient;
        address sourceWhitelabel;
        bytes32 destinationWhitelabel;
        uint256 amount;
        bytes bridgeParams;
    }

    struct PredepositParams {
        bytes32 chainNickname;
        address onBehalf;
        bytes32 remoteRecipient;
        uint256 amount;
    }

    BridgeCallParams public lastBridgeCall;
    bytes32 public messageId;
    PredepositParams public lastPredepositCall;

    constructor(IERC20 _shareToken) {
        shareToken = _shareToken;
    }

    function returnMessageId(bytes32 messageId_) external {
        messageId = messageId_;
    }

    function bridge(
        uint16 bridgeType,
        uint256 chainId,
        address onBehalf,
        bytes32 remoteRecipient,
        address sourceWhitelabel,
        bytes32 destinationWhitelabel,
        uint256 amount,
        bytes calldata bridgeParams
    )
        external
        payable
        returns (bytes32)
    {
        lastBridgeCall = BridgeCallParams({
            bridgeType: bridgeType,
            chainId: chainId,
            onBehalf: onBehalf,
            remoteRecipient: remoteRecipient,
            sourceWhitelabel: sourceWhitelabel,
            destinationWhitelabel: destinationWhitelabel,
            amount: amount,
            bridgeParams: bridgeParams
        });
        shareToken.safeTransferFrom(msg.sender, address(this), amount);
        return messageId;
    }

    function predeposit(
        bytes32 chainNickname,
        address onBehalf,
        bytes32 remoteRecipient,
        uint256 amount
    )
        external
    {
        lastPredepositCall = PredepositParams({
            chainNickname: chainNickname, onBehalf: onBehalf, remoteRecipient: remoteRecipient, amount: amount
        });
        shareToken.safeTransferFrom(msg.sender, address(this), amount);
    }
}
