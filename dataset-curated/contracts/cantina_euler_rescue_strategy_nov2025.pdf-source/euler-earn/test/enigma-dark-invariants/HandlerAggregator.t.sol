// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Admin Handler contracts
import {EulerEarnAdminHandler} from "./handlers/admin/EulerEarnAdminHandler.t.sol";
import {PublicAllocatorAdminHandler} from "./handlers/admin/PublicAllocatorAdminHandler.t.sol";

// EVC Handler contracts
import {EVCHandler} from "./handlers/evc/EVCHandler.t.sol";

// EVK Modules Handler contracts
import {BorrowingModuleHandler} from "./handlers/evk/BorrowingModuleHandler.t.sol";
import {LiquidationModuleHandler} from "./handlers/evk/LiquidationModuleHandler.t.sol";
import {GovernanceModuleHandler} from "./handlers/evk/GovernanceModuleHandler.t.sol";

// User Handler contracts,
import {EulerEarnHandler} from "./handlers/user/EulerEarnHandler.t.sol";
import {PublicAllocatorHandler} from "./handlers/user/PublicAllocatorHandler.t.sol";

// Standard Handler contracts
import {ERC20Handler} from "./handlers/standard/ERC20Handler.t.sol";
import {ERC4626Handler} from "./handlers/standard/ERC4626Handler.t.sol";

// Simulator Handler contracts
import {DonationAttackHandler} from "./handlers/simulators/DonationAttackHandler.t.sol";
import {PriceOracleHandler} from "./handlers/simulators/PriceOracleHandler.t.sol";

// Postcondition Handler contracts
import {ERC4626PostconditionsHandler} from "./handlers/postconditions/ERC4626PostconditionsHandler.t.sol";

/// @notice Helper contract to aggregate all handler contracts, inherited in BaseInvariants
abstract contract HandlerAggregator is
    EulerEarnAdminHandler, // Admin handlers
    PublicAllocatorAdminHandler,
    EulerEarnHandler, // User handlers
    PublicAllocatorHandler,
    EVCHandler, // EVC handlers
    BorrowingModuleHandler, // EVK handlers
    LiquidationModuleHandler,
    GovernanceModuleHandler,
    ERC20Handler, // Standard handlers
    ERC4626Handler,
    DonationAttackHandler, // Simulator handlers
    PriceOracleHandler,
    ERC4626PostconditionsHandler // Postcondition handlers
{
    /// @notice Helper function in case any handler requires additional setup
    function _setUpHandlers() internal {}
}
