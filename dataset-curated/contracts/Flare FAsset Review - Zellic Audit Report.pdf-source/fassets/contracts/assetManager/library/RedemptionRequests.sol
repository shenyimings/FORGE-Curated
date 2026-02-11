// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {SafePct} from "../../utils/library/SafePct.sol";
import {AssetManagerState} from "./data/AssetManagerState.sol";
import {RedemptionTimeExtension} from "./data/RedemptionTimeExtension.sol";
import {IAssetManagerEvents} from "../../userInterfaces/IAssetManagerEvents.sol";
import {Conversion} from "./Conversion.sol";
import {Redemption} from "./data/Redemption.sol";
import {Agent} from "./data/Agent.sol";
import {Globals} from "./Globals.sol";
import {AgentBacking} from "./AgentBacking.sol";
import {AssetManagerSettings} from "../../userInterfaces/data/AssetManagerSettings.sol";
import {PaymentReference} from "./data/PaymentReference.sol";


library RedemptionRequests {
    using SafePct for uint256;
    using SafeCast for uint256;

    error CannotRedeemToAgentsAddress();
    error UnderlyingAddressTooLong();
    error ExecutorFeeWithoutExecutor();

    struct AgentRedemptionData {
        address agentVault;
        uint64 valueAMG;
    }

    struct AgentRedemptionList {
        AgentRedemptionData[] items;
        uint256 length;
    }

    function createRedemptionRequest(
        AgentRedemptionData memory _data,
        address _redeemer,
        string memory _redeemerUnderlyingAddressString,
        bool _poolSelfClose,
        address payable _executor,
        uint64 _executorFeeNatGWei,
        uint64 _additionalPaymentTime,
        bool _transferToCoreVault
    )
        internal
        returns (uint64 _requestId)
    {
        require(_executorFeeNatGWei == 0 || _executor != address(0), ExecutorFeeWithoutExecutor());
        AssetManagerState.State storage state = AssetManagerState.get();
        Agent.State storage agent = Agent.get(_data.agentVault);
        // validate redemption address
        require(bytes(_redeemerUnderlyingAddressString).length < 128, UnderlyingAddressTooLong());
        bytes32 underlyingAddressHash = keccak256(bytes(_redeemerUnderlyingAddressString));
        // both addresses must be normalized (agent's address is checked at vault creation,
        // and if redeemer address isn't normalized, the agent can trigger rejectInvalidRedemption),
        // so this comparison quarantees the redemption is not to the agent's address
        require(underlyingAddressHash != agent.underlyingAddressHash,
            CannotRedeemToAgentsAddress());
        // create request
        uint128 redeemedValueUBA = Conversion.convertAmgToUBA(_data.valueAMG).toUint128();
        _requestId = _newRequestId(_poolSelfClose);
        // create in-memory request and then put it to storage to not go out-of-stack
        Redemption.Request memory request;
        request.redeemerUnderlyingAddressHash = underlyingAddressHash;
        request.underlyingValueUBA = redeemedValueUBA;
        request.firstUnderlyingBlock = state.currentUnderlyingBlock;
        (request.lastUnderlyingBlock, request.lastUnderlyingTimestamp) =
            _lastPaymentBlock(_data.agentVault, _additionalPaymentTime);
        request.timestamp = block.timestamp.toUint64();
        request.underlyingFeeUBA = _transferToCoreVault ?
            0 : uint256(redeemedValueUBA).mulBips(Globals.getSettings().redemptionFeeBIPS).toUint128();
        request.redeemer = _redeemer;
        request.agentVault = _data.agentVault;
        request.valueAMG = _data.valueAMG;
        request.status = Redemption.Status.ACTIVE;
        request.poolSelfClose = _poolSelfClose;
        request.executor = _executor;
        request.executorFeeNatGWei = _executorFeeNatGWei;
        request.redeemerUnderlyingAddressString = _redeemerUnderlyingAddressString;
        request.transferToCoreVault = _transferToCoreVault;
        request.poolFeeShareBIPS = agent.redemptionPoolFeeShareBIPS;
        state.redemptionRequests[_requestId] = request;
        // decrease mintedAMG and mark it to redeemingAMG
        // do not add it to freeBalance yet (only after failed redemption payment)
        AgentBacking.startRedeemingAssets(agent, _data.valueAMG, _poolSelfClose);
        // emit event to remind agent to pay
        _emitRedemptionRequestedEvent(request, _requestId, _redeemerUnderlyingAddressString);
    }

    function _emitRedemptionRequestedEvent(
        Redemption.Request memory _request,
        uint64 _requestId,
        string memory _redeemerUnderlyingAddressString
    )
        private
    {
        emit IAssetManagerEvents.RedemptionRequested(
            _request.agentVault,
            _request.redeemer,
            _requestId,
            _redeemerUnderlyingAddressString,
            _request.underlyingValueUBA,
            _request.underlyingFeeUBA,
            _request.firstUnderlyingBlock,
            _request.lastUnderlyingBlock,
            _request.lastUnderlyingTimestamp,
            PaymentReference.redemption(_requestId),
            _request.executor,
            _request.executorFeeNatGWei * Conversion.GWEI);
    }

    function _newRequestId(bool _poolSelfClose)
        private
        returns (uint64)
    {
        AssetManagerState.State storage state = AssetManagerState.get();
        uint64 nextRequestId = state.newRedemptionRequestId + PaymentReference.randomizedIdSkip();
        // the requestId will indicate in the lowest bit whether it is a pool self close redemption
        // (+1 is added so that the request id still increases after clearing lowest bit)
        uint64 requestId = ((nextRequestId + 1) & ~uint64(1)) | (_poolSelfClose ? 1 : 0);
        state.newRedemptionRequestId = requestId;
        return requestId;
    }

    function _lastPaymentBlock(address _agentVault, uint64 _additionalPaymentTime)
        private
        returns (uint64 _lastUnderlyingBlock, uint64 _lastUnderlyingTimestamp)
    {
        AssetManagerState.State storage state = AssetManagerState.get();
        AssetManagerSettings.Data storage settings = Globals.getSettings();
        // timeshift amortizes for the time that passed from the last underlying block update;
        // it also adds redemption time extension when there are many redemption requests in short time
        uint64 timeshift = block.timestamp.toUint64() - state.currentUnderlyingBlockUpdatedAt
            + RedemptionTimeExtension.extendTimeForRedemption(_agentVault)
            + _additionalPaymentTime;
        uint64 blockshift = (uint256(timeshift) * 1000 / settings.averageBlockTimeMS).toUint64();
        _lastUnderlyingBlock =
            state.currentUnderlyingBlock + blockshift + settings.underlyingBlocksForPayment;
        _lastUnderlyingTimestamp =
            state.currentUnderlyingBlockTimestamp + timeshift + settings.underlyingSecondsForPayment;
    }
}