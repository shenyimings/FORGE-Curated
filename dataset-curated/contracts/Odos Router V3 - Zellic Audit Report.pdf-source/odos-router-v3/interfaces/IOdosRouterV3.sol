// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/// @title V3 Routing contract interface for Odos SOR
/// @author Transaction Assembly
/// @notice Wrapper with security gaurentees around execution of arbitrary operations on user tokens
interface IOdosRouterV3 {

  /// @dev Contains all information needed to describe the input and output for a swap
  struct permit2Info {
    address contractAddress;
    uint256 nonce;
    uint256 deadline;
    bytes signature;
  }
  /// @dev Contains all information needed to describe the input and output for a swap
  struct swapTokenInfo {
    address inputToken;
    uint256 inputAmount;
    address inputReceiver;
    address outputToken;
    uint256 outputQuote;
    uint256 outputMin;
    address outputReceiver;
  }
  /// @dev Contains all information needed to describe an intput token for swapMulti
  struct inputTokenInfo {
    address tokenAddress;
    uint256 amountIn;
    address receiver;
  }
  /// @dev Contains all information needed to describe an output token for swapMulti
  struct outputTokenInfo {
    address tokenAddress;
    uint256 amountQuote;
    uint256 amountMin;
    address receiver;
  }
  /// @dev Holds all information for a given referral
  struct swapReferralInfo {
    uint64 code;
    uint64 fee;
    address feeRecipient;
  }
  /// @dev Event emitted on changing the liquidator address
  event LiquidatorAddressChanged(address indexed account);

  // @dev event for swapping one token for another
  event Swap(
    address sender,
    uint256 inputAmount,
    address inputToken,
    uint256 amountOut,
    address outputToken,
    int256 slippage,
    uint64 referralCode,
    uint64 referralFee,
    address referralFeeRecipient
  );
  /// @dev event for swapping multiple input and/or output tokens
  event SwapMulti(
    address sender,
    uint256[] amountsIn,
    address[] tokensIn,
    uint256[] amountsOut,
    address[] tokensOut,
    int256[] slippage,
    uint64 referralCode,
    uint64 referralFee,
    address referralFeeRecipient
  );

  function swapCompact() external payable returns (uint256);

  function swap(
    swapTokenInfo memory tokenInfo,
    bytes calldata pathDefinition,
    address executor,
    swapReferralInfo memory referralInfo
  )
    external payable returns (uint256 amountOut);

  function swapPermit2(
  	permit2Info memory permit2,
    swapTokenInfo memory tokenInfo,
    bytes calldata pathDefinition,
    address executor,
    swapReferralInfo memory referralInfo
  )
    external returns (uint256 amountOut);

  function swapMultiCompact() external payable returns (uint256[] memory amountsOut);

  function swapMulti(
    inputTokenInfo[] memory inputs,
    outputTokenInfo[] memory outputs,
    bytes calldata pathDefinition,
    address executor,
    swapReferralInfo memory referralInfo
  )
    external payable returns (uint256[] memory amountsOut);

  function swapMultiPermit2(
    permit2Info memory permit2,
    inputTokenInfo[] memory inputs,
    outputTokenInfo[] memory outputs,
    bytes calldata pathDefinition,
    address executor,
    swapReferralInfo memory referralInfo
  )
    external payable returns (uint256[] memory amountsOut);

  function changeLiquidatorAddress(address account)
    external;

  function writeAddressList(
    address[] calldata addresses
  ) 
    external;

  function transferRouterFunds(
    address[] calldata tokens,
    uint256[] calldata amounts,
    address dest
  )
    external;

  function swapRouterFunds(
    inputTokenInfo[] memory inputs,
    outputTokenInfo[] memory outputs,
    bytes calldata pathDefinition,
    address executor
  )
    external
    returns (uint256[] memory amountsOut);
}