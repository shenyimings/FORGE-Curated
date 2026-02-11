// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

error InvalidArguments();
error DuplicateBridgeOperation();
error BridgeOperationNotFound();
error CantFinalizeOnSameBlock();
error NoPendingDepositRequest();
error NoPendingRedeemRequest();
error InsufficientShares();
error NotAuthorized();
error NotChainlinkOracle();
