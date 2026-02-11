// SPDX-FileCopyrightText: 2024 Lido <info@lido.fi>
// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {AssetRecoverer} from "../AssetRecoverer.sol";

/**
 * @title Test contract for AssetRecoverer functionality.
 */
contract AssetRecovererTest is AssetRecoverer {
    // ==================== Constructor ====================

    /**
     * @notice Initializes the test contract.
     * @param agent_ Agent address.
     * @param manager_ Manager address.
     */
    constructor(address agent_, address manager_) AssetRecoverer(agent_) {
        manager = manager_;
    }
}
