// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6 <0.9;
pragma abicoder v2;

import {IWNat} from "../../flareSmartContracts/interfaces/IWNat.sol";


interface IISettingsManagement {
    function updateSystemContracts(address _controller, IWNat _wNat)
        external;

    function setAgentOwnerRegistry(address _value)
        external;

    function setAgentVaultFactory(address _value)
        external;

    function setCollateralPoolFactory(address _value)
        external;

    function setCollateralPoolTokenFactory(address _value)
        external;

    function setPriceReader(address _value)
        external;

    function setFdcVerification(address _value)
        external;

    function setCleanerContract(address _value)
        external;

    function setCleanupBlockNumberManager(address _value)
        external;

    function upgradeFAssetImplementation(address _value, bytes memory callData)
        external;

    function setTimeForPayment(uint256 _underlyingBlocks, uint256 _underlyingSeconds)
        external;

    function setPaymentChallengeReward(uint256 _rewardUSD5, uint256 _rewardBIPS)
        external;

    function setMinUpdateRepeatTimeSeconds(uint256 _value)
        external;

    function setLotSizeAmg(uint256 _value)
        external;

    function setMaxTrustedPriceAgeSeconds(uint256 _value)
        external;

    function setCollateralReservationFeeBips(uint256 _value)
        external;

    function setRedemptionFeeBips(uint256 _value)
        external;

    function setRedemptionDefaultFactorVaultCollateralBIPS(uint256 _value)
        external;

    function setConfirmationByOthersAfterSeconds(uint256 _value)
        external;

    function setConfirmationByOthersRewardUSD5(uint256 _value)
        external;

    function setMaxRedeemedTickets(uint256 _value)
        external;

    function setWithdrawalOrDestroyWaitMinSeconds(uint256 _value)
        external;

    function setAttestationWindowSeconds(uint256 _value)
        external;

    function setAverageBlockTimeMS(uint256 _value)
        external;

    function setMintingPoolHoldingsRequiredBIPS(uint256 _value)
        external;

    function setMintingCapAmg(uint256 _value)
        external;

    function setVaultCollateralBuyForFlareFactorBIPS(uint256 _value)
        external;

    function setAgentExitAvailableTimelockSeconds(uint256 _value)
        external;

    function setAgentFeeChangeTimelockSeconds(uint256 _value)
        external;

    function setAgentMintingCRChangeTimelockSeconds(uint256 _value)
        external;

    function setPoolExitCRChangeTimelockSeconds(uint256 _value)
        external;

    function setAgentTimelockedOperationWindowSeconds(uint256 _value)
        external;

    function setCollateralPoolTokenTimelockSeconds(uint256 _value)
        external;

    function setLiquidationStepSeconds(uint256 _stepSeconds)
        external;

    function setLiquidationPaymentFactors(
        uint256[] memory _liquidationFactors,
        uint256[] memory _vaultCollateralFactors
    ) external;

    function setMaxEmergencyPauseDurationSeconds(uint256 _value)
        external;

    function setEmergencyPauseDurationResetAfterSeconds(uint256 _value)
        external;
}
