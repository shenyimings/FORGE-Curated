// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0;

error NotAuthorized(address operator, address user);
error Unauthorized(address caller);
error UnauthorizedLendingMarketTransfer(address from, address to, uint256 value);
error InsufficientYieldTokenBalance();
error InsufficientAssetsForRepayment(uint256 assetsToRepay, uint256 assetsWithdrawn);
error CannotLiquidate(uint256 maxLiquidateShares, uint256 seizedAssets);
error CannotLiquidateZeroShares();
error Paused();
error CannotExitPositionWithinCooldownPeriod();
error CannotTokenizeWithdrawRequest();
error CurrentAccountAlreadySet();
error InvalidVault(address vault);

error WithdrawRequestNotFinalized(uint256 requestId);
error CannotInitiateWithdraw(address account);
error CannotForceWithdraw(address account);
error InsufficientSharesHeld();
error SlippageTooHigh(uint256 actualTokensOut, uint256 minTokensOut);

error CannotEnterPosition();
error NoExistingPosition();
error LiquidatorHasPosition();
error InvalidUpgrade();
error InvalidInitialization();
error InvalidLendingRouter();

error ExistingWithdrawRequest(address vault, address account, uint256 requestId);
error NoWithdrawRequest(address vault, address account);
error InvalidWithdrawRequestTokenization();

error InvalidPrice(uint256 oraclePrice, uint256 spotPrice);
error PoolShareTooHigh(uint256 poolClaim, uint256 maxSupplyThreshold);
error AssetRemaining(uint256 assetRemaining);