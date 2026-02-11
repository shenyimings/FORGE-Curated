// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IUniswapV3Pool } from
    "contracts/interfaces/external/uniswap/IUniswapV3Pool.sol";

import { Admin } from "contracts/base/Admin.sol";
import { NonDelegateMulticall } from "contracts/base/NonDelegateMulticall.sol";
import { Sickle } from "contracts/Sickle.sol";
import { SickleRegistry } from "contracts/SickleRegistry.sol";
import { IAutomation } from "contracts/interfaces/IAutomation.sol";
import { INftAutomation } from "contracts/interfaces/INftAutomation.sol";
import {
    NftRebalance,
    NftPosition,
    NftHarvest,
    NftWithdraw,
    NftCompound
} from "contracts/structs/NftFarmStrategyStructs.sol";
import {
    Farm,
    HarvestParams,
    WithdrawParams,
    CompoundParams
} from "contracts/structs/FarmStrategyStructs.sol";

// @title Automation contract for automating farming strategies
// @notice This contract allows users to automate their farming strategies
// by enabling auto-compound or auto-harvest for non-NFT positions.
// Only one of Auto-Compound or Auto-Harvest can be enabled:
// all user positions will be either auto-compounded or auto-harvested.
// For NFT positions, all automation settings are handled by NftSettingsRegistry
// instead.
// The contract also allows an approved automator to compound, harvest, exit or
// rebalance farming positions on behalf of users.
// @dev This contract is expected to be used by an external automation bot
// that will call the compoundFor, harvestFor, and rebalanceFor functions.
// The automation bot is expected to be the EOA of the approved automator.
// The approved automator is set by the protocol admin.
contract Automation is Admin, NonDelegateMulticall {
    error InvalidInputLength();
    error NotApprovedAutomator();

    event HarvestedFor(
        Sickle indexed sickle,
        address indexed stakingContract,
        uint256 indexed poolIndex
    );
    event CompoundedFor(
        Sickle indexed sickle,
        address indexed claimStakingContract,
        uint256 claimPoolIndex,
        address indexed depositStakingContract,
        uint256 depositPoolIndex
    );
    event ExitedFor(
        Sickle indexed sickle,
        address indexed stakingContract,
        uint256 indexed poolIndex
    );

    event NftHarvestedFor(
        Sickle indexed sickle,
        address indexed nftAddress,
        uint256 indexed tokenId
    );
    event NftCompoundedFor(
        Sickle indexed sickle,
        address indexed nftAddress,
        uint256 indexed tokenId
    );
    event NftExitedFor(
        Sickle indexed sickle,
        address indexed nftAddress,
        uint256 indexed tokenId
    );
    event NftRebalancedFor(
        Sickle indexed sickle,
        address indexed nftAddress,
        uint256 indexed tokenId
    );
    event ApprovedAutomatorSet(address approvedAutomator);

    address payable public approvedAutomator;

    constructor(
        SickleRegistry registry_,
        address payable approvedAutomator_,
        address admin_
    ) Admin(admin_) NonDelegateMulticall(registry_) {
        approvedAutomator = approvedAutomator_;
    }

    modifier onlyApprovedAutomator() {
        if (msg.sender != approvedAutomator) revert NotApprovedAutomator();
        _;
    }

    // Admin functions

    /// @notice Update approved automator address.
    /// @dev Controls which external address is allowed to
    /// compound farming positions for Sickles. This is expected to be the EOA
    /// of an automation bot.
    /// @custom:access Restricted to protocol admin.
    function setApprovedAutomator(
        address payable approvedAutomator_
    ) external onlyAdmin {
        approvedAutomator = approvedAutomator_;
        emit ApprovedAutomatorSet(approvedAutomator_);
    }

    // Automator functions

    function compoundFor(
        IAutomation[] memory strategies,
        Sickle[] memory sickles,
        CompoundParams[] memory params,
        address[][] memory sweepTokens
    ) external onlyApprovedAutomator {
        uint256 strategiesLength = strategies.length;
        if (
            strategiesLength != sickles.length
                || strategiesLength != params.length
                || strategiesLength != sweepTokens.length
        ) {
            revert InvalidInputLength();
        }

        address[] memory targets = new address[](strategiesLength);
        bytes[] memory data = new bytes[](strategiesLength);
        for (uint256 i; i < strategiesLength; i++) {
            Sickle sickle = sickles[i];
            CompoundParams memory param = params[i];
            targets[i] = address(strategies[i]);
            data[i] = abi.encodeCall(
                IAutomation.compoundFor, (sickle, param, sweepTokens[i])
            );
            emit CompoundedFor(
                sickle,
                param.claimFarm.stakingContract,
                param.claimFarm.poolIndex,
                param.depositFarm.stakingContract,
                param.depositFarm.poolIndex
            );
        }
        this.multicall(targets, data);
    }

    function harvestFor(
        IAutomation[] memory strategies,
        Sickle[] memory sickles,
        Farm[] memory farms,
        HarvestParams[] memory params,
        address[][] memory sweepTokens
    ) external onlyApprovedAutomator {
        uint256 strategiesLength = strategies.length;
        if (
            strategiesLength != sickles.length
                || strategiesLength != params.length
                || strategiesLength != sweepTokens.length
        ) {
            revert InvalidInputLength();
        }

        address[] memory targets = new address[](strategiesLength);
        bytes[] memory data = new bytes[](strategiesLength);
        for (uint256 i; i < strategiesLength; i++) {
            Sickle sickle = sickles[i];
            Farm memory farm = farms[i];
            HarvestParams memory param = params[i];
            targets[i] = address(strategies[i]);
            data[i] = abi.encodeCall(
                IAutomation.harvestFor, (sickle, farm, param, sweepTokens[i])
            );
            emit HarvestedFor(sickle, farm.stakingContract, farm.poolIndex);
        }
        this.multicall(targets, data);
    }

    function exitFor(
        IAutomation[] memory strategies,
        Sickle[] memory sickles,
        Farm[] memory farms,
        HarvestParams[] memory harvestParams,
        address[][] memory harvestSweepTokens,
        WithdrawParams[] memory withdrawParams,
        address[][] memory withdrawSweepTokens
    ) external onlyApprovedAutomator {
        uint256 strategiesLength = strategies.length;
        if (
            strategiesLength != sickles.length
                || strategiesLength != farms.length
                || strategiesLength != harvestParams.length
                || strategiesLength != withdrawParams.length
                || strategiesLength != harvestSweepTokens.length
                || strategiesLength != withdrawSweepTokens.length
        ) {
            revert InvalidInputLength();
        }

        address[] memory targets = new address[](strategiesLength);
        bytes[] memory data = new bytes[](strategiesLength);
        for (uint256 i; i < strategiesLength; i++) {
            targets[i] = address(strategies[i]);
            data[i] = abi.encodeCall(
                IAutomation.exitFor,
                (
                    sickles[i],
                    farms[i],
                    harvestParams[i],
                    harvestSweepTokens[i],
                    withdrawParams[i],
                    withdrawSweepTokens[i]
                )
            );
            emit ExitedFor(
                sickles[i], farms[i].stakingContract, farms[i].poolIndex
            );
        }
        this.multicall(targets, data);
    }

    // NFT Automator functions
    // Validation is done in the NftAutomation contract

    function harvestFor(
        INftAutomation[] memory strategies,
        Sickle[] memory sickles,
        NftPosition[] memory positions,
        NftHarvest[] memory params
    ) external onlyApprovedAutomator {
        uint256 strategiesLength = strategies.length;
        if (
            strategiesLength != sickles.length
                || strategiesLength != positions.length
                || strategiesLength != params.length
        ) {
            revert InvalidInputLength();
        }

        address[] memory targets = new address[](strategiesLength);
        bytes[] memory data = new bytes[](strategiesLength);
        for (uint256 i; i < strategiesLength; i++) {
            Sickle sickle = sickles[i];
            NftPosition memory position = positions[i];
            targets[i] = address(strategies[i]);
            data[i] = abi.encodeCall(
                INftAutomation.harvestFor, (sickle, position, params[i])
            );
            emit NftHarvestedFor(
                sickle, address(position.nft), position.tokenId
            );
        }
        this.multicall(targets, data);
    }

    function compoundFor(
        INftAutomation[] memory strategies,
        Sickle[] memory sickles,
        NftPosition[] memory positions,
        NftCompound[] memory params,
        bool[] memory inPlace,
        address[][] memory sweepTokens
    ) external onlyApprovedAutomator {
        uint256 strategiesLength = strategies.length;
        if (
            strategiesLength != sickles.length
                || strategiesLength != positions.length
                || strategiesLength != params.length
                || strategiesLength != sweepTokens.length
        ) {
            revert InvalidInputLength();
        }

        address[] memory targets = new address[](strategiesLength);
        bytes[] memory data = new bytes[](strategiesLength);
        for (uint256 i; i < strategiesLength; i++) {
            Sickle sickle = sickles[i];
            NftPosition memory position = positions[i];
            targets[i] = address(strategies[i]);
            data[i] = abi.encodeCall(
                INftAutomation.compoundFor,
                (sickle, position, params[i], inPlace[i], sweepTokens[i])
            );
            emit NftCompoundedFor(
                sickle, address(position.nft), position.tokenId
            );
        }
        this.multicall(targets, data);
    }

    function exitFor(
        INftAutomation[] memory strategies,
        Sickle[] memory sickles,
        NftPosition[] memory positions,
        NftHarvest[] memory harvestParams,
        NftWithdraw[] memory withdrawParams,
        address[][] memory sweepTokens
    ) external onlyApprovedAutomator {
        uint256 strategiesLength = strategies.length;
        if (
            strategiesLength != sickles.length
                || strategiesLength != positions.length
                || strategiesLength != harvestParams.length
                || strategiesLength != withdrawParams.length
                || strategiesLength != sweepTokens.length
        ) {
            revert InvalidInputLength();
        }

        address[] memory targets = new address[](strategiesLength);
        bytes[] memory data = new bytes[](strategiesLength);
        for (uint256 i; i < strategiesLength; i++) {
            Sickle sickle = sickles[i];
            NftPosition memory position = positions[i];
            targets[i] = address(strategies[i]);
            data[i] = abi.encodeCall(
                INftAutomation.exitFor,
                (
                    sickle,
                    position,
                    harvestParams[i],
                    withdrawParams[i],
                    sweepTokens[i]
                )
            );
            emit NftExitedFor(sickle, address(position.nft), position.tokenId);
        }
        this.multicall(targets, data);
    }

    function rebalanceFor(
        INftAutomation[] memory strategies,
        Sickle[] memory sickles,
        NftRebalance[] memory params,
        address[][] memory sweepTokens
    ) external onlyApprovedAutomator {
        uint256 strategiesLength = strategies.length;
        if (
            strategiesLength != sickles.length
                || strategiesLength != params.length
                || strategiesLength != sweepTokens.length
        ) {
            revert InvalidInputLength();
        }

        address[] memory targets = new address[](strategiesLength);
        bytes[] memory data = new bytes[](strategiesLength);
        for (uint256 i; i < strategiesLength; i++) {
            NftRebalance memory param = params[i];
            Sickle sickle = sickles[i];
            targets[i] = address(strategies[i]);
            data[i] = abi.encodeCall(
                INftAutomation.rebalanceFor, (sickle, param, sweepTokens[i])
            );
            emit NftRebalancedFor(
                sickle, address(param.position.nft), param.position.tokenId
            );
        }
        this.multicall(targets, data);
    }
}
