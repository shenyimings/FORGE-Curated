// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2025.
pragma solidity ^0.8.23;

import {IPartialLiquidationBotV3} from "@gearbox-protocol/bots-v3/contracts/interfaces/IPartialLiquidationBotV3.sol";
import {IStateSerializerLegacy} from "../../interfaces/IStateSerializerLegacy.sol";

contract PartialLiquidationBotSerializer is IStateSerializerLegacy {
    function serialize(address bot) external view override returns (bytes memory) {
        return abi.encode(
            IPartialLiquidationBotV3(bot).treasury(),
            IPartialLiquidationBotV3(bot).minHealthFactor(),
            IPartialLiquidationBotV3(bot).maxHealthFactor(),
            IPartialLiquidationBotV3(bot).premiumScaleFactor(),
            IPartialLiquidationBotV3(bot).feeScaleFactor()
        );
    }
}
