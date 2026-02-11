// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {
    IUniswapV3Pool,
    IUniswapV3PoolState,
    IUniswapV3PoolImmutables
} from "contracts/interfaces/external/uniswap/IUniswapV3Pool.sol";
import { INonfungiblePositionManager } from
    "contracts/interfaces/external/uniswap/INonfungiblePositionManager.sol";

import { Sickle } from "contracts/Sickle.sol";
import { INftSettingsRegistry } from
    "contracts/interfaces/INftSettingsRegistry.sol";
import {
    RewardBehavior,
    RewardConfig
} from "contracts/structs/PositionSettingsStructs.sol";
import {
    NftKey,
    NftSettings,
    ExitConfig,
    RebalanceConfig
} from "contracts/structs/NftSettingsStructs.sol";
import { SickleFactory } from "contracts/SickleFactory.sol";

interface IPreviousAutomation {
    function rewardAutomation(
        address user
    ) external returns (RewardBehavior);
    function harvestTokensOut(
        address user
    ) external returns (address);
}

interface IPreviousNftSettingsRegistry {
    struct PreviousRebalanceConfig {
        int24 bufferTicksBelow;
        int24 bufferTicksAbove;
        uint256 slippageBP;
        int24 cutoffTickLow;
        int24 cutoffTickHigh;
        uint8 delayMin;
    }

    struct PreviousNftSettings {
        bool autoRebalance;
        RewardBehavior rewardBehavior;
        address harvestTokenOut;
        PreviousRebalanceConfig rebalanceConfig;
    }

    function getNftSettings(
        NftKey memory key
    ) external returns (PreviousNftSettings memory);
}

contract NftSettingsRegistry is INftSettingsRegistry {
    error AutoHarvestNotSet();
    error AutoCompoundNotSet();
    error AutoRebalanceNotSet();
    error AutoExitNotSet();
    error CompoundOrHarvestNotSet();
    error CompoundAndHarvestBothSet();
    error ExitTriggersNotSet();
    error InvalidTokenOut();
    error InvalidMinMaxTickRange();
    error InvalidSlippageBP();
    error InvalidPriceImpactBP();
    error InvalidDustBP();
    error InvalidMinTickLow();
    error InvalidMaxTickHigh();
    error OnlySickle();
    error RebalanceConfigNotSet();
    error TickWithinRange();
    error TickOutsideStopLossRange();
    error SickleNotDeployed();
    error InvalidWidth(uint24 actual, uint24 expected);

    event NftSettingsSet(NftKey key, NftSettings settings);
    event NftSettingsUnset(NftKey key);

    uint256 constant MAX_SLIPPAGE_BP = 500;
    uint256 constant MAX_PRICE_IMPACT_BP = 5000;
    uint256 constant MAX_DUST_BP = 5000;
    int24 constant MAX_TICK = 887_272;
    int24 constant MIN_TICK = -MAX_TICK;

    SickleFactory public immutable factory;

    constructor(
        SickleFactory _factory
    ) {
        factory = _factory;
    }

    mapping(bytes32 => NftSettings) settingsMap;

    /* Public functions */

    function getNftSettings(
        NftKey memory key
    ) public view returns (NftSettings memory) {
        return settingsMap[keccak256(abi.encode(key))];
    }

    function validateHarvestFor(
        NftKey memory key
    ) public view {
        NftSettings memory settings = getNftSettings(key);
        if (
            !settings.automateRewards
                || settings.rewardConfig.rewardBehavior != RewardBehavior.Harvest
        ) {
            revert AutoHarvestNotSet();
        }
    }

    function validateCompoundFor(
        NftKey memory key
    ) public view {
        NftSettings memory settings = getNftSettings(key);
        if (
            !settings.automateRewards
                || settings.rewardConfig.rewardBehavior != RewardBehavior.Compound
        ) {
            revert AutoCompoundNotSet();
        }
    }

    // Validate that a rebalanceFor meets the user requirements
    function validateRebalanceFor(
        NftKey memory key
    ) public {
        NftSettings memory settings = getNftSettings(key);
        RebalanceConfig memory config = settings.rebalanceConfig;

        if (!settings.autoRebalance) {
            revert AutoRebalanceNotSet();
        }
        if (config.cutoffTickLow == 0) {
            revert RebalanceConfigNotSet();
        }

        (,,,,, int24 tickLower, int24 tickUpper,,,,,) =
            key.nftManager.positions(key.tokenId);

        int24 tick = _get_current_tick(settings.pool);

        if (
            tick >= tickLower - int24(config.bufferTicksBelow)
                && tick < tickUpper + int24(config.bufferTicksAbove)
        ) {
            revert TickWithinRange();
        }
        if (tick <= config.cutoffTickLow || tick >= config.cutoffTickHigh) {
            revert TickOutsideStopLossRange();
        }
    }

    function validateExitFor(
        NftKey memory key
    ) public {
        NftSettings memory settings = getNftSettings(key);
        ExitConfig memory config = settings.exitConfig;

        if (!settings.autoExit) {
            revert AutoExitNotSet();
        }

        int24 tick = _get_current_tick(settings.pool);

        if (tick >= config.triggerTickLow && tick < config.triggerTickHigh) {
            revert TickWithinRange();
        }
    }

    /* Sickle Owner functions */

    function setNftSettings(
        INonfungiblePositionManager nftManager,
        uint256 tokenId,
        NftSettings calldata settings
    ) external {
        Sickle sickle = _get_sickle_by_owner(msg.sender);
        NftKey memory key = NftKey(sickle, nftManager, tokenId);
        _set_nft_settings(key, settings);
    }

    function unsetNftSettings(
        INonfungiblePositionManager nftManager,
        uint256 tokenId
    ) external {
        Sickle sickle = _get_sickle_by_owner(msg.sender);
        NftKey memory key = NftKey(sickle, nftManager, tokenId);
        _unset_nft_settings(key);
    }

    /* Sickle (delegatecall) functions */

    function setNftSettings(
        NftKey calldata key,
        NftSettings calldata settings
    ) external {
        Sickle sickle = Sickle(payable(msg.sender));

        if (key.sickle != sickle) {
            revert OnlySickle();
        }

        _set_nft_settings(key, settings);
    }

    function resetNftSettings(
        NftKey calldata oldKey,
        NftKey calldata newKey,
        NftSettings calldata settings
    ) external {
        Sickle sickle = Sickle(payable(msg.sender));

        if (oldKey.sickle != sickle || newKey.sickle != sickle) {
            revert OnlySickle();
        }

        _unset_nft_settings(oldKey);

        _set_nft_settings(newKey, settings);
    }

    function migrateNftSettings(
        IPreviousAutomation automation,
        IPreviousNftSettingsRegistry previousNftSettingsRegistry,
        INonfungiblePositionManager nftManager,
        IUniswapV3Pool[] memory pools,
        uint256[] memory tokenIds
    ) external {
        Sickle sickle = _get_sickle_by_owner(msg.sender);

        uint256 tokenLength = tokenIds.length;
        for (uint256 i; i < tokenLength; i++) {
            NftKey memory key = NftKey(sickle, nftManager, tokenIds[i]);
            RebalanceConfig memory newConfig =
                _get_new_rebalance_config(previousNftSettingsRegistry, key);
            NftSettings memory settings =
                _get_new_nft_settings(automation, sickle, pools[i], newConfig);
            _set_nft_settings(key, settings);
        }
    }

    /* Modifiers */

    modifier checkConfigValues(NftKey memory key, NftSettings memory settings) {
        if (settings.autoRebalance) {
            _check_rebalance_config(settings.rebalanceConfig);
            _check_tick_width(key, settings);
        } else {
            if (
                settings.rebalanceConfig.cutoffTickLow != 0
                    || settings.rebalanceConfig.cutoffTickHigh != 0
            ) {
                revert AutoRebalanceNotSet();
            }
        }
        if (
            settings.rewardConfig.rewardBehavior != RewardBehavior.Harvest
                && settings.rewardConfig.harvestTokenOut != address(0)
        ) {
            revert InvalidTokenOut();
        }
        if (!settings.autoExit) {
            if (
                settings.exitConfig.triggerTickLow != 0
                    || settings.exitConfig.triggerTickHigh != 0
                    || settings.exitConfig.exitTokenOutLow != address(0)
                    || settings.exitConfig.exitTokenOutHigh != address(0)
                    || settings.exitConfig.slippageBP != 0
                    || settings.exitConfig.priceImpactBP != 0
            ) {
                revert AutoExitNotSet();
            }
        } else {
            if (
                settings.exitConfig.triggerTickLow == 0
                    && settings.exitConfig.triggerTickHigh == 0
            ) {
                revert ExitTriggersNotSet();
            }
            if (settings.exitConfig.slippageBP > MAX_SLIPPAGE_BP) {
                revert InvalidSlippageBP();
            }
            if (
                settings.exitConfig.priceImpactBP > MAX_PRICE_IMPACT_BP
                    || settings.exitConfig.priceImpactBP == 0
            ) {
                revert InvalidPriceImpactBP();
            }
        }
        _;
    }

    /* Internal */

    function _get_sickle_by_owner(
        address owner
    ) internal view returns (Sickle) {
        Sickle sickle = Sickle(payable(factory.sickles(owner)));
        if (address(sickle) == address(0)) {
            revert SickleNotDeployed();
        }
        return sickle;
    }

    function _set_nft_settings(
        NftKey memory key,
        NftSettings memory settings
    ) internal checkConfigValues(key, settings) {
        settingsMap[keccak256(abi.encode(key))] = settings;
        emit NftSettingsSet(key, settings);
    }

    function _unset_nft_settings(
        NftKey memory key
    ) internal {
        delete settingsMap[keccak256(abi.encode(key))];
        emit NftSettingsUnset(key);
    }

    // Tick is the 2nd field in slot0, the rest can vary
    function _get_current_tick(
        IUniswapV3Pool pool
    ) internal returns (int24) {
        (, bytes memory result) =
            address(pool).call(abi.encodeCall(IUniswapV3PoolState.slot0, ()));

        int24 tick;

        assembly {
            tick := mload(add(result, 64))
        }

        return tick;
    }

    // Check configuratgion parameters for errors
    function _check_rebalance_config(
        RebalanceConfig memory config
    ) internal pure {
        if (config.cutoffTickLow < MIN_TICK) {
            revert InvalidMinTickLow();
        }
        if (config.cutoffTickLow >= config.cutoffTickHigh) {
            revert InvalidMinMaxTickRange();
        }
        if (config.cutoffTickHigh > MAX_TICK) {
            revert InvalidMaxTickHigh();
        }
        if (config.slippageBP > MAX_SLIPPAGE_BP) {
            revert InvalidSlippageBP();
        }
        if (
            config.priceImpactBP > MAX_PRICE_IMPACT_BP
                || config.priceImpactBP == 0
        ) {
            revert InvalidPriceImpactBP();
        }
        if (config.dustBP > MAX_DUST_BP || config.dustBP == 0) {
            revert InvalidDustBP();
        }
        if (
            config.rewardConfig.rewardBehavior != RewardBehavior.Harvest
                && config.rewardConfig.harvestTokenOut != address(0)
        ) {
            revert InvalidTokenOut();
        }
    }

    function _check_tick_width(
        NftKey memory key,
        NftSettings memory settings
    ) internal view {
        (,,,,, int24 tickLower, int24 tickUpper,,,,,) =
            key.nftManager.positions(key.tokenId);
        int24 tickSpacing = settings.pool.tickSpacing();

        uint24 actualWidth = uint24(tickUpper - tickLower) / uint24(tickSpacing);
        uint24 expectedWidth = settings.rebalanceConfig.tickSpacesBelow
            + settings.rebalanceConfig.tickSpacesAbove + 1;

        if (actualWidth != expectedWidth) {
            revert InvalidWidth(actualWidth, expectedWidth);
        }
    }

    /* Migration internals */

    function _get_position_tick_spaces_each_side(
        NftKey memory key
    ) private view returns (uint24 below, uint24 above) {
        (,,,, uint24 tickSpacing, int24 tickLower, int24 tickUpper,,,,,) =
            key.nftManager.positions(key.tokenId);
        uint24 totalSpaces = uint24(tickUpper - tickLower) / tickSpacing - 1;
        below = totalSpaces / 2;
        above = totalSpaces / 2 + totalSpaces % 2;
    }

    function _get_new_nft_settings(
        IPreviousAutomation automation,
        Sickle sickle,
        IUniswapV3Pool pool,
        RebalanceConfig memory newConfig
    ) internal returns (NftSettings memory) {
        address sickleOwner = sickle.owner();
        RewardBehavior rewardBehavior = automation.rewardAutomation(sickleOwner);

        return NftSettings({
            pool: pool,
            autoRebalance: true,
            rebalanceConfig: newConfig,
            automateRewards: rewardBehavior != RewardBehavior.None,
            rewardConfig: RewardConfig(
                rewardBehavior, automation.harvestTokensOut(sickleOwner)
            ),
            autoExit: false,
            exitConfig: ExitConfig(0, 0, address(0), address(0), 0, 0)
        });
    }

    function _get_new_rebalance_config(
        IPreviousNftSettingsRegistry previousNftSettingsRegistry,
        NftKey memory key
    ) internal returns (RebalanceConfig memory) {
        IPreviousNftSettingsRegistry.PreviousNftSettings memory previousSettings =
            previousNftSettingsRegistry.getNftSettings(key);
        IPreviousNftSettingsRegistry.PreviousRebalanceConfig memory oldConfig =
            previousSettings.rebalanceConfig;
        (uint24 spacesBelow, uint24 spacesAbove) =
            _get_position_tick_spaces_each_side(key);
        return RebalanceConfig(
            spacesBelow,
            spacesAbove,
            int24(oldConfig.bufferTicksBelow),
            int24(oldConfig.bufferTicksAbove),
            oldConfig.slippageBP,
            oldConfig.slippageBP,
            oldConfig.slippageBP,
            oldConfig.cutoffTickLow,
            oldConfig.cutoffTickHigh,
            oldConfig.delayMin,
            RewardConfig(
                previousSettings.rewardBehavior,
                previousSettings.harvestTokenOut
            )
        );
    }
}
