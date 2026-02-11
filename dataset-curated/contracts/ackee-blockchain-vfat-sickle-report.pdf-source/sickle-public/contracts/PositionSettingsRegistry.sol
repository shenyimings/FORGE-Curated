// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { Sickle } from "contracts/Sickle.sol";
import { SickleFactory } from "contracts/SickleFactory.sol";
import { ConnectorRegistry } from "contracts/ConnectorRegistry.sol";
import { TimelockAdmin } from "contracts/base/TimelockAdmin.sol";
import { Farm } from "contracts/structs/FarmStrategyStructs.sol";
import {
    PositionKey,
    RewardBehavior,
    RewardConfig,
    ExitConfig,
    PositionSettings
} from "contracts/structs/PositionSettingsStructs.sol";
import {
    GetAmountOutParams,
    ILiquidityConnector
} from "contracts/interfaces/ILiquidityConnector.sol";

contract PositionSettingsRegistry is TimelockAdmin {
    error SickleNotDeployed();
    error AutoHarvestNotSet();
    error AutoCompoundNotSet();
    error RewardBehaviorNotSet();
    error AutoExitNotSet();
    error ConditionsNotMet();
    error InvalidPrice();
    error InvalidTokenOut();
    error ExitTriggersNotSet();
    error InvalidExitTriggers();
    error InvalidSlippageBP();
    error InvalidPriceImpactBP();
    error OnlySickle();
    error NonZeroRewardConfig();
    error NonZeroExitConfig();

    event PositionSettingsSet(PositionKey key, PositionSettings settings);
    event ConnectionRegistrySet(address connectorRegistry);

    uint256 constant MAX_SLIPPAGE_BP = 500;
    uint256 constant MAX_PRICE_IMPACT_BP = 5000;

    SickleFactory public immutable factory;
    ConnectorRegistry private _connectorRegistry;

    mapping(bytes32 => PositionSettings) positionSettingsMap;

    constructor(
        SickleFactory _factory,
        ConnectorRegistry connectorRegistry,
        address timelockAdmin
    ) TimelockAdmin(timelockAdmin) {
        factory = _factory;
        _connectorRegistry = connectorRegistry;
        emit ConnectionRegistrySet(address(connectorRegistry));
    }

    /* Timelock functions */

    function setConnectorRegistry(
        ConnectorRegistry connectorRegistry
    ) external onlyTimelockAdmin {
        _connectorRegistry = connectorRegistry;
        emit ConnectionRegistrySet(address(connectorRegistry));
    }

    /* Public functions */

    function getPositionSettings(
        PositionKey calldata key
    ) public view returns (PositionSettings memory) {
        bytes32 keyHash = keccak256(abi.encode(key));
        return positionSettingsMap[keyHash];
    }

    /* Owner functions */

    function setPositionSettings(
        Farm calldata farm,
        PositionSettings calldata settings
    ) external checkPositionSettings(settings) {
        PositionKey memory key = PositionKey({
            sickle: _get_sickle_by_owner(msg.sender),
            stakingContract: farm.stakingContract,
            poolIndex: farm.poolIndex
        });
        bytes32 keyHash = keccak256(abi.encode(key));
        positionSettingsMap[keyHash] = settings;
        emit PositionSettingsSet(key, settings);
    }

    /* Sickle functions */

    function setPositionSettings(
        PositionKey calldata key,
        PositionSettings calldata settings
    ) external checkPositionSettings(settings) {
        Sickle sickle = Sickle(payable(msg.sender));
        if (key.sickle != sickle) {
            revert OnlySickle();
        }
        bytes32 keyHash = keccak256(abi.encode(key));
        positionSettingsMap[keyHash] = settings;
        emit PositionSettingsSet(key, settings);
    }

    // Used to set reward behavior (but not auto-exit) for multiple positions
    function setPositionSettings(
        Farm[] calldata farms,
        RewardConfig calldata rewardConfig
    ) public checkRewardConfig(rewardConfig) {
        Sickle sickle = _get_sickle_by_owner(msg.sender);
        PositionSettings memory settings;
        PositionKey memory key;
        for (uint256 i; i < farms.length; i++) {
            key = PositionKey({
                sickle: sickle,
                stakingContract: farms[i].stakingContract,
                poolIndex: farms[i].poolIndex
            });
            bytes32 keyHash = keccak256(abi.encode(key));
            settings = positionSettingsMap[keyHash];
            settings.rewardConfig = rewardConfig;
            positionSettingsMap[keyHash] = settings;
            emit PositionSettingsSet(key, settings);
        }
    }

    function validateHarvestFor(
        PositionKey calldata key
    ) public view {
        PositionSettings memory settings = getPositionSettings(key);
        if (
            !settings.automateRewards
                || settings.rewardConfig.rewardBehavior != RewardBehavior.Harvest
        ) {
            revert AutoHarvestNotSet();
        }
    }

    function validateCompoundFor(
        PositionKey calldata key
    ) public view {
        PositionSettings memory settings = getPositionSettings(key);
        if (
            !settings.automateRewards
                || settings.rewardConfig.rewardBehavior != RewardBehavior.Compound
        ) {
            revert AutoCompoundNotSet();
        }
    }

    function validateExitFor(
        PositionKey calldata key
    ) public view {
        PositionSettings memory settings = getPositionSettings(key);
        ExitConfig memory config = settings.exitConfig;

        if (!settings.autoExit) {
            revert AutoExitNotSet();
        }

        uint256 price = _get_pool_price(settings);
        (uint256 reserves0, uint256 reserves1,) = settings.pair.getReserves();

        bool priceBelowRange = price < config.triggerPriceLow;

        bool priceAboveRange = price > config.triggerPriceHigh;

        bool reservesBelowRange = reserves0 < config.triggerReserves0
            || reserves1 < config.triggerReserves1;

        if (!priceBelowRange && !priceAboveRange && !reservesBelowRange) {
            revert ConditionsNotMet();
        }
    }

    /* Modifiers */

    modifier checkPositionSettings(
        PositionSettings memory settings
    ) {
        if (settings.automateRewards) {
            _check_reward_config(settings.rewardConfig);
        } else {
            if (
                settings.rewardConfig.rewardBehavior != RewardBehavior.None
                    || settings.rewardConfig.harvestTokenOut != address(0)
            ) {
                revert NonZeroRewardConfig();
            }
        }
        if (settings.autoExit) {
            if (
                settings.exitConfig.triggerPriceLow == 0
                    && settings.exitConfig.triggerPriceHigh == 0
            ) {
                revert ExitTriggersNotSet();
            }
            if (
                settings.exitConfig.triggerPriceLow
                    >= settings.exitConfig.triggerPriceHigh
            ) {
                revert InvalidExitTriggers();
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
        } else {
            if (
                settings.exitConfig.triggerPriceLow != 0
                    || settings.exitConfig.triggerPriceHigh != 0
                    || settings.exitConfig.exitTokenOutLow != address(0)
                    || settings.exitConfig.exitTokenOutHigh != address(0)
                    || settings.exitConfig.slippageBP != 0
                    || settings.exitConfig.priceImpactBP != 0
            ) {
                revert NonZeroExitConfig();
            }
        }
        _;
    }

    modifier checkRewardConfig(
        RewardConfig memory rewardConfig
    ) {
        _check_reward_config(rewardConfig);
        _;
    }

    function _check_reward_config(
        RewardConfig memory rewardConfig
    ) private pure {
        if (rewardConfig.rewardBehavior == RewardBehavior.None) {
            revert RewardBehaviorNotSet();
        }
        if (
            rewardConfig.rewardBehavior == RewardBehavior.Compound
                && rewardConfig.harvestTokenOut != address(0)
        ) {
            revert InvalidTokenOut();
        }
    }

    /* Internal */

    function _get_sickle_by_owner(
        address owner
    ) public view returns (Sickle) {
        Sickle sickle = Sickle(payable(factory.sickles(owner)));
        if (address(sickle) == address(0)) {
            revert SickleNotDeployed();
        }
        return sickle;
    }

    function _get_pool_price(
        PositionSettings memory settings
    ) private view returns (uint256 price) {
        address token0 = settings.pair.token0();
        address token1 = settings.pair.token1();

        ILiquidityConnector connector = ILiquidityConnector(
            _connectorRegistry.connectorOf(address(settings.router))
        );

        uint256 amountOut0 = connector.getAmountOut(
            GetAmountOutParams({
                router: address(settings.router),
                lpToken: address(settings.pair),
                tokenIn: token0,
                tokenOut: token1,
                amountIn: 1
            })
        );

        if (amountOut0 > 0) {
            price = amountOut0 * 1e18;
        } else {
            uint256 amountOut1 = connector.getAmountOut(
                GetAmountOutParams({
                    router: address(settings.router),
                    lpToken: address(settings.pair),
                    tokenIn: token1,
                    tokenOut: token0,
                    amountIn: 1
                })
            );
            if (amountOut1 == 0) {
                revert InvalidPrice();
            }
            price = 1e18 / amountOut1;
        }

        if (price == 0) {
            revert InvalidPrice();
        }
    }
}
