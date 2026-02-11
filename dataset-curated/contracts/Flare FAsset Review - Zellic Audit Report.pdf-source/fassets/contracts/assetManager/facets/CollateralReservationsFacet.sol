// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {AssetManagerBase} from "./AssetManagerBase.sol";
import {ReentrancyGuard} from "../../openzeppelin/security/ReentrancyGuard.sol";
import {SafePct} from "../../utils/library/SafePct.sol";
import {Transfers} from "../../utils/library/Transfers.sol";
import {AssetManagerState} from "../library/data/AssetManagerState.sol";
import {IAssetManagerEvents} from "../../userInterfaces/IAssetManagerEvents.sol";
import {Conversion} from "../library/Conversion.sol";
import {Agents} from "../library/Agents.sol";
import {Minting} from "../library/Minting.sol";
import {AgentCollateral} from "../library/AgentCollateral.sol";
import {Collateral} from "../library/data/Collateral.sol";
import {Agent} from "../library/data/Agent.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {CollateralReservation} from "../library/data/CollateralReservation.sol";
import {PaymentReference} from "../library/data/PaymentReference.sol";
import {Globals} from "../library/Globals.sol";
import {AssetManagerSettings} from "../../userInterfaces/data/AssetManagerSettings.sol";

contract CollateralReservationsFacet is AssetManagerBase, ReentrancyGuard {
    using SafePct for uint256;
    using SafeCast for uint256;
    using AgentCollateral for Collateral.CombinedData;
    using Agent for Agent.State;
    using EnumerableSet for EnumerableSet.AddressSet;

    error InappropriateFeeAmount();
    error AgentsFeeTooHigh();
    error NotEnoughFreeCollateral();
    error InvalidAgentStatus();
    error CannotMintZeroLots();
    error AgentNotInMintQueue();
    error MintingPaused();

    /**
     * Before paying underlying assets for minting, minter has to reserve collateral and
     * pay collateral reservation fee. Collateral is reserved at ratio of agent's agentMinCollateralRatio
     * to requested lots NAT market price.
     * The minter receives instructions for underlying payment
     * (value, fee and payment reference) in event CollateralReserved.
     * Then the minter has to pay `value + fee` on the underlying chain.
     * If the minter pays the underlying amount, minter obtains f-assets.
     * The collateral reservation fee is split between the agent and the collateral pool.
     * NOTE: the owner of the agent vault must be in the AgentOwnerRegistry.
     * @param _agentVault agent vault address
     * @param _lots the number of lots for which to reserve collateral
     * @param _maxMintingFeeBIPS maximum minting fee (BIPS) that can be charged by the agent - best is just to
     *      copy current agent's published fee; used to prevent agent from front-running reservation request
     *      and increasing fee (that would mean that the minter would have to pay raised fee or forfeit
     *      collateral reservation fee)
     * @param _executor the account that is allowed to execute minting (besides minter and agent)
     */
    function reserveCollateral(
        address _agentVault,
        uint256 _lots,
        uint256 _maxMintingFeeBIPS,
        address payable _executor
    )
        external payable
        onlyAttached
        notEmergencyPaused
        nonReentrant
        returns (uint256 _collateralReservationId)
    {
        Agent.State storage agent = Agent.get(_agentVault);
        Agents.requireWhitelistedAgentVaultOwner(agent);
        Collateral.CombinedData memory collateralData = AgentCollateral.combinedData(agent);
        AssetManagerState.State storage state = AssetManagerState.get();
        require(state.mintingPausedAt == 0, MintingPaused());
        require(agent.availableAgentsPos != 0 || agent.alwaysAllowedMinters.contains(msg.sender),
            AgentNotInMintQueue());
        require(_lots > 0, CannotMintZeroLots());
        require(agent.status == Agent.Status.NORMAL, InvalidAgentStatus());
        require(collateralData.freeCollateralLots(agent) >= _lots, NotEnoughFreeCollateral());
        require(_maxMintingFeeBIPS >= agent.feeBIPS, AgentsFeeTooHigh());
        uint64 valueAMG = Conversion.convertLotsToAMG(_lots);
        _reserveCollateral(agent, valueAMG + _currentPoolFeeAMG(agent, valueAMG));
        // - only charge reservation fee for public minting, not for alwaysAllowedMinters on non-public agent
        // - poolCollateral is WNat, so we can use its price for calculation of CR fee
        uint256 reservationFee = agent.availableAgentsPos != 0
            ? _reservationFee(collateralData.poolCollateral.amgToTokenWeiPrice, valueAMG)
            : 0;
        require(msg.value >= reservationFee, InappropriateFeeAmount());
        // create new crt id - pre-increment, so that id can never be 0
        state.newCrtId += PaymentReference.randomizedIdSkip();
        uint256 crtId = state.newCrtId;
        // create in-memory cr and then put it to storage to not go out-of-stack
        CollateralReservation.Data memory cr;
        cr.valueAMG = valueAMG;
        cr.underlyingFeeUBA = Conversion.convertAmgToUBA(valueAMG).mulBips(agent.feeBIPS).toUint128();
        cr.reservationFeeNatWei = reservationFee.toUint128();
        // 1 is added for backward compatibility where 0 means "value not stored" - it is subtracted when used
        cr.poolFeeShareBIPS = agent.poolFeeShareBIPS + 1;
        cr.agentVault = _agentVault;
        cr.minter = msg.sender;
        if (_executor != address(0)) {
            cr.executor = _executor;
            cr.executorFeeNatGWei = ((msg.value - reservationFee) / Conversion.GWEI).toUint64();
        }
        (uint64 lastUnderlyingBlock, uint64 lastUnderlyingTimestamp) = _lastPaymentBlock();
        cr.firstUnderlyingBlock = state.currentUnderlyingBlock;
        cr.lastUnderlyingBlock = lastUnderlyingBlock;
        cr.lastUnderlyingTimestamp = lastUnderlyingTimestamp;
        cr.status = CollateralReservation.Status.ACTIVE;
        // store cr
        state.crts[crtId] = cr;
        // emit event
        _emitCollateralReservationEvent(agent, cr, crtId);
        // if executor is not set, we return the change to the minter
        if (cr.executor == address(0) && msg.value > reservationFee) {
            Transfers.transferNAT(payable(msg.sender), msg.value - reservationFee);
        }
        return crtId;
    }

    /**
     * Return the collateral reservation fee amount that has to be passed to the `reserveCollateral` method.
     * NOTE: the amount paid may be larger than the required amount, but the difference is not returned.
     * It is advised that the minter pays the exact amount, but when the amount is so small that the revert
     * would cost more than the lost difference, the minter may want to send a slightly larger amount to compensate
     * for the possibility of a FTSO price change between obtaining this value and calling `reserveCollateral`.
     * @param _lots the number of lots for which to reserve collateral
     * @return _reservationFeeNATWei the amount of reservation fee in NAT wei
     */
    function collateralReservationFee(
        uint256 _lots
    )
        external view
        returns (uint256 _reservationFeeNATWei)
    {
        AssetManagerState.State storage state = AssetManagerState.get();
        uint256 amgToTokenWeiPrice = Conversion.currentAmgPriceInTokenWei(state.poolCollateralIndex);
        return _reservationFee(amgToTokenWeiPrice, Conversion.convertLotsToAMG(_lots));
    }

    function _reserveCollateral(
        Agent.State storage _agent,
        uint64 _reservationAMG
    )
        private
    {
        AssetManagerState.State storage state = AssetManagerState.get();
        Minting.checkMintingCap(_reservationAMG);
        _agent.reservedAMG += _reservationAMG;
        state.totalReservedCollateralAMG += _reservationAMG;
    }

    function _emitCollateralReservationEvent(
        Agent.State storage _agent,
        CollateralReservation.Data memory _cr,
        uint256 _crtId
    )
        private
    {
        emit IAssetManagerEvents.CollateralReserved(
            _agent.vaultAddress(),
            _cr.minter,
            _crtId,
            Conversion.convertAmgToUBA(_cr.valueAMG),
            _cr.underlyingFeeUBA,
            _cr.firstUnderlyingBlock,
            _cr.lastUnderlyingBlock,
            _cr.lastUnderlyingTimestamp,
            _agent.underlyingAddressString,
            PaymentReference.minting(_crtId),
            _cr.executor,
            _cr.executorFeeNatGWei * Conversion.GWEI);
    }

    function _currentPoolFeeAMG(
        Agent.State storage _agent,
        uint64 _valueAMG
    )
        private view
        returns (uint64)
    {
        uint256 underlyingValueUBA = Conversion.convertAmgToUBA(_valueAMG);
        uint256 poolFeeUBA = Minting.calculateCurrentPoolFeeUBA(_agent, underlyingValueUBA);
        return Conversion.convertUBAToAmg(poolFeeUBA);
    }

    function _lastPaymentBlock()
        private view
        returns (uint64 _lastUnderlyingBlock, uint64 _lastUnderlyingTimestamp)
    {
        AssetManagerState.State storage state = AssetManagerState.get();
        AssetManagerSettings.Data storage settings = Globals.getSettings();
        // timeshift amortizes for the time that passed from the last underlying block update
        uint64 timeshift = block.timestamp.toUint64() - state.currentUnderlyingBlockUpdatedAt;
        uint64 blockshift = (uint256(timeshift) * 1000 / settings.averageBlockTimeMS).toUint64();
        _lastUnderlyingBlock =
            state.currentUnderlyingBlock + blockshift + settings.underlyingBlocksForPayment;
        _lastUnderlyingTimestamp =
            state.currentUnderlyingBlockTimestamp + timeshift + settings.underlyingSecondsForPayment;
    }

    function _reservationFee(
        uint256 amgToTokenWeiPrice,
        uint64 _valueAMG
    )
        private view
        returns (uint256)
    {
        uint256 valueNATWei = Conversion.convertAmgToTokenWei(_valueAMG, amgToTokenWeiPrice);
        return valueNATWei.mulBips(Globals.getSettings().collateralReservationFeeBIPS);
    }
}