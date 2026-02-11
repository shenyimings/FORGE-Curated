// SPDX-License-Identifier: ISC
pragma solidity 0.8.25;

interface ILiquidatable {
    /**
     * @notice Liquidates the collateral from the provided LOC.
     * @dev If _liquidatorToUse is populated, liquidation will occur through the ILiquidator interface callback. If not,
     * liquidation will be attempted by implementing contract transferring the required amount of credited tokens from
     * `msg.sender`.
     *
     * @param _locId The ID of the unhealthy LOC to liquidate.
     * @param _iLiquidatorToUse (optional) The ILiquidator to use for liquidation if not liquidating directly from the
     * assets of `msg.sender`.
     * @param _oraclePriceUpdate (optional) The oracle price update to be used for this liquidation.
     * @param _creatorAuthorization (optional) If not called by the creator, and the LOC is healthy, the signed creator
     * authorization necessary to convert the LOC.
     * @param _liquidatorParams (optional) Parameters to be parsed and used by the ILiquidator implementation contract.
     */
    function convertLOC(
        uint96 _locId,
        address _iLiquidatorToUse,
        bytes calldata _oraclePriceUpdate,
        bytes calldata _creatorAuthorization,
        bytes calldata _liquidatorParams
    ) external payable;
}
