// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import { BootloaderAuth } from "./BootloaderAuth.sol";
import { SelfAuth } from "./SelfAuth.sol";
import { HookAuth } from "./HookAuth.sol";
import { Errors } from "../libraries/Errors.sol";

/**
 * @title Auth
 * @notice Abstract contract that organizes authentication logic for the contract
 * @author https://getclave.io
 */
abstract contract Auth is BootloaderAuth, SelfAuth, HookAuth {}
