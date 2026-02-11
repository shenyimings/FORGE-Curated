// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IICoreVaultManager} from "../../coreVaultManager/interfaces/IICoreVaultManager.sol";
import {MathUtils} from "../../utils/library/MathUtils.sol";
import {SafePct} from "../../utils/library/SafePct.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {ICoreVaultClient} from "../../userInterfaces/ICoreVaultClient.sol";
import {AgentCollateral} from "./AgentCollateral.sol";
import {Redemptions} from "./Redemptions.sol";
import {Agent} from "./data/Agent.sol";
import {Collateral} from "./data/Collateral.sol";
import {IPayment} from "@flarenetwork/flare-periphery-contracts/flare/IFdcVerification.sol";
import {Redemption} from "./data/Redemption.sol";
import {AssetManagerSettings} from "../../userInterfaces/data/AssetManagerSettings.sol";
import {Globals} from "./Globals.sol";
import {Conversion} from "./Conversion.sol";
import {ICoreVaultClient} from "../../userInterfaces/ICoreVaultClient.sol";


library CoreVaultClient {
    using SafePct for uint256;
    using SafeCast for int256;
    using Agent for Agent.State;

    error CoreVaultNotEnabled();

    struct State {
        // settings
        IICoreVaultManager coreVaultManager;
        uint64 transferTimeExtensionSeconds;
        address payable nativeAddress;
        uint16 __transferFeeBIPS; // only storage placeholder
        uint16 redemptionFeeBIPS;
        uint16 minimumAmountLeftBIPS;
        uint64 minimumRedeemLots;

        // state
        bool initialized;
        uint64 newTransferFromCoreVaultId;
        uint64 newRedemptionFromCoreVaultId;
    }

    // core vault may not be enabled on all chains
    modifier onlyEnabled {
        checkEnabled();
        _;
    }

    // only called by RedemptionConfirmations.confirmRedemptionPayment, so all checks are done there
    function confirmTransferToCoreVault(
        IPayment.Proof calldata _payment,
        Agent.State storage _agent,
        uint256 _redemptionRequestId
    )
        internal
        onlyEnabled
    {
        State storage state = getState();
        state.coreVaultManager.confirmPayment(_payment);
        uint256 receivedAmount = _payment.data.responseBody.receivedAmount.toUint256();
        emit ICoreVaultClient.TransferToCoreVaultSuccessful(_agent.vaultAddress(), _redemptionRequestId,
            receivedAmount);
    }

    // only called by RedemptionDefaults, RedemptionConfirmations etc., so all checks are done there
    function cancelTransferToCoreVault(
        Agent.State storage _agent,
        Redemption.Request storage _request,
        uint256 _redemptionRequestId
    )
        internal
        onlyEnabled
    {
        // core vault transfer default - re-create tickets
        Redemptions.releaseTransferToCoreVault(_redemptionRequestId, _request);
        Redemptions.reCreateRedemptionTicket(_agent, _request);
        emit ICoreVaultClient.TransferToCoreVaultDefaulted(_agent.vaultAddress(), _redemptionRequestId,
            _request.underlyingValueUBA);
    }

    function deleteReturnFromCoreVaultRequest(
        Agent.State storage _agent
    )
        internal
    {
        assert(_agent.activeReturnFromCoreVaultId != 0 && _agent.returnFromCoreVaultReservedAMG != 0);
        _agent.reservedAMG -= _agent.returnFromCoreVaultReservedAMG;
        _agent.activeReturnFromCoreVaultId = 0;
        _agent.returnFromCoreVaultReservedAMG = 0;
    }

    function maximumTransferToCoreVaultAMG(
        Agent.State storage _agent
    )
        internal view
        returns (uint256 _maximumTransferAMG, uint256 _minimumLeftAmountAMG)
    {
        _minimumLeftAmountAMG = _minimumRemainingAfterTransferAMG(_agent);
        _maximumTransferAMG = MathUtils.subOrZero(_agent.mintedAMG, _minimumLeftAmountAMG);
    }

    function coreVaultAvailableAmount()
        internal view
        returns (uint256 _immediatelyAvailableUBA, uint256 _totalAvailableUBA)
    {
        State storage state = getState();
        uint256 availableFunds = state.coreVaultManager.availableFunds();
        uint256 escrowedFunds = state.coreVaultManager.escrowedFunds();
        // account for fee for one more request, because this much must remain available on any transfer
        uint256 requestedAmountWithFee =
            state.coreVaultManager.totalRequestAmountWithFee() + coreVaultUnderlyingPaymentFee();
        _immediatelyAvailableUBA = MathUtils.subOrZero(availableFunds, requestedAmountWithFee);
        _totalAvailableUBA = MathUtils.subOrZero(availableFunds + escrowedFunds, requestedAmountWithFee);
    }

    function coreVaultAmountLots()
        internal view
        returns (uint256)
    {
        AssetManagerSettings.Data storage settings = Globals.getSettings();
        (, uint256 totalAmountUBA) = coreVaultAvailableAmount();
        return Conversion.convertUBAToAmg(totalAmountUBA) / settings.lotSizeAMG;
    }

    function coreVaultUnderlyingPaymentFee()
        internal view
        returns (uint256)
    {
        State storage state = getState();
        (,,, uint256 fee) = state.coreVaultManager.getSettings();
        return fee;
    }

    function checkEnabled()
        internal view
    {
        State storage state = getState();
        require(address(state.coreVaultManager) != address(0), CoreVaultNotEnabled());
    }

    function coreVaultUnderlyingAddressHash()
        internal view
        returns (bytes32)
    {
        State storage state = getState();
        if (address(state.coreVaultManager) == address(0)) {
            return bytes32(0);
        }
        return state.coreVaultManager.coreVaultAddressHash();
    }

    function _minimumRemainingAfterTransferAMG(
        Agent.State storage _agent
    )
        private view
        returns (uint256)
    {
        Collateral.CombinedData memory cd = AgentCollateral.combinedData(_agent);
        uint256 resultWRTVault = _minimumRemainingAfterTransferForCollateralAMG(_agent, cd.agentCollateral);
        uint256 resultWRTPool = _minimumRemainingAfterTransferForCollateralAMG(_agent, cd.poolCollateral);
        uint256 resultWRTAgentPT = _minimumRemainingAfterTransferForCollateralAMG(_agent, cd.agentPoolTokens);
        return Math.min(resultWRTVault, Math.min(resultWRTPool, resultWRTAgentPT));
    }

    function _minimumRemainingAfterTransferForCollateralAMG(
        Agent.State storage _agent,
        Collateral.Data memory _data
    )
        private view
        returns (uint256)
    {
        State storage state = getState();
        (, uint256 systemMinCrBIPS) = AgentCollateral.mintingMinCollateralRatio(_agent, _data.kind);
        uint256 collateralEquivAMG = Conversion.convertTokenWeiToAMG(_data.fullCollateral, _data.amgToTokenWeiPrice);
        uint256 maxSupportedAMG = collateralEquivAMG.mulDiv(SafePct.MAX_BIPS, systemMinCrBIPS);
        return maxSupportedAMG.mulBips(state.minimumAmountLeftBIPS);
    }

    bytes32 internal constant STATE_POSITION = keccak256("fasset.CoreVault.State");

    function getState()
        internal pure
        returns (State storage _state)
    {
        bytes32 position = STATE_POSITION;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            _state.slot := position
        }
    }
}