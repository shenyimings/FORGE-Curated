// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "../interfaces/ILayerZeroPriceFeedV2.sol";

// copy of "@layerzerolabs/lz-evm-messagelib-v2/contracts/interfaces/ILayerZeroPriceFeed.sol"
// PriceFeed is updated based on v1 eids
// v2 eids will fall to the convention of v1 eid + 30,000
contract PriceFeedV2Mock is ILayerZeroPriceFeedV2, OwnableUpgradeable {
    uint128 internal PRICE_RATIO_DENOMINATOR;

    // sets pricing
    mapping(address => bool) public priceUpdater;

    mapping(uint32 => Price) public defaultModelPrice;
    ArbitrumPriceExt public arbitrumPriceExt;

    uint128 public nativeTokenPriceUSD; // uses PRICE_RATIO_DENOMINATOR

    // upgrade: arbitrum compression - percentage of callDataSize after brotli compression
    uint128 public ARBITRUM_COMPRESSION_PERCENT;

    // ============================ Constructor ===================================

    function initialize(address _priceUpdater) public initializer {
        __Ownable_init();
        priceUpdater[_priceUpdater] = true;
        PRICE_RATIO_DENOMINATOR = 1e20;
        ARBITRUM_COMPRESSION_PERCENT = 47;
    }

    // ============================ Modifier ======================================

    // owner is always approved
    modifier onlyPriceUpdater() {
        if (owner() != msg.sender) {
            require(priceUpdater[msg.sender], "PriceFeed: not price updater");
        }
        _;
    }

    // ============================ OnlyOwner =====================================

    function setPriceUpdater(address _addr, bool _active) external onlyOwner {
        priceUpdater[_addr] = _active;
    }

    function setPriceRatioDenominator(uint128 _denominator) external onlyOwner {
        PRICE_RATIO_DENOMINATOR = _denominator;
    }

    function setArbitrumCompressionPercent(uint128 _compressionPercent) external onlyOwner {
        ARBITRUM_COMPRESSION_PERCENT = _compressionPercent;
    }

    // ============================ OnlyPriceUpdater =====================================

    function setPrice(UpdatePrice[] calldata _price) external onlyPriceUpdater {
        for (uint i = 0; i < _price.length; i++) {
            UpdatePrice calldata _update = _price[i];
            _setPrice(_update.eid, _update.price);
        }
    }

    function setPriceForArbitrum(UpdatePriceExt calldata _update) external onlyPriceUpdater {
        _setPrice(_update.eid, _update.price);

        uint64 gasPerL2Tx = _update.extend.gasPerL2Tx;
        uint32 gasPerL1CalldataByte = _update.extend.gasPerL1CallDataByte;

        arbitrumPriceExt.gasPerL2Tx = gasPerL2Tx;
        arbitrumPriceExt.gasPerL1CallDataByte = gasPerL1CalldataByte;
    }

    function setNativeTokenPriceUSD(uint128 _nativeTokenPriceUSD) external onlyPriceUpdater {
        nativeTokenPriceUSD = _nativeTokenPriceUSD;
    }

    // ============================ Internal ==========================================
    function _setPrice(uint32 _dstEid, Price memory _price) internal {
        uint128 priceRatio = _price.priceRatio;
        uint64 gasPriceInUnit = _price.gasPriceInUnit;
        uint32 gasPerByte = _price.gasPerByte;
        defaultModelPrice[_dstEid] = Price(priceRatio, gasPriceInUnit, gasPerByte);
    }

    function _getL1LookupId(uint32 _l2Eid) internal pure returns (uint32) {
        uint32 l2Eid = _l2Eid % 30_000;
        if (l2Eid == 111) {
            return 101;
        } else if (l2Eid == 10132) {
            return 10121; // ethereum-goerli
        } else if (l2Eid == 20132) {
            return 20121; // ethereum-goerli
        } else {
            revert("PriceFeed: unknown l2 chain id");
        }
    }

    // ============================ View ==========================================

    function getPrice(uint32 _dstEid) external view override returns (Price memory price) {
        price = defaultModelPrice[_dstEid];
    }

    function getPriceRatioDenominator() external view override returns (uint128) {
        return PRICE_RATIO_DENOMINATOR;
    }

    function estimateFeeByEid(
        uint32 _dstEid,
        uint _callDataSize,
        uint _gas
    )
        external
        view
        override
        returns (uint fee, uint128 priceRatio, uint128 priceRatioDenominator, uint128 nativePriceUSD)
    {
        uint32 dstEid = _dstEid % 30_000;
        if (dstEid == 110 || dstEid == 10143 || dstEid == 20143) {
            (fee, priceRatio) = _estimateFeeWithArbitrumModel(dstEid, _callDataSize, _gas);
        } else if (dstEid == 111 || dstEid == 10132 || dstEid == 20132) {
            (fee, priceRatio) = _estimateFeeWithOptimismModel(dstEid, _callDataSize, _gas);
        } else {
            (fee, priceRatio) = _estimateFeeWithDefaultModel(dstEid, _callDataSize, _gas);
        }
        priceRatioDenominator = PRICE_RATIO_DENOMINATOR;
        nativePriceUSD = nativeTokenPriceUSD;
    }

    function _estimateFeeWithDefaultModel(
        uint32 _dstEid,
        uint _callDataSize,
        uint _gas
    ) internal view returns (uint fee, uint128 priceRatio) {
        Price storage remotePrice = defaultModelPrice[_dstEid];

        // assuming the _gas includes (1) the 21,000 overhead and (2) not the calldata gas
        uint gasForCallData = _callDataSize * remotePrice.gasPerByte;
        uint remoteFee = (gasForCallData + _gas) * remotePrice.gasPriceInUnit;
        return ((remoteFee * remotePrice.priceRatio) / PRICE_RATIO_DENOMINATOR, remotePrice.priceRatio);
    }

    function _estimateFeeWithOptimismModel(
        uint32 _dstEid,
        uint _callDataSize,
        uint _gas
    ) internal view returns (uint fee, uint128 priceRatio) {
        uint32 ethereumId = _getL1LookupId(_dstEid);

        // L1 fee
        Price storage ethereumPrice = defaultModelPrice[ethereumId];
        uint gasForL1CallData = (_callDataSize * ethereumPrice.gasPerByte) + 3188; // 2100 + 68 * 16
        uint l1Fee = gasForL1CallData * ethereumPrice.gasPriceInUnit;

        // L2 fee
        Price storage optimismPrice = defaultModelPrice[_dstEid];
        uint gasForL2CallData = _callDataSize * optimismPrice.gasPerByte;
        uint l2Fee = (gasForL2CallData + _gas) * optimismPrice.gasPriceInUnit;

        uint l1FeeInSrcPrice = (l1Fee * ethereumPrice.priceRatio) / PRICE_RATIO_DENOMINATOR;
        uint l2FeeInSrcPrice = (l2Fee * optimismPrice.priceRatio) / PRICE_RATIO_DENOMINATOR;
        uint gasFee = l1FeeInSrcPrice + l2FeeInSrcPrice;
        return (gasFee, optimismPrice.priceRatio);
    }

    function _estimateFeeWithArbitrumModel(
        uint32 _dstEid,
        uint _callDataSize,
        uint _gas
    ) internal view returns (uint fee, uint128 priceRatio) {
        Price storage arbitrumPrice = defaultModelPrice[_dstEid];

        // L1 fee
        uint gasForL1CallData = ((_callDataSize * ARBITRUM_COMPRESSION_PERCENT) / 100) *
            arbitrumPriceExt.gasPerL1CallDataByte;
        // L2 Fee
        uint gasForL2CallData = _callDataSize * arbitrumPrice.gasPerByte;
        uint gasFee = (_gas + arbitrumPriceExt.gasPerL2Tx + gasForL1CallData + gasForL2CallData) *
            arbitrumPrice.gasPriceInUnit;

        return ((gasFee * arbitrumPrice.priceRatio) / PRICE_RATIO_DENOMINATOR, arbitrumPrice.priceRatio);
    }
}
