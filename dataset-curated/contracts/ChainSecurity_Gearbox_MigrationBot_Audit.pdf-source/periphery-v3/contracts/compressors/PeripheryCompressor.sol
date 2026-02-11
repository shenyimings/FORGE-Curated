// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundaiton, 2025.
pragma solidity ^0.8.23;

import {IBotListV3} from "@gearbox-protocol/core-v3/contracts/interfaces/IBotListV3.sol";
import {ICreditAccountV3} from "@gearbox-protocol/core-v3/contracts/interfaces/ICreditAccountV3.sol";
import {ICreditFacadeV3} from "@gearbox-protocol/core-v3/contracts/interfaces/ICreditFacadeV3.sol";
import {ICreditManagerV3} from "@gearbox-protocol/core-v3/contracts/interfaces/ICreditManagerV3.sol";
import {IBot} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IBot.sol";
import {IZapper} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IZapper.sol";

import {IMarketConfigurator} from "@gearbox-protocol/permissionless/contracts/interfaces/IMarketConfigurator.sol";
import {DOMAIN_BOT, DOMAIN_ZAPPER} from "@gearbox-protocol/permissionless/contracts/libraries/ContractLiterals.sol";

import {ITokenCompressor} from "../interfaces/ITokenCompressor.sol";
import {IPeripheryCompressor} from "../interfaces/IPeripheryCompressor.sol";

import {BaseLib} from "../libraries/BaseLib.sol";
import {ILegacyBotList} from "../libraries/Legacy.sol";
import {AP_PERIPHERY_COMPRESSOR, AP_TOKEN_COMPRESSOR} from "../libraries/Literals.sol";

import {PartialLiquidationBotSerializer} from "../serializers/periphery/PartialLiquidationBotSerializer.sol";

import {BotState, ConnectedBotState, ZapperState} from "../types/PeripheryState.sol";

import {BaseCompressor} from "./BaseCompressor.sol";

contract PeripheryCompressor is BaseCompressor, IPeripheryCompressor {
    using BaseLib for address;

    uint256 public constant override version = 3_10;
    bytes32 public constant override contractType = AP_PERIPHERY_COMPRESSOR;

    address internal immutable _partialLiquidationBotSerializer;

    constructor(address addressProvider_) BaseCompressor(addressProvider_) {
        _partialLiquidationBotSerializer = address(new PartialLiquidationBotSerializer());
    }

    function getZappers(address marketConfigurator, address pool)
        external
        view
        override
        returns (ZapperState[] memory zappers)
    {
        address tokenCompressor = _getLatestAddress(AP_TOKEN_COMPRESSOR, 3_10);

        address[] memory allZappers = IMarketConfigurator(marketConfigurator).getPeripheryContracts(DOMAIN_ZAPPER);
        zappers = new ZapperState[](allZappers.length);
        uint256 num;
        for (uint256 i; i < allZappers.length; ++i) {
            if (IZapper(allZappers[i]).pool() != pool) continue;
            ZapperState memory zapperState = ZapperState({
                baseParams: allZappers[i].getBaseParams("ZAPPER::UNKNOWN", address(0)),
                tokenIn: ITokenCompressor(tokenCompressor).getTokenInfo(IZapper(allZappers[i]).tokenIn()),
                tokenOut: ITokenCompressor(tokenCompressor).getTokenInfo(IZapper(allZappers[i]).tokenOut())
            });
            zappers[num++] = zapperState;
        }
        assembly {
            mstore(zappers, num)
        }
    }

    function getBots(address marketConfigurator) external view override returns (BotState[] memory botStates) {
        address[] memory bots = IMarketConfigurator(marketConfigurator).getPeripheryContracts(DOMAIN_BOT);
        botStates = new BotState[](bots.length);
        for (uint256 i; i < bots.length; ++i) {
            botStates[i].baseParams =
                bots[i].getBaseParams("BOT::PARTIAL_LIQUIDATION", _partialLiquidationBotSerializer);
            try IBot(bots[i]).requiredPermissions() returns (uint192 requiredPermissions) {
                botStates[i].requiredPermissions = requiredPermissions;
            } catch {}
        }
    }

    function getConnectedBots(address marketConfigurator, address creditAccount)
        external
        view
        override
        returns (ConnectedBotState[] memory botStates)
    {
        address creditManager = ICreditAccountV3(creditAccount).creditManager();
        address botList = ICreditFacadeV3(ICreditManagerV3(creditManager).creditFacade()).botList();
        uint256 botListVersion = IBotListV3(botList).version();

        address[] memory bots = IMarketConfigurator(marketConfigurator).getPeripheryContracts(DOMAIN_BOT);
        botStates = new ConnectedBotState[](bots.length);
        uint256 num;
        for (uint256 i; i < bots.length; ++i) {
            ConnectedBotState memory botState;
            if (botListVersion < 3_10) {
                (botState.permissions, botState.forbidden,) =
                    ILegacyBotList(botList).getBotStatus(bots[i], creditManager, creditAccount);
            } else {
                (botState.permissions, botState.forbidden) = IBotListV3(botList).getBotStatus(bots[i], creditAccount);
            }
            if (botState.permissions != 0) {
                botState.baseParams =
                    bots[i].getBaseParams("BOT::PARTIAL_LIQUIDATION", _partialLiquidationBotSerializer);
                botState.creditAccount = creditAccount;
                try IBot(bots[i]).requiredPermissions() returns (uint192 requiredPermissions) {
                    botState.requiredPermissions = requiredPermissions;
                } catch {}
                botStates[num++] = botState;
            }
        }
        assembly {
            mstore(botStates, num)
        }
    }
}
