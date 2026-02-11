// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {IProtocolAdapter} from "./IProtocolAdapter.sol";
import {IERC20, IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IERC4626Adapter is IProtocolAdapter {}
