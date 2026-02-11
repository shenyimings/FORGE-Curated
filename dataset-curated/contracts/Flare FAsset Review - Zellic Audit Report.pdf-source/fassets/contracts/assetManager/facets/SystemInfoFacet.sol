// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {AssetManagerBase} from "./AssetManagerBase.sol";
import {AssetManagerState} from "../library/data/AssetManagerState.sol";
import {Conversion} from "../library/Conversion.sol";
import {RedemptionQueueInfo} from "../library/RedemptionQueueInfo.sol";
import {Minting} from "../library/Minting.sol";
import {Redemptions} from "../library/Redemptions.sol";
import {Agent} from "../library/data/Agent.sol";
import {CollateralReservation} from "../library/data/CollateralReservation.sol";
import {PaymentReference} from "../library/data/PaymentReference.sol";
import {Redemption} from "../library/data/Redemption.sol";
import {CollateralReservationInfo} from "../../userInterfaces/data/CollateralReservationInfo.sol";
import {RedemptionRequestInfo} from "../../userInterfaces/data/RedemptionRequestInfo.sol";
import {RedemptionTicketInfo} from "../../userInterfaces/data/RedemptionTicketInfo.sol";


contract SystemInfoFacet is AssetManagerBase {
    /**
     * When `controllerAttached` is true, asset manager has been added to the asset manager controller.
     */
    function controllerAttached()
        external view
        returns (bool)
    {
        AssetManagerState.State storage state = AssetManagerState.get();
        return state.attached;
    }

    /**
     * True if asset manager is paused.
     */
    function mintingPaused()
        external view
        returns (bool)
    {
        AssetManagerState.State storage state = AssetManagerState.get();
        return state.mintingPausedAt != 0;
    }

    /**
     * Return (part of) the redemption queue.
     * @param _firstRedemptionTicketId the ticket id to start listing from; if 0, starts from the beginning
     * @param _pageSize the maximum number of redemption tickets to return
     * @return _queue the (part of) the redemption queue; maximum length is _pageSize
     * @return _nextRedemptionTicketId works as a cursor - if the _pageSize is reached and there are more tickets,
     *  it is the first ticket id not returned; if the end is reached, it is 0
     */
    function redemptionQueue(
        uint256 _firstRedemptionTicketId,
        uint256 _pageSize
    )
        external view
        returns (RedemptionTicketInfo.Data[] memory _queue, uint256 _nextRedemptionTicketId)
    {
        return RedemptionQueueInfo.redemptionQueue(_firstRedemptionTicketId, _pageSize);
    }

    /**
     * Return (part of) the redemption queue for a specific agent.
     * @param _agentVault the agent vault address of the queried agent
     * @param _firstRedemptionTicketId the ticket id to start listing from; if 0, starts from the beginning
     * @param _pageSize the maximum number of redemption tickets to return
     * @return _queue the (part of) the redemption queue; maximum length is _pageSize
     * @return _nextRedemptionTicketId works as a cursor - if the _pageSize is reached and there are more tickets,
     *  it is the first ticket id not returned; if the end is reached, it is 0
     */
    function agentRedemptionQueue(
        address _agentVault,
        uint256 _firstRedemptionTicketId,
        uint256 _pageSize
    )
        external view
        returns (RedemptionTicketInfo.Data[] memory _queue, uint256 _nextRedemptionTicketId)
    {
        return RedemptionQueueInfo.agentRedemptionQueue(_agentVault, _firstRedemptionTicketId, _pageSize);
    }

    function collateralReservationInfo(
        uint256 _collateralReservationId
    )
        external view
        returns (CollateralReservationInfo.Data memory)
    {
        uint64 crtId = SafeCast.toUint64(_collateralReservationId);
        CollateralReservation.Data storage crt = Minting.getCollateralReservation(crtId, false);
        Agent.State storage agent = Agent.get(crt.agentVault);
        return CollateralReservationInfo.Data({
            collateralReservationId: crtId,
            agentVault: crt.agentVault,
            minter: crt.minter,
            paymentAddress: agent.underlyingAddressString,
            paymentReference: PaymentReference.minting(crtId),
            valueUBA: Conversion.convertAmgToUBA(crt.valueAMG),
            mintingFeeUBA: crt.underlyingFeeUBA,
            reservationFeeNatWei: crt.reservationFeeNatWei,
            poolFeeShareBIPS: Minting.reservationPoolFeeShare(agent, crt),
            firstUnderlyingBlock: crt.firstUnderlyingBlock,
            lastUnderlyingBlock: crt.lastUnderlyingBlock,
            lastUnderlyingTimestamp: crt.lastUnderlyingTimestamp,
            executor: crt.executor,
            executorFeeNatWei: crt.executorFeeNatGWei * Conversion.GWEI,
            status: _convertCollateralReservationStatus(crt.status)
        });
    }

    function redemptionRequestInfo(
        uint256 _redemptionRequestId
    )
        external view
        returns (RedemptionRequestInfo.Data memory)
    {
        uint64 requestId = SafeCast.toUint64(_redemptionRequestId);
        Redemption.Request storage request = Redemptions.getRedemptionRequest(requestId, false);
        return RedemptionRequestInfo.Data({
            redemptionRequestId: requestId,
            status: _convertRedemptionStatus(request.status),
            agentVault: request.agentVault,
            redeemer: request.redeemer,
            paymentAddress: request.redeemerUnderlyingAddressString,
            paymentReference: PaymentReference.redemption(requestId),
            valueUBA: request.underlyingValueUBA,
            feeUBA: request.underlyingFeeUBA,
            poolFeeShareBIPS: request.poolFeeShareBIPS,
            firstUnderlyingBlock: request.firstUnderlyingBlock,
            lastUnderlyingBlock: request.lastUnderlyingBlock,
            lastUnderlyingTimestamp: request.lastUnderlyingTimestamp,
            timestamp: request.timestamp,
            poolSelfClose: request.poolSelfClose,
            transferToCoreVault: request.transferToCoreVault,
            executor: request.executor,
            executorFeeNatWei: request.executorFeeNatGWei * Conversion.GWEI
        });
    }

    function _convertCollateralReservationStatus(CollateralReservation.Status _status)
        private pure
        returns (CollateralReservationInfo.Status)
    {
        if (_status == CollateralReservation.Status.ACTIVE) {
            return CollateralReservationInfo.Status.ACTIVE;
        } else if (_status == CollateralReservation.Status.SUCCESSFUL) {
            return CollateralReservationInfo.Status.SUCCESSFUL;
        } else if (_status == CollateralReservation.Status.DEFAULTED) {
            return CollateralReservationInfo.Status.DEFAULTED;
        } else {
            assert(_status == CollateralReservation.Status.EXPIRED);
            return CollateralReservationInfo.Status.EXPIRED;
        }
    }

    function _convertRedemptionStatus(Redemption.Status _status)
        private pure
        returns (RedemptionRequestInfo.Status)
    {
        if (_status == Redemption.Status.ACTIVE) {
            return RedemptionRequestInfo.Status.ACTIVE;
        } else if (_status == Redemption.Status.DEFAULTED) {
            return RedemptionRequestInfo.Status.DEFAULTED_UNCONFIRMED;
        } else if (_status == Redemption.Status.SUCCESSFUL) {
            return RedemptionRequestInfo.Status.SUCCESSFUL;
        } else if (_status == Redemption.Status.FAILED) {
            return RedemptionRequestInfo.Status.DEFAULTED_FAILED;
        } else if (_status == Redemption.Status.BLOCKED) {
            return RedemptionRequestInfo.Status.BLOCKED;
        } else {
            // the only possible status, since EMPTY is not allowed
            assert(_status == Redemption.Status.REJECTED);
            return RedemptionRequestInfo.Status.REJECTED;
        }
    }
}
