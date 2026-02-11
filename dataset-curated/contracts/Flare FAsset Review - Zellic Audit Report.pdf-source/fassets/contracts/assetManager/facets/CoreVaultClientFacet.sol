// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IPayment} from "@flarenetwork/flare-periphery-contracts/flare/IFdcVerification.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {ICoreVaultClient} from "../../userInterfaces/ICoreVaultClient.sol";
import {AssetManagerBase} from "./AssetManagerBase.sol";
import {ReentrancyGuard} from "../../openzeppelin/security/ReentrancyGuard.sol";
import {Conversion} from "../library/Conversion.sol";
import {CoreVaultClient} from "../library/CoreVaultClient.sol";
import {Agent} from "../library/data/Agent.sol";
import {SafePct} from "../../utils/library/SafePct.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {AssetManagerState} from "../library/data/AssetManagerState.sol";
import {PaymentReference} from "../library/data/PaymentReference.sol";
import {AgentCollateral} from "../library/AgentCollateral.sol";
import {Redemptions} from "../library/Redemptions.sol";
import {RedemptionRequests} from "../library/RedemptionRequests.sol";
import {UnderlyingBalance} from "../library/UnderlyingBalance.sol";
import {Collateral} from "../library/data/Collateral.sol";
import {PaymentConfirmations} from "../library/data/PaymentConfirmations.sol";
import {AgentBacking} from "../library/AgentBacking.sol";
import {SafeMath64} from "../../utils/library/SafeMath64.sol";
import {TransactionAttestation} from "../library/TransactionAttestation.sol";
import {UnderlyingBlockUpdater} from "../library/UnderlyingBlockUpdater.sol";


contract CoreVaultClientFacet is AssetManagerBase, ReentrancyGuard, ICoreVaultClient {
    using SafePct for uint256;
    using SafeCast for uint256;
    using SafeCast for int256;
    using AgentCollateral for Collateral.CombinedData;
    using PaymentConfirmations for PaymentConfirmations.State;

    error CannotReturnZeroLots();
    error InvalidAgentStatus();
    error InvalidPaymentReference();
    error NoActiveReturnRequest();
    error NotEnoughFreeCollateral();
    error NotEnoughUnderlying();
    error NothingMinted();
    error PaymentNotFromCoreVault();
    error PaymentNotToAgentsAddress();
    error RequestedAmountTooSmall();
    error ReturnFromCoreVaultAlreadyRequested();
    error TooLittleMintingLeftAfterTransfer();
    error TransferAlreadyActive();
    error ZeroTransferNotAllowed();

    // core vault may not be enabled on all chains
    modifier onlyEnabled {
        CoreVaultClient.checkEnabled();
        _;
    }

    // prevent initialization of implementation contract
    constructor() {
        CoreVaultClient.State storage state = CoreVaultClient.getState();
        state.initialized = true;
    }

    /**
     * Agent can transfer their backing to core vault.
     * They then get a redemption requests which the owner pays just like any other redemption request.
     * After that, the agent's collateral is released.
     * NOTE: only agent vault owner can call
     * @param _agentVault the agent vault address
     * @param _amountUBA the amount to transfer to the core vault
     */
    function transferToCoreVault(
        address _agentVault,
        uint256 _amountUBA
    )
        external
        onlyEnabled
        notEmergencyPaused
        nonReentrant
        onlyAgentVaultOwner(_agentVault)
    {
        Agent.State storage agent = Agent.get(_agentVault);
        CoreVaultClient.State storage state = CoreVaultClient.getState();
        // for agent in full liquidation, the system cannot know if there is enough underlying for the transfer
        require(agent.status != Agent.Status.FULL_LIQUIDATION, InvalidAgentStatus());
        // forbid 0 transfer
        require(_amountUBA > 0, ZeroTransferNotAllowed());
        // agent must have enough underlying for the transfer (if the required backing < 100%, they may have less)
        require(_amountUBA.toInt256() <= agent.underlyingBalanceUBA, NotEnoughUnderlying());
        // only one transfer can be active
        require(agent.activeTransferToCoreVault == 0, TransferAlreadyActive());
        // close agent's redemption tickets
        uint64 amountAMG = Conversion.convertUBAToAmg(_amountUBA);
        (uint64 transferredAMG,) = Redemptions.closeTickets(agent, amountAMG, false);
        require(transferredAMG > 0, NothingMinted());
        // check the remaining amount
        (uint256 maximumTransferAMG,) = CoreVaultClient.maximumTransferToCoreVaultAMG(agent);
        require(transferredAMG <= maximumTransferAMG, TooLittleMintingLeftAfterTransfer());
        // create ordinary redemption request to core vault address
        string memory underlyingAddress = state.coreVaultManager.coreVaultAddress();
        // NOTE: there will be no redemption fee, so the agent needs enough free underlying for the
        // underlying transaction fee, otherwise they will go into full liquidation
        uint64 redemptionRequestId = RedemptionRequests.createRedemptionRequest(
            RedemptionRequests.AgentRedemptionData(_agentVault, transferredAMG),
            state.nativeAddress, underlyingAddress, false, payable(address(0)), 0,
            state.transferTimeExtensionSeconds, true);
        // set the active request
        agent.activeTransferToCoreVault = redemptionRequestId;
        // send event
        uint256 transferredUBA = Conversion.convertAmgToUBA(transferredAMG);
        emit TransferToCoreVaultStarted(_agentVault, redemptionRequestId, transferredUBA);
    }

    /**
     * Request that core vault transfers funds to the agent's underlying address,
     * which makes them available for redemptions. This method reserves agent's collateral.
     * This may be sent by an agent when redemptions dominate mintings, so that the agents
     * are empty but want to earn from redemptions.
     * NOTE: only agent vault owner can call
     * NOTE: there can be only one active return request (until it is confirmed or cancelled).
     * @param _agentVault the agent vault address
     * @param _lots number of lots (same lots as for minting and redemptions)
     */
    function requestReturnFromCoreVault(
        address _agentVault,
        uint256 _lots
    )
        external
        onlyEnabled
        notEmergencyPaused
        nonReentrant
        onlyAgentVaultOwner(_agentVault)
    {
        Agent.State storage agent = Agent.get(_agentVault);
        CoreVaultClient.State storage state = CoreVaultClient.getState();
        require(agent.activeReturnFromCoreVaultId == 0, ReturnFromCoreVaultAlreadyRequested());
        Collateral.CombinedData memory collateralData = AgentCollateral.combinedData(agent);
        require(_lots > 0, CannotReturnZeroLots());
        require(agent.status == Agent.Status.NORMAL, InvalidAgentStatus());
        require(collateralData.freeCollateralLotsOptionalFee(agent, false) >= _lots, NotEnoughFreeCollateral());
        // create new request id
        state.newTransferFromCoreVaultId += PaymentReference.randomizedIdSkip();
        uint64 requestId = state.newTransferFromCoreVaultId;
        agent.activeReturnFromCoreVaultId = requestId;
        // reserve collateral
        assert(agent.returnFromCoreVaultReservedAMG == 0);
        uint64 amountAMG = Conversion.convertLotsToAMG(_lots);
        agent.returnFromCoreVaultReservedAMG = amountAMG;
        agent.reservedAMG += amountAMG;
        // request
        bytes32 paymentReference = PaymentReference.returnFromCoreVault(requestId);
        uint128 amountUBA = Conversion.convertAmgToUBA(amountAMG).toUint128();
        state.coreVaultManager.requestTransferFromCoreVault(
            agent.underlyingAddressString, paymentReference, amountUBA, true);
        emit ReturnFromCoreVaultRequested(_agentVault, requestId, paymentReference, amountUBA);
    }

    /**
     * Before the return request is processed, it can be cancelled, releasing the agent's reserved collateral.
     * @param _agentVault the agent vault address
     */
    function cancelReturnFromCoreVault(
        address _agentVault
    )
        external
        onlyEnabled
        notFullyEmergencyPaused
        nonReentrant
        onlyAgentVaultOwner(_agentVault)
    {
        Agent.State storage agent = Agent.get(_agentVault);
        CoreVaultClient.State storage state = CoreVaultClient.getState();
        uint256 requestId = agent.activeReturnFromCoreVaultId;
        require(requestId != 0, NoActiveReturnRequest());
        state.coreVaultManager.cancelTransferRequestFromCoreVault(agent.underlyingAddressString);
        CoreVaultClient.deleteReturnFromCoreVaultRequest(agent);
        emit ReturnFromCoreVaultCancelled(_agentVault, requestId);
    }

    /**
     * Confirm the payment from core vault to the agent's underlying address.
     * This adds the reserved funds to the agent's backing.
     * @param _payment FDC payment proof
     * @param _agentVault the agent vault address
     */
    function confirmReturnFromCoreVault(
        IPayment.Proof calldata _payment,
        address _agentVault
    )
        external
        onlyEnabled
        notFullyEmergencyPaused
        nonReentrant
        onlyAgentVaultOwner(_agentVault)
    {
        Agent.State storage agent = Agent.get(_agentVault);
        CoreVaultClient.State storage state = CoreVaultClient.getState();
        TransactionAttestation.verifyPaymentSuccess(_payment);
        uint64 requestId = agent.activeReturnFromCoreVaultId;
        require(requestId != 0, NoActiveReturnRequest());
        require(_payment.data.responseBody.sourceAddressHash == state.coreVaultManager.coreVaultAddressHash(),
            PaymentNotFromCoreVault());
        require(_payment.data.responseBody.receivingAddressHash == agent.underlyingAddressHash,
            PaymentNotToAgentsAddress());
        require(_payment.data.responseBody.standardPaymentReference == PaymentReference.returnFromCoreVault(requestId),
            InvalidPaymentReference());
        // make sure payment isn't used again
        AssetManagerState.get().paymentConfirmations.confirmIncomingPayment(_payment);
        // we account for the option that CV pays more or less than the reserved amount:
        // - if less, only the amount received gets converted to redemption ticket
        // - if more, the extra amount becomes the agent's free underlying
        uint256 receivedAmountUBA = _payment.data.responseBody.receivedAmount.toUint256();
        uint64 receivedAmountAMG = Conversion.convertUBAToAmg(receivedAmountUBA);
        uint64 remintedAMG = SafeMath64.min64(agent.returnFromCoreVaultReservedAMG, receivedAmountAMG);
        // create redemption ticket
        AgentBacking.createNewMinting(agent, remintedAMG);
        // update underlying amount
        UnderlyingBalance.increaseBalance(agent, receivedAmountUBA);
        // update underlying block
        UnderlyingBlockUpdater.updateCurrentBlockForVerifiedPayment(_payment);
        // clear the reservation
        CoreVaultClient.deleteReturnFromCoreVaultRequest(agent);
        // send event
        uint256 remintedUBA = Conversion.convertAmgToUBA(remintedAMG);
        emit ReturnFromCoreVaultConfirmed(_agentVault, requestId, receivedAmountUBA, remintedUBA);
    }

    /**
     * Directly redeem from core vault by a user holding FAssets.
     * This is like ordinary redemption, but the redemption time is much longer (a day or more)
     * and there is no possibility of redemption.
     * @param _lots the number of lots, must be larger than `coreVaultMinimumRedeemLots` setting
     * @param _redeemerUnderlyingAddress the underlying address to which the assets will be redeemed;
     *      must have been added to the `allowedDestinations` list in the core vault manager by
     *      the governance before the redemption request.
     */
    function redeemFromCoreVault(
        uint256 _lots,
        string memory _redeemerUnderlyingAddress
    )
        external
        onlyEnabled
        notEmergencyPaused
        nonReentrant
    {
        CoreVaultClient.State storage state = CoreVaultClient.getState();
        // reduce minimumRedeemLots when the total amount on CV is lower than minimumRedeemLots,
        // otherwise redemptions won't be able to clear the CV
        uint256 availableLots = CoreVaultClient.coreVaultAmountLots();
        uint256 minimumRedeemLots = Math.min(state.minimumRedeemLots, availableLots);
        require(_lots >= minimumRedeemLots, RequestedAmountTooSmall());
        // burn the senders fassets
        uint256 redeemedUBA = Conversion.convertLotsToUBA(_lots);
        Redemptions.burnFAssets(msg.sender, redeemedUBA);
        // subtract the redemption fee
        uint256 redemptionFeeUBA = redeemedUBA.mulBips(state.redemptionFeeBIPS);
        uint128 paymentUBA = (redeemedUBA - redemptionFeeUBA).toUint128();
        // create new request id
        state.newRedemptionFromCoreVaultId += PaymentReference.randomizedIdSkip();
        bytes32 paymentReference = PaymentReference.redemptionFromCoreVault(state.newRedemptionFromCoreVaultId);
        // transfer from core vault (paymentReference may change when the request is merged)
        paymentReference = state.coreVaultManager.requestTransferFromCoreVault(
            _redeemerUnderlyingAddress, paymentReference, paymentUBA, false);
        emit CoreVaultRedemptionRequested(msg.sender, _redeemerUnderlyingAddress, paymentReference,
            redeemedUBA, redemptionFeeUBA);
    }

    function maximumTransferToCoreVault(
        address _agentVault
    )
        external view
        returns (uint256 _maximumTransferUBA, uint256 _minimumLeftAmountUBA)
    {
        Agent.State storage agent = Agent.get(_agentVault);
        (uint256 _maximumTransferAMG, uint256 _minimumLeftAmountAMG) =
             CoreVaultClient.maximumTransferToCoreVaultAMG(agent);
        _maximumTransferUBA = Conversion.convertAmgToUBA(_maximumTransferAMG.toUint64());
        _minimumLeftAmountUBA = Conversion.convertAmgToUBA(_minimumLeftAmountAMG.toUint64());
    }

    function coreVaultAvailableAmount()
        external view
        returns (uint256 _immediatelyAvailableUBA, uint256 _totalAvailableUBA)
    {
        return CoreVaultClient.coreVaultAvailableAmount();
    }
}