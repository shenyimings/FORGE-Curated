// SPDX-License-Identifier: BUSL-1.1

pragma solidity >=0.7.0;
pragma abicoder v2;

interface ILayerZeroPriceFeed {
    /**
     * @dev
     * priceRatio: (USD price of 1 unit of remote native token in unit of local native token) * PRICE_RATIO_DENOMINATOR
     */

    struct Price {
        uint128 priceRatio; // float value * 10 ^ 10, decimal awared. for aptos to evm, the basis would be (10^18 / 10^8) * 10 ^10 = 10 ^ 20.
        uint64 gasPriceInUnit; // for evm, it is in wei, for aptos, it is in octas.
        uint32 gasPerByte;
    }

    struct UpdatePrice {
        uint16 chainId;
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
        uint16 chainId;
        Price price;
        ArbitrumPriceExt extend;
    }

    function getPrice(uint16 _dstChainId) external view returns (Price memory);

    function getPriceRatioDenominator() external view returns (uint128);

    function estimateFeeByChain(
        uint16 _dstChainId,
        uint _callDataSize,
        uint _gas
    ) external view returns (uint fee, uint128 priceRatio);

    function nativeTokenPriceUSD() external view returns (uint128);
}
