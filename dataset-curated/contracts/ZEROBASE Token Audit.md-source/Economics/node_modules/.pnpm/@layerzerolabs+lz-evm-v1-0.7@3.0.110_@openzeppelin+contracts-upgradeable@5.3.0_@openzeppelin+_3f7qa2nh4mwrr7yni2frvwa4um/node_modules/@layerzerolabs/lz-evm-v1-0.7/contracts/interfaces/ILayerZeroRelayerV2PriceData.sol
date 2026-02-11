// SPDX-License-Identifier: BUSL-1.1

pragma solidity >=0.7.0;

pragma abicoder v2;

interface ILayerZeroRelayerV2PriceData {
    struct DstPrice {
        uint128 dstPriceRatio; // 10^10
        uint128 dstGasPriceInWei;
    }

    struct DstConfig {
        uint128 dstNativeAmtCap;
        uint64 baseGas;
        uint64 gasPerByte;
    }

    function dstPriceLookup(uint16 _chainId) external view returns (DstPrice memory);

    function dstConfigLookup(uint16 _chainId, uint16 _outboundProofType) external view returns (DstConfig memory);
}
