// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0 <0.9.0;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {EIP712} from "openzeppelin-contracts/contracts/utils/cryptography/EIP712.sol";
import {Multicall} from "openzeppelin-contracts/contracts/utils/Multicall.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IV3Pool} from "../../interfaces/handlers/V3/IV3Pool.sol";
import {ECDSA} from "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";

import {IOptionMarketOTMFE} from "../../interfaces/apps/options/IOptionMarketOTMFE.sol";
import {ISwapper} from "../../interfaces/ISwapper.sol";

contract ExerciseOptionFirewall is Multicall, Ownable, EIP712 {
    using SafeERC20 for IERC20;
    using ECDSA for bytes32;

    mapping(address => bool) public whitelistedExecutors;
    mapping(address => bool) public whitelistedMarkets;

    error NotWhitelistedMarket();
    error NotWhitelistedExecutor();
    error ArrayLenMismatch();
    error NotOwner();
    error OptionExpired();
    error InvalidSignature();
    error InvalidDeadline();
    error InvalidTick();
    error InvalidSqrtPriceX96();
    error OptionNotExpired();

    struct RangeCheckData {
        address user;
        address pool;
        address market;
        int24 minTickLower;
        int24 maxTickUpper;
        uint160 minSqrtPriceX96;
        uint160 maxSqrtPriceX96;
        uint256 deadline;
    }

    struct Signature {
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    struct PoolData {
        uint160 sqrtPriceX96;
        int24 tick;
    }

    bytes32 private constant RANGE_CHECK_TYPEHASH = keccak256(
        "RangeCheck(address user,address pool,int24 minTickLower,int24 maxTickUpper,uint160 minSqrtPriceX96,uint160 maxSprtPriceX96,uint256 deadline)"
    );

    constructor(address _signer) EIP712("ExerciseOptionFirewall", "1") Ownable(msg.sender) {
        whitelistedExecutors[_signer] = true;
    }

    function updateWhitelistedExecutor(address executor, bool isWhitelisted) external onlyOwner {
        whitelistedExecutors[executor] = isWhitelisted;
    }

    function updateWhitelistedMarket(address market, bool isWhitelisted) external onlyOwner {
        whitelistedMarkets[market] = isWhitelisted;
    }

    function exerciseOption(
        IOptionMarketOTMFE market,
        uint256 optionId,
        IOptionMarketOTMFE.SettleOptionParams memory settleParams,
        RangeCheckData[] calldata rangeCheckData,
        Signature[] calldata signature
    ) external returns (IOptionMarketOTMFE.AssetsCache memory) {
        if (!whitelistedMarkets[address(market)]) {
            revert NotWhitelistedMarket();
        }

        if (market.ownerOf(optionId) != msg.sender) {
            revert NotOwner();
        }

        IOptionMarketOTMFE.OptionData memory oData = market.opData(optionId);

        if (oData.opTickArrayLen != rangeCheckData.length) {
            revert ArrayLenMismatch();
        }

        for (uint256 i; i < oData.opTickArrayLen; i++) {
            _checkRange(market, market.opTickMap(optionId, i), rangeCheckData[i], signature[i]);
        }

        (IOptionMarketOTMFE.AssetsCache memory ac) = market.settleOption(settleParams);

        if (ac.isSettle) {
            revert OptionExpired();
        }

        if (ac.totalProfit > 0) {
            IERC20(address(ac.assetToGet)).safeTransfer(market.ownerOf(settleParams.optionId), ac.totalProfit);
        }

        return ac;
    }

    function settleOption(
        IOptionMarketOTMFE market,
        uint256 optionId,
        IOptionMarketOTMFE.SettleOptionParams memory settleParams
    ) external returns (IOptionMarketOTMFE.AssetsCache memory) {
        if (!whitelistedMarkets[address(market)]) {
            revert NotWhitelistedMarket();
        }

        if (!whitelistedExecutors[msg.sender]) {
            revert NotWhitelistedExecutor();
        }

        (IOptionMarketOTMFE.AssetsCache memory ac) = market.settleOption(settleParams);

        if (!ac.isSettle) revert OptionNotExpired();

        if (ac.totalProfit > 0) {
            IERC20(address(ac.assetToGet)).safeTransfer(market.ownerOf(settleParams.optionId), ac.totalProfit);
        }

        return ac;
    }

    function _checkRange(
        IOptionMarketOTMFE market,
        IOptionMarketOTMFE.OptionTicks memory optionTicks,
        RangeCheckData calldata rangeCheckData,
        Signature calldata signature
    ) internal view {
        bytes32 structHash = keccak256(
            abi.encode(
                RANGE_CHECK_TYPEHASH,
                msg.sender,
                address(optionTicks.pool),
                address(market),
                rangeCheckData.minTickLower,
                rangeCheckData.maxTickUpper,
                rangeCheckData.minSqrtPriceX96,
                rangeCheckData.maxSqrtPriceX96,
                rangeCheckData.deadline
            )
        );

        bytes32 hash = _hashTypedDataV4(structHash);

        if (!whitelistedExecutors[hash.recover(signature.v, signature.r, signature.s)]) {
            revert InvalidSignature();
        }

        if (rangeCheckData.deadline < block.timestamp) {
            revert InvalidDeadline();
        }

        PoolData memory poolData;
        (, bytes memory result) = address(optionTicks.pool).staticcall(abi.encodeWithSignature("slot0()"));
        (poolData.sqrtPriceX96, poolData.tick) = abi.decode(result, (uint160, int24));

        if (poolData.tick < rangeCheckData.minTickLower || poolData.tick > rangeCheckData.maxTickUpper) {
            revert InvalidTick();
        }

        if (
            poolData.sqrtPriceX96 < rangeCheckData.minSqrtPriceX96
                || poolData.sqrtPriceX96 > rangeCheckData.maxSqrtPriceX96
        ) revert InvalidSqrtPriceX96();
    }

    function hashTypedDataV4(bytes32 structHash) public view returns (bytes32) {
        return _hashTypedDataV4(structHash);
    }

    function getRangeCheckTypehash() public pure returns (bytes32) {
        return RANGE_CHECK_TYPEHASH;
    }

    function getDomainSeparator() public view returns (bytes32) {
        return _domainSeparatorV4();
    }
}
