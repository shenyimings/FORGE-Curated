// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {SafePct} from "../../utils/library/SafePct.sol";
import {Transfers} from "../../utils/library/Transfers.sol";
import {AssetManagerState} from "./data/AssetManagerState.sol";
import {Agents} from "./Agents.sol";
import {Agent} from "./data/Agent.sol";
import {CollateralReservation} from "./data/CollateralReservation.sol";
import {Conversion} from "./Conversion.sol";
import {AssetManagerSettings} from "../../userInterfaces/data/AssetManagerSettings.sol";
import {Globals} from "./Globals.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";


library Minting {
    using SafePct for uint256;

    error MintingCapExceeded();
    error InvalidCrtId();

    function distributeCollateralReservationFee(
        Agent.State storage _agent,
        CollateralReservation.Data storage _crt,
        uint256 _fee
    )
        internal
    {
        if (_fee == 0) return;
        uint256 poolFeeShare = _fee.mulBips(reservationPoolFeeShare(_agent, _crt));
        _agent.collateralPool.depositNat{value: poolFeeShare}();
        Transfers.depositWNat(Globals.getWNat(), Agents.getOwnerPayAddress(_agent), _fee - poolFeeShare);
    }

    // pay executor for executor calls in WNat, otherwise burn executor fee
    function payOrBurnExecutorFee(
        CollateralReservation.Data storage _crt
    )
        internal
    {
        uint256 executorFeeNatWei = _crt.executorFeeNatGWei * Conversion.GWEI;
        if (executorFeeNatWei > 0) {
            _crt.executorFeeNatGWei = 0;
            if (msg.sender == _crt.executor) {
                Transfers.depositWNat(Globals.getWNat(), _crt.executor, executorFeeNatWei);
            } else {
                Globals.getBurnAddress().transfer(executorFeeNatWei);
            }
        }
    }

    function releaseCollateralReservation(
        CollateralReservation.Data storage _crt,
        CollateralReservation.Status _status
    )
        internal
    {
        AssetManagerState.State storage state = AssetManagerState.get();
        Agent.State storage agent = Agent.get(_crt.agentVault);
        uint64 reservationAMG = _crt.valueAMG + Conversion.convertUBAToAmg(calculatePoolFeeUBA(agent, _crt));
        agent.reservedAMG = agent.reservedAMG - reservationAMG;
        state.totalReservedCollateralAMG -= reservationAMG;
        assert(_status != CollateralReservation.Status.ACTIVE);
        _crt.status = _status;
    }

    function getCollateralReservation(
        uint256 _crtId,
        bool _requireActive
    )
        internal view
        returns (CollateralReservation.Data storage _crt)
    {
        require(_crtId > 0, InvalidCrtId());
        AssetManagerState.State storage state = AssetManagerState.get();
        _crt = state.crts[_crtId];
        require(_crt.valueAMG != 0, InvalidCrtId());
        if (_requireActive) {
            require(_crt.status == CollateralReservation.Status.ACTIVE, InvalidCrtId());
        }
    }

    function checkMintingCap(
        uint64 _increaseAMG
    )
        internal view
    {
        AssetManagerState.State storage state = AssetManagerState.get();
        AssetManagerSettings.Data storage settings = Globals.getSettings();
        uint256 mintingCapAMG = settings.mintingCapAMG;
        if (mintingCapAMG == 0) return;     // minting cap disabled
        uint256 totalMintedUBA = IERC20(settings.fAsset).totalSupply();
        uint256 totalAMG = state.totalReservedCollateralAMG + Conversion.convertUBAToAmg(totalMintedUBA);
        require(totalAMG + _increaseAMG <= mintingCapAMG, MintingCapExceeded());
    }

    function calculatePoolFeeUBA(
        Agent.State storage _agent,
        CollateralReservation.Data storage _crt
    )
        internal view
        returns (uint256)
    {
        return _calculatePoolFeeUBA(_crt.underlyingFeeUBA, reservationPoolFeeShare(_agent, _crt));
    }

    function reservationPoolFeeShare(
        Agent.State storage _agent,
        CollateralReservation.Data storage _crt
    )
        internal view
        returns (uint16)
    {
        // After an upgrade, poolFeeShareBIPS is stored in the collateral reservation.
        // To allow for backward compatibility, value 0 in this field indicates use of old _agent.poolFeeShareBIPS.
        uint16 storedPoolFeeShareBIPS = _crt.poolFeeShareBIPS;
        return storedPoolFeeShareBIPS > 0 ? storedPoolFeeShareBIPS - 1 : _agent.poolFeeShareBIPS;
    }

    function calculateCurrentPoolFeeUBA(
        Agent.State storage _agent,
        uint256 _mintingValueUBA
    )
        internal view
        returns (uint256)
    {
        uint256 mintingFeeUBA = _mintingValueUBA.mulBips(_agent.feeBIPS);
        return _calculatePoolFeeUBA(mintingFeeUBA, _agent.poolFeeShareBIPS);
    }

    function _calculatePoolFeeUBA(
        uint256 _mintingFee,
        uint16 _poolFeeShareBIPS
    )
        private view
        returns (uint256)
    {
        // round to whole number of amg's to avoid rounding errors after minting (minted amount is in amg)
        return Conversion.roundUBAToAmg(_mintingFee.mulBips(_poolFeeShareBIPS));
    }
}