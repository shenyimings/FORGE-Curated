// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Interfaces
import {IERC4626, IERC20} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {IEulerEarn} from "src/interfaces/IEulerEarn.sol";
import {IEulerEarnAdminHandler} from "../interfaces/IEulerEarnAdminHandler.sol";

// Libraries
import "forge-std/console.sol";

// Test Contracts
import {BaseHandler} from "../../base/BaseHandler.t.sol";

/// @title EulerEarnAdminHandler
/// @notice Handler test contract for a set of actions
abstract contract EulerEarnAdminHandler is IEulerEarnAdminHandler, BaseHandler {
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                      STATE VARIABLES                                      //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                          SUBMIT                                           //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function submitTimelock(uint256 _newTimelock, uint8 i) external directCallCleanup {
        target = _getRandomEulerEarnVault(i);

        _before();
        IEulerEarn(target).submitTimelock(_newTimelock);
        _after();
    }

    function setFee(uint256 _newTimelock, uint8 i) external directCallCleanup {
        target = _getRandomEulerEarnVault(i);

        _before();
        IEulerEarn(target).setFee(_newTimelock);
        _after();
    }

    function setFeeRecipient(bool zeroFeeRecipient, uint8 i) external directCallCleanup {
        target = _getRandomEulerEarnVault(i);
        address newFeeRecipient = zeroFeeRecipient ? address(0) : address(FEE_RECIPIENT);
        _before();
        IEulerEarn(target).setFeeRecipient(newFeeRecipient);
        _after();
    }

    function submitCap(uint256 _newSupplyCap, uint8 i, uint8 j) external directCallCleanup {
        target = _getRandomEulerEarnVault(i);

        IERC4626 market = _getRandomMarket(target, j);

        _before();
        IEulerEarn(target).submitCap(market, _newSupplyCap);
        _after();
    }

    function submitMarketRemoval(uint8 i, uint8 j) external directCallCleanup {
        target = _getRandomEulerEarnVault(i);

        IERC4626 market = _getRandomMarket(target, j);

        _before();
        IEulerEarn(target).submitMarketRemoval(market);
        _after();
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                          REVOKE                                           //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function revokePendingTimelock(uint8 i) external directCallCleanup {
        target = _getRandomEulerEarnVault(i);

        _before();
        IEulerEarn(target).revokePendingTimelock();
        _after();
    }

    function revokePendingCap(uint8 i, uint8 j) external directCallCleanup {
        target = _getRandomEulerEarnVault(i);
        IERC4626 market = _getRandomMarket(target, j);

        _before();
        IEulerEarn(target).revokePendingCap(market);
        _after();
    }

    function revokePendingMarketRemoval(uint8 i, uint8 j) external directCallCleanup {
        target = _getRandomEulerEarnVault(i);
        IERC4626 market = _getRandomMarket(target, j);

        _before();
        IEulerEarn(target).revokePendingMarketRemoval(market);
        _after();
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                          EXTERNAL                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function acceptTimelock(uint8 i) external directCallCleanup {
        target = _getRandomEulerEarnVault(i);

        _before();
        IEulerEarn(target).acceptTimelock();
        _after();
    }

    function acceptCap(uint8 i, uint8 j) external directCallCleanup {
        target = _getRandomEulerEarnVault(i);

        IERC4626 market = _getRandomMarket(target, j);

        _before();
        IEulerEarn(target).acceptCap(market);
        _after();
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                          ALLOCATOR                                        //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function setSupplyQueue(uint8 i, uint8 j) external {
        // Get a random EulerEarn vault
        target = _getRandomEulerEarnVault(i);

        // Generate a random market array
        IERC4626[] memory _newSupplyQueue = _generateRandomMarketArray(j, target);

        IEulerEarn(target).setSupplyQueue(_newSupplyQueue);

        uint256 supplyQueueLength = IEulerEarn(target).supplyQueueLength();

        // HSPOST

        /// @dev QUEUES
        for (uint256 k; k < supplyQueueLength; k++) {
            assertGt(IEulerEarn(target).config(IEulerEarn(target).supplyQueue(k)).cap, 0, HSPOST_QUEUES_F);
        }
    }

    function updateWithdrawQueue(uint8[MAX_NUM_MARKETS] memory _indexes, uint8 i, uint8 j) external {
        // Get a random EulerEarn vault
        target = _getRandomEulerEarnVault(i);

        // Clamp the indexes
        uint256[] memory _clampedIndexes = _clampIndexesArray(_indexes, j, target);

        // Update the withdraw queue
        IEulerEarn(target).updateWithdrawQueue(_clampedIndexes);
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                          HELPERS                                          //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function _generateRandomMarketArray(uint8 seed, address _target) internal returns (IERC4626[] memory randomArray) {
        // First, create array of non-idleVault markets
        uint256 nonIdleCount = allMarkets[_target].length - 1;
        IERC4626[] memory nonIdleMarkets = new IERC4626[](nonIdleCount);

        for (uint256 i = 0; i < nonIdleCount; i++) {
            nonIdleMarkets[i] = allMarkets[_target][i];
        }

        // Determine how many non-idle markets to select (max available)
        uint256 randomLength = clampLe(seed, nonIdleCount);

        randomArray = new IERC4626[](randomLength + 1); // +1 for idleVault

        // Select from non-idle markets only
        for (uint256 i = 0; i < randomLength; i++) {
            randomArray[i] = nonIdleMarkets[(uint256(seed) + i) % nonIdleCount];
        }

        // Always add idleVault at the end
        randomArray[randomLength] = IERC4626(address(allMarkets[_target][nonIdleCount]));

        assert(randomArray.length <= allMarkets[_target].length);
    }

    function _clampIndexesArray(uint8[MAX_NUM_MARKETS] memory _indexes, uint8 indexesLengthSeed, address _target)
        internal
        returns (uint256[] memory clampedIndexes)
    {
        uint256 withdrawalQueueLength = IEulerEarn(_target).withdrawQueueLength();
        assertLe(
            withdrawalQueueLength,
            MAX_NUM_MARKETS,
            "PublicAllocatorHandler: withdrawalQueueLength exceeds MAX_NUM_MARKETS"
        );

        uint256 clampedIndexesLength = clampGe(indexesLengthSeed % (withdrawalQueueLength), 1);

        clampedIndexes = new uint256[](clampedIndexesLength);

        for (uint256 i; i < clampedIndexesLength; i++) {
            clampedIndexes[i] = clampLt(_indexes[i], allMarkets[_target].length);
        }
    }
}
