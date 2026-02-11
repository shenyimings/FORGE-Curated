// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IIntentSource} from "./IIntentSource.sol";
import {IInbox} from "./IInbox.sol";

/**
 * @title IPortal
 * @notice Interface for the unified Portal contract following the new specification
 * @dev Combines source chain operations (publish, fund, refund, withdraw) and
 *      destination chain operations (fulfill, prove) in a single interface
 */
// solhint-disable-next-line no-empty-blocks
interface IPortal is IIntentSource, IInbox {}
