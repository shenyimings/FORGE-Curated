// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0 <0.9.0;

import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IHandler} from "../../IHandler.sol";
import {ISwapper} from "../../ISwapper.sol";

import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

interface IOptionMarketOTMFE {
    /// @notice Struct to store option data
    struct OptionData {
        uint256 opTickArrayLen;
        uint256 expiry;
        int24 tickLower;
        int24 tickUpper;
        bool isCall;
    }

    /// @notice Struct to store option ticks data
    struct OptionTicks {
        IHandler _handler;
        IUniswapV3Pool pool;
        address hook;
        int24 tickLower;
        int24 tickUpper;
        uint256 liquidityToUse;
    }

    /// @notice Struct for option parameters
    struct OptionParams {
        OptionTicks[] optionTicks;
        uint256 ttl;
        uint256 maxCostAllowance;
        int24 tickLower;
        int24 tickUpper;
        bool isCall;
    }

    /// @notice Struct for settling option parameters
    struct SettleOptionParams {
        uint256 optionId;
        ISwapper[] swapper;
        bytes[] swapData;
        uint256[] liquidityToSettle;
    }

    /// @notice Struct for position splitter parameters
    struct PositionSplitterParams {
        uint256 optionId;
        address to;
        uint256[] liquidityToSplit;
    }

    /// @notice Struct to cache asset-related data during option settlement
    struct AssetsCache {
        uint256 totalProfit;
        uint256 totalAssetRelocked;
        ERC20 assetToUse;
        ERC20 assetToGet;
        bool isSettle;
    }

    /// @notice Mints a new option
    /// @param _params The option parameters
    function mintOption(OptionParams calldata _params) external;

    /// @notice Settles an option
    /// @param _params The settlement parameters
    /// @return ac The assets cache containing settlement results
    function settleOption(SettleOptionParams calldata _params) external returns (AssetsCache memory ac);

    /// @notice Splits a position into a new option
    /// @param _params The position splitter parameters
    function positionSplitter(PositionSplitterParams calldata _params) external;

    /// @notice Updates the exercise delegate for the caller
    /// @param _delegateTo The address to delegate to
    /// @param _status The delegation status
    function updateExerciseDelegate(address _delegateTo, bool _status) external;

    /// @notice Gets the price per call asset via a specific tick
    /// @param _pool The Uniswap V3 pool
    /// @param _tick The tick to get the price for
    /// @return uint256 The price per call asset
    function getPricePerCallAssetViaTick(IUniswapV3Pool _pool, int24 _tick) external view returns (uint256);

    /// @notice Gets the premium amount for an option
    /// @param hook The hook address
    /// @param isPut Whether the option is a put
    /// @param expiry The expiry timestamp
    /// @param ttl The time-to-live
    /// @param strike The strike price
    /// @param lastPrice The last price
    /// @param amount The option amount
    /// @return uint256 The premium amount
    function getPremiumAmount(
        address hook,
        bool isPut,
        uint256 expiry,
        uint256 ttl,
        uint256 strike,
        uint256 lastPrice,
        uint256 amount
    ) external view returns (uint256);

    /// @notice Gets the fee for a given amount and premium
    /// @param amount The option amount
    /// @param premium The option premium
    /// @return uint256 The calculated fee
    function getFee(uint256 amount, uint256 premium) external view returns (uint256);

    /// @notice Updates pool approvals and settings
    /// @param _settler The settler address
    /// @param _statusSettler The settler status
    /// @param _pool The pool address
    /// @param _statusPools The pool status
    /// @param ttl The time-to-live
    /// @param ttlStatus The TTL status
    /// @param _BUFFER_TIME The buffer time
    function updatePoolApporvals(
        address _settler,
        bool _statusSettler,
        address _pool,
        bool _statusPools,
        uint256 ttl,
        bool ttlStatus,
        uint256 _BUFFER_TIME
    ) external;

    /// @notice Updates pool settings
    /// @param _feeTo The fee recipient address
    /// @param _tokenURIFetcher The token URI fetcher address
    /// @param _dpFee The fee strategy address
    /// @param _optionPricing The option pricing address
    /// @param _verifiedSpotPrice The verified spot price address
    function updatePoolSettings(
        address _feeTo,
        address _tokenURIFetcher,
        address _dpFee,
        address _optionPricing,
        address _verifiedSpotPrice
    ) external;

    /// @notice Emergency withdraw function
    /// @param token The token address to withdraw
    function emergencyWithdraw(address token) external;

    /// @notice Returns the owner of a token
    /// @param id The token ID
    /// @return address The owner of the token
    function ownerOf(uint256 id) external view returns (address);

    /// @notice Returns the address of the call asset
    /// @return address The address of the call asset
    function callAsset() external view returns (address);

    /// @notice Returns the address of the put asset
    /// @return address The address of the put asset
    function putAsset() external view returns (address);

    /// @notice Returns the option IDs
    /// @return uint256 The option IDs
    function optionIds() external view returns (uint256);

    /// @notice Returns the option data
    /// @param optionId The option ID
    /// @return OptionData The option data
    function opData(uint256 optionId) external view returns (OptionData memory);

    /// @notice Returns the option ticks
    /// @param optionId The option ID
    /// @param index The index of the option tick
    /// @return OptionTicks The option tick
    function opTickMap(uint256 optionId, uint256 index) external view returns (OptionTicks memory);
}
