// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {NonReentrantVault} from "@src/utils/NonReentrantVault.sol";

/// @title CashStrategyVault
/// @custom:security-contact security@size.credit
/// @author Size (https://size.credit/)
/// @notice A strategy that only holds cash assets without investing in external protocols
contract CashStrategyVault is NonReentrantVault {}
