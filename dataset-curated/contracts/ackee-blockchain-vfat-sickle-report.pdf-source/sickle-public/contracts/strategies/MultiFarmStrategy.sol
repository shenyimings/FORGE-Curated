// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { INonfungiblePositionManager } from
    "contracts/interfaces/external/uniswap/INonfungiblePositionManager.sol";

import { IFarmConnector } from "contracts/interfaces/IFarmConnector.sol";
import { INftFarmConnector } from "contracts/interfaces/INftFarmConnector.sol";
import { Farm } from "contracts/structs/FarmStrategyStructs.sol";
import {
    NftPosition,
    SimpleNftHarvest
} from "contracts/structs/NftFarmStrategyStructs.sol";
import {
    StrategyModule,
    SickleFactory,
    Sickle
} from "contracts/modules/StrategyModule.sol";
import { ConnectorRegistry } from "contracts/ConnectorRegistry.sol";
import { IZapLib } from "contracts/interfaces/libraries/IZapLib.sol";
import { INftZapLib } from "contracts/interfaces/libraries/INftZapLib.sol";
import { IFeesLib } from "contracts/interfaces/libraries/IFeesLib.sol";
import { ITransferLib } from "contracts/interfaces/libraries/ITransferLib.sol";
import { ISwapLib } from "contracts/interfaces/libraries/ISwapLib.sol";
import { FarmStrategyEvents } from "contracts/events/FarmStrategyEvents.sol";
import { NftFarmStrategyEvents } from
    "contracts/events/NftFarmStrategyEvents.sol";
import {
    ClaimParams,
    NftClaimParams,
    MultiCompoundParams,
    NftMultiCompoundParams,
    MultiHarvestParams
} from "contracts/structs/MultiFarmStrategyStructs.sol";

library MultiFarmStrategyFees {
    bytes4 constant Harvest = bytes4(keccak256("FarmHarvestFee"));
    bytes4 constant Compound = bytes4(keccak256("FarmCompoundFee"));
}

contract MultiFarmStrategy is
    StrategyModule,
    FarmStrategyEvents,
    NftFarmStrategyEvents
{
    struct Libraries {
        ITransferLib transferLib;
        ISwapLib swapLib;
        IFeesLib feesLib;
        IZapLib zapLib;
        INftZapLib nftZapLib;
    }

    ITransferLib public immutable transferLib;
    ISwapLib public immutable swapLib;
    IFeesLib public immutable feesLib;
    IZapLib public immutable zapLib;
    INftZapLib public immutable nftZapLib;
    address public immutable strategyAddress;

    constructor(
        SickleFactory factory,
        ConnectorRegistry connectorRegistry,
        Libraries memory libraries
    ) StrategyModule(factory, connectorRegistry) {
        strategyAddress = address(this);
        transferLib = libraries.transferLib;
        swapLib = libraries.swapLib;
        feesLib = libraries.feesLib;
        zapLib = libraries.zapLib;
        nftZapLib = libraries.nftZapLib;
    }

    /* External Functions */

    /**
     * @notice Compound multiple ERC20 and/or NFT farms into a single ERC20 farm
     * @param params The parameters for the compound operation
     * @param sweepTokens The tokens to sweep after the compound operation
     */
    function compoundMultiple(
        MultiCompoundParams calldata params,
        address[] memory sweepTokens
    ) external {
        Sickle sickle = getSickle(msg.sender);

        _harvest_erc20_positions(sickle, params.claims);
        _harvest_nft_positions(sickle, params.nftClaims);

        address[] memory targets = new address[](4);
        bytes[] memory data = new bytes[](4);

        targets[0] = address(feesLib);
        data[0] = abi.encodeCall(
            IFeesLib.chargeFees,
            (
                strategyAddress,
                MultiFarmStrategyFees.Compound,
                params.rewardTokens
            )
        );

        targets[1] = address(zapLib);
        data[1] = abi.encodeCall(IZapLib.zapIn, (params.zap));

        address depositFarmConnector =
            connectorRegistry.connectorOf(params.depositFarm.stakingContract);
        targets[2] = depositFarmConnector;
        data[2] = abi.encodeCall(
            IFarmConnector.deposit,
            (
                params.depositFarm,
                params.zap.addLiquidityParams.lpToken,
                params.depositExtraData
            )
        );

        targets[3] = address(transferLib);
        data[3] =
            abi.encodeCall(ITransferLib.transferTokensToUser, (sweepTokens));

        sickle.multicall(targets, data);

        _emit_compound_events(
            sickle, params.depositFarm, params.claims, params.nftClaims
        );
    }

    /**
     * @notice Compound multiple ERC20 and/or NFT farms into a single NFT farm
     * @param params The parameters for the compound operation
     * @param sweepTokens The tokens to sweep after the compound operation
     */
    function nftCompoundMultiple(
        NftMultiCompoundParams calldata params,
        address[] calldata sweepTokens
    ) external {
        Sickle sickle = getSickle(msg.sender);

        _harvest_erc20_positions(sickle, params.claims);
        _harvest_nft_positions(sickle, params.nftClaims);

        if (!params.compoundInPlace) {
            _withdraw_nft(
                sickle, params.depositPosition, params.depositExtraData
            );
        }

        address[] memory targets = new address[](3);
        bytes[] memory data = new bytes[](3);

        targets[0] = address(feesLib);
        data[0] = abi.encodeCall(
            IFeesLib.chargeFees,
            (
                strategyAddress,
                MultiFarmStrategyFees.Compound,
                params.rewardTokens
            )
        );

        targets[1] = address(nftZapLib);
        data[1] = abi.encodeCall(INftZapLib.zapIn, (params.zap));

        targets[2] = address(transferLib);
        data[2] =
            abi.encodeCall(ITransferLib.transferTokensToUser, (sweepTokens));

        sickle.multicall(targets, data);

        if (!params.compoundInPlace) {
            _deposit_nft(
                sickle, params.depositPosition, params.depositExtraData
            );
        }

        _emit_compound_events(
            sickle, params.depositPosition.farm, params.claims, params.nftClaims
        );
    }

    /**
     * @notice Harvest multiple ERC20 and/or NFT farms
     * @param params The parameters for the harvest operation
     * @param sweepTokens The tokens to sweep after the harvest operation
     */
    function harvestMultiple(
        MultiHarvestParams calldata params,
        address[] memory sweepTokens
    ) public {
        Sickle sickle = getSickle(msg.sender);

        _harvest_erc20_positions(sickle, params.claims);
        _harvest_nft_positions(sickle, params.nftClaims);

        address[] memory targets = new address[](3);
        bytes[] memory data = new bytes[](3);

        targets[0] = address(swapLib);
        data[0] = abi.encodeCall(ISwapLib.swapMultiple, (params.swaps));

        targets[1] = address(feesLib);
        data[1] = abi.encodeCall(
            IFeesLib.chargeFees,
            (strategyAddress, MultiFarmStrategyFees.Harvest, params.tokensOut)
        );

        targets[2] = address(transferLib);
        data[2] =
            abi.encodeCall(ITransferLib.transferTokensToUser, (sweepTokens));

        sickle.multicall(targets, data);

        _emit_harvest_events(sickle, params.claims, params.nftClaims);
    }

    /* Private Functions */

    function _harvest_erc20_positions(
        Sickle sickle,
        ClaimParams[] calldata params
    ) private {
        uint256 arrayLength = params.length;
        address[] memory targets = new address[](arrayLength);
        bytes[] memory data = new bytes[](arrayLength);

        for (uint256 i; i < arrayLength; i++) {
            ClaimParams calldata claim = params[i];
            address farmConnector =
                connectorRegistry.connectorOf(claim.claimFarm.stakingContract);

            targets[i] = farmConnector;
            data[i] = abi.encodeCall(
                IFarmConnector.claim, (claim.claimFarm, claim.claimExtraData)
            );
        }

        sickle.multicall(targets, data);
    }

    function _harvest_nft_positions(
        Sickle sickle,
        NftClaimParams[] calldata params
    ) private {
        uint256 arrayLength = params.length;
        address[] memory targets = new address[](arrayLength);
        bytes[] memory data = new bytes[](arrayLength);

        for (uint256 i; i < arrayLength; i++) {
            NftClaimParams calldata claim = params[i];
            address farmConnector = connectorRegistry.connectorOf(
                claim.position.farm.stakingContract
            );

            targets[i] = farmConnector;
            data[i] = abi.encodeCall(
                INftFarmConnector.claim,
                (
                    claim.position,
                    claim.harvest.rewardTokens,
                    claim.harvest.amount0Max,
                    claim.harvest.amount1Max,
                    claim.harvest.extraData
                )
            );
        }

        sickle.multicall(targets, data);
    }

    function _withdraw_nft(
        Sickle sickle,
        NftPosition calldata position,
        bytes calldata extraData
    ) private {
        address farmConnector =
            connectorRegistry.connectorOf(position.farm.stakingContract);

        address[] memory targets = new address[](1);
        bytes[] memory data = new bytes[](1);

        targets[0] = farmConnector;
        data[0] =
            abi.encodeCall(INftFarmConnector.withdrawNft, (position, extraData));

        sickle.multicall(targets, data);
    }

    function _deposit_nft(
        Sickle sickle,
        NftPosition calldata position,
        bytes calldata extraData
    ) private {
        address farmConnector =
            connectorRegistry.connectorOf(position.farm.stakingContract);

        address[] memory targets = new address[](1);
        bytes[] memory data = new bytes[](1);

        targets[0] = farmConnector;
        data[0] = abi.encodeCall(
            INftFarmConnector.depositExistingNft, (position, extraData)
        );

        sickle.multicall(targets, data);
    }

    function _emit_harvest_events(
        Sickle sickle,
        ClaimParams[] calldata claims,
        NftClaimParams[] calldata nftClaims
    ) private {
        for (uint256 i = 0; i < claims.length; i++) {
            emit SickleHarvested(
                sickle,
                claims[i].claimFarm.stakingContract,
                claims[i].claimFarm.poolIndex
            );
        }

        for (uint256 i = 0; i < nftClaims.length; i++) {
            emit SickleHarvestedNft(
                sickle,
                nftClaims[i].position.farm.stakingContract,
                nftClaims[i].position.farm.poolIndex,
                nftClaims[i].position.nft,
                nftClaims[i].position.tokenId
            );
        }
    }

    function _emit_compound_events(
        Sickle sickle,
        Farm calldata depositFarm,
        ClaimParams[] calldata claims,
        NftClaimParams[] calldata nftClaims
    ) private {
        for (uint256 i = 0; i < claims.length; i++) {
            emit SickleCompounded(
                sickle,
                claims[i].claimFarm.stakingContract,
                claims[i].claimFarm.poolIndex,
                depositFarm.stakingContract,
                depositFarm.poolIndex
            );
        }

        for (uint256 i = 0; i < nftClaims.length; i++) {
            emit SickleCompoundedNft(
                sickle,
                depositFarm.stakingContract,
                depositFarm.poolIndex,
                nftClaims[i].position.nft,
                nftClaims[i].position.tokenId
            );
        }
    }
}
