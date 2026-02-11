// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6 <0.9;

library EmergencyPause {
    enum Level {
        // Pause is not active.
        NONE,
        // Prevent starting mint, redeem, liquidation and core vault transfer/return.
        START_OPERATIONS,
        // Everything from START_OPERATIONS, plus prevent finishing or defulating already started mints and redeems.
        FULL,
        // Everything from FULL, plus prevent FAsset transfers.
        FULL_AND_TRANSFER
    }
}
