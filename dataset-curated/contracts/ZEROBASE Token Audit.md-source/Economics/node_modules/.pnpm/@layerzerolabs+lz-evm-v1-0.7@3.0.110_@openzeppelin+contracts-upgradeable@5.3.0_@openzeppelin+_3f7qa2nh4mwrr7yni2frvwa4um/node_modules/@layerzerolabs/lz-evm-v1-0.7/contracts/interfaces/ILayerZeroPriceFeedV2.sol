// SPDX-License-Identifier: BUSL-1.1

pragma solidity >=0.7.0;
pragma abicoder v2;

// copy of "@layerzerolabs/lz-evm-messagelib-v2/contracts/interfaces/ILayerZeroPriceFeed.sol"
interface ILayerZeroPriceFeedV2 {
    /**
     * @dev
     * priceRatio: (USD price of 1 unit of remote native token in unit of local native token) * PRICE_RATIO_DENOMINATOR
     */

    struct Price {
        uint128 priceRatio; // float value * 10 ^ 20, decimal awared. for aptos to evm, the basis would be (10^18 / 10^8) * 10 ^20 = 10 ^ 30.
        uint64 gasPriceInUnit; // for evm, it is in wei, for aptos, it is in octas.
        uint32 gasPerByte;
    }

    struct UpdatePrice {
        uint32 eid;
        Price price;
    }

    /**
     * @dev
     *    ArbGasInfo.go:GetPricesInArbGas
     *
     */
    struct ArbitrumPriceExt {
        uint64 gasPerL2Tx; // L2 overhead
        uint32 gasPerL1CallDataByte;
    }

    struct UpdatePriceExt {
        uint32 eid;
        Price price;
        ArbitrumPriceExt extend;
    }

    function getPrice(uint32 _dstEid) external view returns (Price memory);

    function getPriceRatioDenominator() external view returns (uint128);

    function estimateFeeByEid(
        uint32 _dstEid,
        uint _callDataSize,
        uint _gas
    ) external view returns (uint fee, uint128 priceRatio, uint128 priceRatioDenominator, uint128 nativePriceUSD);
}
