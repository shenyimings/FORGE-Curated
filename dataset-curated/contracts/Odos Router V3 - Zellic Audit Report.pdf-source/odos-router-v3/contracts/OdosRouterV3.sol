// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../interfaces/IOdosRouterV3.sol";
import "../interfaces/IOdosExecutor.sol";
import "../interfaces/IOdosHook.sol";
import "../interfaces/ISignatureTransfer.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";

/// @title V3 Routing contract for Odos SOR
/// @author Transaction Assembly
/// @notice Wrapper with security gaurentees around execution of arbitrary operations on user tokens
contract OdosRouterV3 is IOdosRouterV3, Ownable2Step {
  using SafeERC20 for IERC20;

  /// @dev The zero address is uniquely used to represent eth since it is already
  /// recognized as an invalid ERC20, and due to its gas efficiency
  address constant _ETH = address(0);

  /// @dev Address list where addresses can be cached for use when reading from storage is cheaper
  // than reading from calldata. addressListStart is the storage slot of the first dynamic array element
  uint256 private constant addressListStart = 
    29102676481673041902632991033461445430619272659676223336789171408008386403022;
  address[] public addressList;

  /// @dev Address which can access and liquidate funds held in the router
  address public liquidatorAddress;

  // @dev constant for the fee precision
  uint256 public constant FEE_DENOM = 1e18;

  constructor(address owner) Ownable(owner) { }

  /// @dev Must exist in order for contract to receive eth
  receive() external payable { }

  /// @notice Custom decoder to swap with compact calldata for efficient execution on L2s
  function swapCompact() 
    external
    payable
    returns (uint256)
  {
    swapTokenInfo memory tokenInfo;
    swapReferralInfo memory referralInfo;

    address executor;
    bytes calldata pathDefinition;
    {
      assembly {
        // Define function to load in token address, either from calldata or from storage
        function getAddress(currPos) -> result, newPos {
          let inputPos := shr(240, calldataload(currPos))

          switch inputPos
          // Reserve the null address as a special case that can be specified with 2 null bytes
          case 0x0000 {
            newPos := add(currPos, 2)
          }
          // This case means that the address is encoded in the calldata directly following the code
          case 0x0001 {
            result := and(shr(80, calldataload(currPos)), 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
            newPos := add(currPos, 22)
          }
          // Otherwise we use the case to load in from the cached address list
          default {
            result := sload(add(addressListStart, sub(inputPos, 2)))
            newPos := add(currPos, 2)
          }
        }
        let result := 0
        let pos := 4

        // Load in the input and output token addresses
        result, pos := getAddress(pos)
        mstore(tokenInfo, result)

        result, pos := getAddress(pos)
        mstore(add(tokenInfo, 0x60), result)

        // Load in the input amount - a 0 byte means the full balance is to be used
        let inputAmountLength := shr(248, calldataload(pos))
        pos := add(pos, 1)

        if inputAmountLength {
          mstore(add(tokenInfo, 0x20), shr(mul(sub(32, inputAmountLength), 8), calldataload(pos)))
          pos := add(pos, inputAmountLength)
        }

        // Load in the quoted output amount
        let quoteAmountLength := shr(248, calldataload(pos))
        pos := add(pos, 1)

        let outputQuote := shr(mul(sub(32, quoteAmountLength), 8), calldataload(pos))
        mstore(add(tokenInfo, 0x80), outputQuote)
        pos := add(pos, quoteAmountLength)

        // Load the slippage tolerance and use to get the minimum output amount
        {
          let slippageTolerance := shr(232, calldataload(pos))
          mstore(add(tokenInfo, 0xA0), div(mul(outputQuote, sub(0xFFFFFF, slippageTolerance)), 0xFFFFFF))
        }
        pos := add(pos, 3)

        // Load in the executor address
        executor, pos := getAddress(pos)

        // Load in the destination to send the input to - Zero denotes the executor
        result, pos := getAddress(pos)
        if eq(result, 0) { result := executor }
        mstore(add(tokenInfo, 0x40), result)

        // Load in the destination to send the output to - Zero denotes msg.sender
        result, pos := getAddress(pos)
        mstore(add(tokenInfo, 0xC0), result)

        let referralCode := shr(192, calldataload(pos))
        pos := add(pos, 8)
        mstore(referralInfo, referralCode)

        let feeStatus := shr(248, calldataload(pos))
        pos := add(pos, 1)

        if feeStatus {
          let referralFee := shr(192, calldataload(pos))
          pos := add(pos, 8)
          mstore(add(referralInfo, 0x20), referralFee)

          let referralBeneficiary := shr(96, calldataload(pos))
          pos := add(pos, 20)
          mstore(add(referralInfo, 0x40), referralBeneficiary)
        }

        // Set the offset and size for the pathDefinition portion of the msg.data
        pathDefinition.length := mul(shr(248, calldataload(pos)), 32)
        pathDefinition.offset := add(pos, 1)
      }
    }
    return _swapApproval(
      tokenInfo,
      pathDefinition,
      executor,
      referralInfo
    );
  }

  /// @notice Externally facing interface for swapping two tokens
  /// @param tokenInfo All information about the tokens being swapped
  /// @param pathDefinition Encoded path definition for executor
  /// @param executor Address of contract that will execute the path
  /// @param referralInfo referral info to specify the source of and fee for the swap
  function swap(
    swapTokenInfo memory tokenInfo,
    bytes calldata pathDefinition,
    address executor,
    swapReferralInfo memory referralInfo
  )
    external
    payable
    returns (uint256 amountOut)
  {
    return _swapApproval(
      tokenInfo,
      pathDefinition,
      executor,
      referralInfo
    );
  }

  /// @notice Externally facing interface for swapping two tokens with a call at the end
  /// @param tokenInfo All information about the tokens being swapped
  /// @param pathDefinition Encoded path definition for executor
  /// @param executor Address of contract that will execute the path
  /// @param referralInfo referral info to specify the source of and fee for the swap
  /// @param hookTarget the target address to call the hook on
  /// @param hookData encoded data for a call to the hookTarget after the swap
  function swapWithHook(
    swapTokenInfo memory tokenInfo,
    bytes calldata pathDefinition,
    address executor,
    swapReferralInfo memory referralInfo,
    address hookTarget,
    bytes calldata hookData
  )
    external
    payable
    returns (uint256 amountOut)
  {
    amountOut = _swapApproval(
      tokenInfo,
      pathDefinition,
      executor,
      referralInfo
    );
    uint256[] memory hookAmountsIn = new uint256[](1);
    hookAmountsIn[0] = amountOut;

    IOdosHook(hookTarget).executeOdosHook(
      hookData, 
      hookAmountsIn,
      msg.sender
    );
  }

  /// @notice Internal function for initiating approval transfers
  /// @param tokenInfo All information about the tokens being swapped
  /// @param pathDefinition Encoded path definition for executor
  /// @param executor Address of contract that will execute the path
  /// @param referralInfo referral info to specify the source of and fee for the swap
  function _swapApproval(
    swapTokenInfo memory tokenInfo,
    bytes calldata pathDefinition,
    address executor,
    swapReferralInfo memory referralInfo
  )
    internal
    returns (uint256 amountOut)
  {
    if (tokenInfo.inputToken == _ETH) {
      // Support rebasing tokens by allowing the user to trade the entire balance
      if (tokenInfo.inputAmount == 0) {
        tokenInfo.inputAmount = msg.value;
      } else {
        require(msg.value == tokenInfo.inputAmount, "Wrong msg.value");
      }
    }
    else {
      require(msg.value == 0, "Wrong msg.value");

      // Support rebasing tokens by allowing the user to trade the entire balance
      if (tokenInfo.inputAmount == 0) {
        tokenInfo.inputAmount = IERC20(tokenInfo.inputToken).balanceOf(msg.sender);
      }
      IERC20(tokenInfo.inputToken).safeTransferFrom(
        msg.sender,
        tokenInfo.inputReceiver,
        tokenInfo.inputAmount
      );
    }
    return _swap(
      tokenInfo,
      pathDefinition,
      executor,
      referralInfo
    );
  }

  /// @notice Externally facing interface for swapping two tokens
  /// @param permit2 All additional info for Permit2 transfers
  /// @param tokenInfo All information about the tokens being swapped
  /// @param pathDefinition Encoded path definition for executor
  /// @param executor Address of contract that will execute the path
  /// @param referralInfo referral info to specify the source of and fee for the swap
  function swapPermit2(
    permit2Info memory permit2,
    swapTokenInfo memory tokenInfo,
    bytes calldata pathDefinition,
    address executor,
    swapReferralInfo memory referralInfo
  )
    external
    returns (uint256 amountOut)
  {
    return _swapPermit2(
      permit2,
      tokenInfo,
      pathDefinition,
      executor,
      referralInfo
    );
  }

  /// @notice Externally facing interface for swapping two tokens
  /// @param permit2 All additional info for Permit2 transfers
  /// @param tokenInfo All information about the tokens being swapped
  /// @param pathDefinition Encoded path definition for executor
  /// @param executor Address of contract that will execute the path
  /// @param referralInfo referral info to specify the source of and fee for the swap
  /// @param hookTarget the target address to call the hook on
  /// @param hookData encoded data for a call to the hookTarget after the swap
  function swapPermit2WithHook(
    permit2Info memory permit2,
    swapTokenInfo memory tokenInfo,
    bytes calldata pathDefinition,
    address executor,
    swapReferralInfo memory referralInfo,
    address hookTarget,
    bytes calldata hookData
  )
    external
    returns (uint256 amountOut)
  {
    amountOut = _swapPermit2(
      permit2,
      tokenInfo,
      pathDefinition,
      executor,
      referralInfo
    );
    uint256[] memory hookAmountsIn = new uint256[](1);
    hookAmountsIn[0] = amountOut;

    IOdosHook(hookTarget).executeOdosHook(
      hookData, 
      hookAmountsIn,
      msg.sender
    );
  }

  /// @notice Internal function for using permit2 before a swap
  /// @param permit2 All additional info for Permit2 transfers
  /// @param tokenInfo All information about the tokens being swapped
  /// @param pathDefinition Encoded path definition for executor
  /// @param executor Address of contract that will execute the path
  /// @param referralInfo referral info to specify the source of and fee for the swap
  function _swapPermit2(
    permit2Info memory permit2,
    swapTokenInfo memory tokenInfo,
    bytes calldata pathDefinition,
    address executor,
    swapReferralInfo memory referralInfo
  )
    internal
    returns (uint256 amountOut)
  {
    ISignatureTransfer(permit2.contractAddress).permitTransferFrom(
      ISignatureTransfer.PermitTransferFrom(
        ISignatureTransfer.TokenPermissions(
          tokenInfo.inputToken,
          tokenInfo.inputAmount
        ),
        permit2.nonce,
        permit2.deadline
      ),
      ISignatureTransfer.SignatureTransferDetails(
        tokenInfo.inputReceiver,
        tokenInfo.inputAmount
      ),
      msg.sender,
      permit2.signature
    );
    return _swap(
      tokenInfo,
      pathDefinition,
      executor,
      referralInfo
    );
  }

  /// @notice contains the main logic for swapping one token for another
  /// Assumes input tokens have already been sent to their destinations and
  /// that msg.value is set to expected ETH input value, or 0 for ERC20 input
  /// @param tokenInfo All information about the tokens being swapped
  /// @param pathDefinition Encoded path definition for executor
  /// @param executor Address of contract that will execute the path
  /// @param referralInfo referral info to specify the source of and fee for the swap
  function _swap(
    swapTokenInfo memory tokenInfo,
    bytes calldata pathDefinition,
    address executor,
    swapReferralInfo memory referralInfo
  )
    internal
    returns (uint256 amountOut)
  {
    // Check for valid output specifications
    require(tokenInfo.outputMin <= tokenInfo.outputQuote, "Minimum greater than quote");
    require(tokenInfo.outputMin > 0, "Minimum output is zero");
    require(tokenInfo.inputToken != tokenInfo.outputToken, "Arbitrage not supported");

    uint256 balanceBefore = _universalBalance(tokenInfo.outputToken);

    // Delegate the execution of the path to the specified Odos Executor
    uint256[] memory amountsIn = new uint256[](1);
    amountsIn[0] = tokenInfo.inputAmount;

    IOdosExecutor(executor).executePath{value: msg.value}(pathDefinition, amountsIn, msg.sender);

    amountOut = _universalBalance(tokenInfo.outputToken) - balanceBefore;

    if (referralInfo.fee > 0) {
      require(referralInfo.feeRecipient != address(0), "Null fee recipient");
      require(referralInfo.fee <= FEE_DENOM / 50, "Fee too high");

      uint256 splitBPS = (referralInfo.code >> 32) & 65535;
      if (splitBPS == 0) splitBPS = 8000;
      require(splitBPS <= 10000, "Invalid Ref Code");

      if (referralInfo.feeRecipient != address(this)) {
        _universalTransfer(
          tokenInfo.outputToken,
          referralInfo.feeRecipient,
          amountOut * referralInfo.fee * splitBPS / (FEE_DENOM * 10000)
        );
      }
      amountOut = amountOut * (FEE_DENOM - referralInfo.fee) / FEE_DENOM;
    }
    int256 slippage = int256(amountOut) - int256(tokenInfo.outputQuote);
    if (slippage > 0 && (referralInfo.code >> 48) & 1 == 0) {
      amountOut = tokenInfo.outputQuote;
    }
    require(amountOut >= tokenInfo.outputMin, "Slippage Limit Exceeded");

    // Transfer out the final output to the end user
    _universalTransfer(
      tokenInfo.outputToken, 
      tokenInfo.outputReceiver == address(0) ? msg.sender : tokenInfo.outputReceiver, 
      amountOut
    );
    emit Swap(
      msg.sender,
      tokenInfo.inputAmount,
      tokenInfo.inputToken,
      amountOut,
      tokenInfo.outputToken,
      slippage,
      referralInfo.code,
      referralInfo.fee,
      referralInfo.feeRecipient
    );
  }

  /// @notice Custom decoder to swapMulti with compact calldata for efficient execution on L2s
  function swapMultiCompact() 
    external
    payable
    returns (uint256[] memory amountsOut)
  {
    address executor;

    inputTokenInfo[] memory inputs;
    outputTokenInfo[] memory outputs;

    uint256 pos = 6;
    {
      uint256 numInputs;
      uint256 numOutputs;

      assembly {
        numInputs := shr(248, calldataload(4))
        numOutputs := shr(248, calldataload(5))
      }
      inputs = new inputTokenInfo[](numInputs);
      outputs = new outputTokenInfo[](numOutputs);

      assembly {
        // Define function to load in token address, either from calldata or from storage
        function getAddress(currPos) -> result, newPos {
          let inputPos := shr(240, calldataload(currPos))

          switch inputPos
          // Reserve the null address as a special case that can be specified with 2 null bytes
          case 0x0000 {
            newPos := add(currPos, 2)
          }
          // This case means that the address is encoded in the calldata directly following the code
          case 0x0001 {
            result := and(shr(80, calldataload(currPos)), 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
            newPos := add(currPos, 22)
          }
          // Otherwise we use the case to load in from the cached address list
          default {
            result := sload(add(addressListStart, sub(inputPos, 2)))
            newPos := add(currPos, 2)
          }
        }
        executor, pos := getAddress(pos)

        let slippageTolerance := shr(232, calldataload(pos))
        pos := add(pos, 3)

        let result := 0
        let memPos := 0

        for { let element := 0 } lt(element, numInputs) { element := add(element, 1) }
        {
          memPos := mload(add(inputs, add(mul(element, 0x20), 0x20)))

          // Load in the token address
          result, pos := getAddress(pos)
          mstore(memPos, result)

          // Load in the input amount - a 0 byte means the full balance is to be used
          let inputAmountLength := shr(248, calldataload(pos))
          pos := add(pos, 1)

          if inputAmountLength {
             mstore(add(memPos, 0x20), shr(mul(sub(32, inputAmountLength), 8), calldataload(pos)))
            pos := add(pos, inputAmountLength)
          }
          result, pos := getAddress(pos)
          if eq(result, 0) { result := executor }

          mstore(add(memPos, 0x40), result)
        }
        for { let element := 0 } lt(element, numOutputs) { element := add(element, 1) }
        {
          memPos := mload(add(outputs, add(mul(element, 0x20), 0x20)))

          // Load in the token address
          result, pos := getAddress(pos)
          mstore(memPos, result)

          // Load in the quoted output amount
          let outputAmountLength := shr(248, calldataload(pos))
          pos := add(pos, 1)

          let outputQuote := shr(mul(sub(32, outputAmountLength), 8), calldataload(pos))
          mstore(add(memPos, 0x20), outputQuote)
          pos := add(pos, outputAmountLength)

          // Set the minimum output amount as quote with slippage limit applied
          mstore(add(memPos, 0x40), div(mul(outputQuote, sub(0xFFFFFF, slippageTolerance)), 0xFFFFFF))

          result, pos := getAddress(pos)

          mstore(add(memPos, 0x60), result)
        }
      }
    }
    swapReferralInfo memory referralInfo;
    bytes calldata pathDefinition;

    assembly {
      let referralCode := shr(192, calldataload(pos))
      pos := add(pos, 8)
      mstore(referralInfo, referralCode)

      let feeStatus := shr(248, calldataload(pos))
      pos := add(pos, 1)

      if feeStatus {
        let referralFee := shr(192, calldataload(pos))
        pos := add(pos, 8)
        mstore(add(referralInfo, 0x20), referralFee)

        let referralBeneficiary := shr(96, calldataload(pos))
        pos := add(pos, 20)
        mstore(add(referralInfo, 0x40), referralBeneficiary)
      }

      // Set the offset and size for the pathDefinition portion of the msg.data
      pathDefinition.length := mul(shr(248, calldataload(pos)), 32)
      pathDefinition.offset := add(pos, 1)
    }
    return _swapMultiApproval(
      inputs,
      outputs,
      pathDefinition,
      executor,
      referralInfo
    );
  }

  /// @notice Externally facing interface for swapping between two sets of tokens
  /// @param inputs list of input token structs for the path being executed
  /// @param outputs list of output token structs for the path being executed
  /// @param pathDefinition Encoded path definition for executor
  /// @param executor Address of contract that will execute the path
  /// @param referralInfo referral info to specify the source of and fee for the swap
  function swapMulti(
    inputTokenInfo[] memory inputs,
    outputTokenInfo[] memory outputs,
    bytes calldata pathDefinition,
    address executor,
    swapReferralInfo memory referralInfo
  )
    external
    payable
    returns (uint256[] memory amountsOut)
  {
    return _swapMultiApproval(
      inputs,
      outputs,
      pathDefinition,
      executor,
      referralInfo
    );
  }

  /// @notice Externally facing interface for swapping between two sets of tokens with a hook
  /// @param inputs list of input token structs for the path being executed
  /// @param outputs list of output token structs for the path being executed
  /// @param pathDefinition Encoded path definition for executor
  /// @param executor Address of contract that will execute the path
  /// @param referralInfo referral info to specify the source of and fee for the swap
  /// @param hookTarget the target address to call the hook on
  /// @param hookData encoded data for a call to the hookTarget after the swap
  function swapMultiWithHook(
    inputTokenInfo[] memory inputs,
    outputTokenInfo[] memory outputs,
    bytes calldata pathDefinition,
    address executor,
    swapReferralInfo memory referralInfo,
    address hookTarget,
    bytes calldata hookData
  )
    external
    payable
    returns (uint256[] memory amountsOut)
  {
    amountsOut = _swapMultiApproval(
      inputs,
      outputs,
      pathDefinition,
      executor,
      referralInfo
    );
    IOdosHook(hookTarget).executeOdosHook(
      hookData,
      amountsOut,
      msg.sender
    );
  }

  /// @notice Internal logic for swapping between two sets of tokens with approvals
  /// @param inputs list of input token structs for the path being executed
  /// @param outputs list of output token structs for the path being executed
  /// @param pathDefinition Encoded path definition for executor
  /// @param executor Address of contract that will execute the path
  /// @param referralInfo referral info to specify the source of and fee for the swap
  function _swapMultiApproval(
    inputTokenInfo[] memory inputs,
    outputTokenInfo[] memory outputs,
    bytes calldata pathDefinition,
    address executor,
    swapReferralInfo memory referralInfo
  )
    internal
    returns (uint256[] memory amountsOut)
  {
    // If input amount is still 0 then that means the maximum possible input is to be used
    uint256 expected_msg_value = 0;

    for (uint256 i = 0; i < inputs.length; i++) {
      if (inputs[i].tokenAddress == _ETH) {
        if (inputs[i].amountIn == 0) {
          inputs[i].amountIn = msg.value;
        }
        expected_msg_value = inputs[i].amountIn;
      } 
      else {
        if (inputs[i].amountIn == 0) {
          inputs[i].amountIn = IERC20(inputs[i].tokenAddress).balanceOf(msg.sender);
        }
        IERC20(inputs[i].tokenAddress).safeTransferFrom(
          msg.sender,
          inputs[i].receiver,
          inputs[i].amountIn
        );
      }
    }
    require(msg.value == expected_msg_value, "Wrong msg.value");

    return _swapMulti(
      inputs,
      outputs,
      pathDefinition,
      executor,
      referralInfo
    );
  }

  /// @notice Externally facing function for swapping between two sets of tokens with Permit2
  /// @param permit2 All additional info for Permit2 transfers
  /// @param inputs list of input token structs for the path being executed
  /// @param outputs list of output token structs for the path being executed
  /// @param pathDefinition Encoded path definition for executor
  /// @param executor Address of contract that will execute the path
  /// @param referralInfo referral info to specify the source of and fee for the swap
  function swapMultiPermit2(
    permit2Info memory permit2,
    inputTokenInfo[] memory inputs,
    outputTokenInfo[] memory outputs,
    bytes calldata pathDefinition,
    address executor,
    swapReferralInfo memory referralInfo
  )
    external
    payable
    returns (uint256[] memory amountsOut)
  {
    return _swapMultiPermit2(
      permit2,
      inputs,
      outputs,
      pathDefinition,
      executor,
      referralInfo
    );
  }

  /// @notice Externally facing function for swapping between two sets of tokens with Permit2 with a hook
  /// @param permit2 All additional info for Permit2 transfers
  /// @param inputs list of input token structs for the path being executed
  /// @param outputs list of output token structs for the path being executed
  /// @param pathDefinition Encoded path definition for executor
  /// @param executor Address of contract that will execute the path
  /// @param referralInfo referral info to specify the source of and fee for the swap
  /// @param hookTarget the target address to call the hook on
  /// @param hookData encoded data for a call to the hookTarget after the swap
  function swapMultiPermit2WithHook(
    permit2Info memory permit2,
    inputTokenInfo[] memory inputs,
    outputTokenInfo[] memory outputs,
    bytes calldata pathDefinition,
    address executor,
    swapReferralInfo memory referralInfo,
    address hookTarget,
    bytes calldata hookData
  )
    external
    payable
    returns (uint256[] memory amountsOut)
  {
    amountsOut = _swapMultiPermit2(
      permit2,
      inputs,
      outputs,
      pathDefinition,
      executor,
      referralInfo
    );
    IOdosHook(hookTarget).executeOdosHook(
      hookData,
      amountsOut,
      msg.sender
    );
  }

  /// @notice Internal function for approcing with premit2 before swapping multiple tokens
  /// @param permit2 All additional info for Permit2 transfers
  /// @param inputs list of input token structs for the path being executed
  /// @param outputs list of output token structs for the path being executed
  /// @param pathDefinition Encoded path definition for executor
  /// @param executor Address of contract that will execute the path
  /// @param referralInfo referral info to specify the source of and fee for the swap
  function _swapMultiPermit2(
    permit2Info memory permit2,
    inputTokenInfo[] memory inputs,
    outputTokenInfo[] memory outputs,
    bytes calldata pathDefinition,
    address executor,
    swapReferralInfo memory referralInfo
  )
    internal
    returns (uint256[] memory amountsOut)
  {
    ISignatureTransfer.PermitBatchTransferFrom memory permit;
    ISignatureTransfer.SignatureTransferDetails[] memory transferDetails;
    {
      uint256 permit_length = msg.value > 0 ? inputs.length - 1 : inputs.length;

      permit = ISignatureTransfer.PermitBatchTransferFrom(
        new ISignatureTransfer.TokenPermissions[](permit_length),
        permit2.nonce,
        permit2.deadline
      );
      transferDetails = 
        new ISignatureTransfer.SignatureTransferDetails[](permit_length);
    }
    {
      uint256 expected_msg_value = 0;
      for (uint256 i = 0; i < inputs.length; i++) {

        if (inputs[i].tokenAddress == _ETH) {
          if (inputs[i].amountIn == 0) {
            inputs[i].amountIn = msg.value;
          }
          expected_msg_value = inputs[i].amountIn;
        }
        else {
          if (inputs[i].amountIn == 0) {
            inputs[i].amountIn = IERC20(inputs[i].tokenAddress).balanceOf(msg.sender);
          }
          uint256 permit_index = expected_msg_value == 0 ? i : i - 1;

          permit.permitted[permit_index].token = inputs[i].tokenAddress;
          permit.permitted[permit_index].amount = inputs[i].amountIn;

          transferDetails[permit_index].to = inputs[i].receiver;
          transferDetails[permit_index].requestedAmount = inputs[i].amountIn;
        }
      }
      require(msg.value == expected_msg_value, "Wrong msg.value");
    }
    ISignatureTransfer(permit2.contractAddress).permitTransferFrom(
      permit,
      transferDetails,
      msg.sender,
      permit2.signature
    );
    return _swapMulti(
      inputs,
      outputs,
      pathDefinition,
      executor,
      referralInfo
    );
  }

  /// @notice contains the main logic for swapping between two sets of tokens
  /// assumes that inputs have already been sent to the right location and msg.value
  /// is set correctly to be 0 for no native input and match native inpuit otherwise
  /// @param inputs list of input token structs for the path being executed
  /// @param outputs list of output token structs for the path being executed
  /// @param pathDefinition Encoded path definition for executor
  /// @param executor Address of contract that will execute the path
  /// @param referralInfo referral info to specify the source of and fee for the swap
  function _swapMulti(
    inputTokenInfo[] memory inputs,
    outputTokenInfo[] memory outputs,
    bytes calldata pathDefinition,
    address executor,
    swapReferralInfo memory referralInfo
  )
    internal
    returns (uint256[] memory amountsOut)
  {
    // Extract arrays of input amount values and tokens from the inputs struct list
    uint256[] memory amountsIn = new uint256[](inputs.length);
    address[] memory tokensIn = new address[](inputs.length);

    // Check input specification validity and transfer input tokens to executor
    {
      for (uint256 i = 0; i < inputs.length; i++) {

        amountsIn[i] = inputs[i].amountIn;
        tokensIn[i] = inputs[i].tokenAddress;

        for (uint256 j = 0; j < i; j++) {
          require(
            inputs[i].tokenAddress != inputs[j].tokenAddress,
            "Duplicate source tokens"
          );
        }
        for (uint256 j = 0; j < outputs.length; j++) {
          require(
            inputs[i].tokenAddress != outputs[j].tokenAddress,
            "Arbitrage not supported"
          );
        }
      }
    }
    // Check outputs for duplicates and record balances before swap
    uint256[] memory balancesBefore = new uint256[](outputs.length);
    for (uint256 i = 0; i < outputs.length; i++) {
      require(
        outputs[i].amountMin <= outputs[i].amountQuote,
        "Minimum greater than quote"
      );
      require(
        outputs[i].amountMin > 0,
        "Minimum output is zero"
      );
      for (uint256 j = 0; j < i; j++) {
        require(
          outputs[i].tokenAddress != outputs[j].tokenAddress,
          "Duplicate destination tokens"
        );
      }
      balancesBefore[i] = _universalBalance(outputs[i].tokenAddress);
    }
    // Delegate the execution of the path to the specified Odos Executor
    IOdosExecutor(executor).executePath{value: msg.value}(pathDefinition, amountsIn, msg.sender);

    int256[] memory slippage = new int256[](outputs.length);
    {
      amountsOut = new uint256[](outputs.length);

      uint256 splitBPS = (referralInfo.code >> 32) & 65535;
      if (splitBPS == 0) splitBPS = 8000;
      require(splitBPS <= 10000, "Invalid Ref Code");

      for (uint256 i = 0; i < outputs.length; i++) {
        // Record the destination token balance before the path is executed
        amountsOut[i] = _universalBalance(outputs[i].tokenAddress) - balancesBefore[i];

        if (referralInfo.fee > 0) {
          require(referralInfo.feeRecipient != address(0), "Null fee recipient");
          require(referralInfo.fee <= FEE_DENOM / 50, "Fee too high");

          if (referralInfo.feeRecipient != address(this)) {
            _universalTransfer(
              outputs[i].tokenAddress,
              referralInfo.feeRecipient,
              amountsOut[i] * referralInfo.fee * splitBPS / (FEE_DENOM * 10000)
            );
          }
          amountsOut[i] = amountsOut[i] * (FEE_DENOM - referralInfo.fee) / FEE_DENOM;
        }
        slippage[i] = int256(amountsOut[i]) - int256(outputs[i].amountQuote);
        if (slippage[i] > 0 && (referralInfo.code >> 48) & 1 == 0) {
          amountsOut[i] = outputs[i].amountQuote;
        }
        require(amountsOut[i] >= outputs[i].amountMin, "Slippage Limit Exceeded");

        _universalTransfer(
          outputs[i].tokenAddress,
          outputs[i].receiver == address(0) ? msg.sender : outputs[i].receiver,
          amountsOut[i]
        );
      }
    }
    address[] memory tokensOut = new address[](outputs.length);
    for (uint256 i = 0; i < outputs.length; i++) {
        tokensOut[i] = outputs[i].tokenAddress;
    }
    emit SwapMulti(
      msg.sender,
      amountsIn,
      tokensIn,
      amountsOut,
      tokensOut,
      slippage,
      referralInfo.code,
      referralInfo.fee,
      referralInfo.feeRecipient
    );
  }

  /// @notice Changes the liquidator address
  /// @param account The address of new liquidator
  function changeLiquidatorAddress(address account)
    external
    onlyOwner
  {
    liquidatorAddress = account;
    emit LiquidatorAddressChanged(account);
  }

  /// @notice Push new addresses to the cached address list for when storage is cheaper than calldata
  /// @param addresses list of addresses to be added to the cached address list
  function writeAddressList(
    address[] calldata addresses
  ) 
    external
    onlyOwner
  {
    for (uint256 i = 0; i < addresses.length; i++) {
      addressList.push(addresses[i]);
    }
  }

  /// @notice Allows the owner to transfer funds held by the router contract
  /// @param tokens List of token address to be transferred
  /// @param amounts List of amounts of each token to be transferred
  /// @param dest Address to which the funds should be sent
  function transferRouterFunds(
    address[] calldata tokens,
    uint256[] calldata amounts,
    address dest
  )
    external
  {
    require(msg.sender == liquidatorAddress || msg.sender == owner(), "Address not allowed");
    require(tokens.length == amounts.length, "Invalid funds transfer");
    
    for (uint256 i = 0; i < tokens.length; i++) {
      _universalTransfer(
        tokens[i], 
        dest, 
        amounts[i] == 0 ? _universalBalance(tokens[i]) : amounts[i]
      );
    }
  }
  
  /// @notice Directly swap funds held in router 
  /// @param inputs list of input token structs for the path being executed
  /// @param outputs list of output token structs for the path being executed
  /// @param pathDefinition Encoded path definition for executor
  /// @param executor Address of contract that will execute the path
  function swapRouterFunds(
    inputTokenInfo[] memory inputs,
    outputTokenInfo[] memory outputs,
    bytes calldata pathDefinition,
    address executor
  )
    external
    returns (uint256[] memory amountsOut)
  {
    require(msg.sender == liquidatorAddress || msg.sender == owner(), "Address not allowed");

    uint256[] memory amountsIn = new uint256[](inputs.length);
    address[] memory tokensIn = new address[](inputs.length);

    for (uint256 i = 0; i < inputs.length; i++) {
      tokensIn[i] = inputs[i].tokenAddress;

      amountsIn[i] = inputs[i].amountIn == 0 ? 
        _universalBalance(tokensIn[i]) : inputs[i].amountIn;

      _universalTransfer(
        tokensIn[i],
        inputs[i].receiver,
        amountsIn[i]
      );
    }
    // Check outputs for duplicates and record balances before swap
    uint256[] memory balancesBefore = new uint256[](outputs.length);
    address[] memory tokensOut = new address[](outputs.length);
    for (uint256 i = 0; i < outputs.length; i++) {
      tokensOut[i] = outputs[i].tokenAddress;
      balancesBefore[i] = _universalBalance(tokensOut[i]);
    }
    // Delegate the execution of the path to the specified Odos Executor
    IOdosExecutor(executor).executePath{value: 0}(pathDefinition, amountsIn, msg.sender);

    amountsOut = new uint256[](outputs.length);
    for (uint256 i = 0; i < outputs.length; i++) {

      // Record the destination token balance before the path is executed
      amountsOut[i] = _universalBalance(tokensOut[i]) - balancesBefore[i];

      require(amountsOut[i] >= outputs[i].amountMin, "Slippage Limit Exceeded");

      _universalTransfer(
        outputs[i].tokenAddress,
        outputs[i].receiver == address(0) ? msg.sender : outputs[i].receiver,
        amountsOut[i]
      );
    }
    emit SwapMulti(
      msg.sender,
      amountsIn,
      tokensIn,
      amountsOut,
      tokensOut,
      new int256[](outputs.length),
      0,
      0,
      address(0)
    );
  }
  
  /// @notice helper function to get balance of ERC20 or native coin for this contract
  /// @param token address of the token to check, null for native coin
  /// @return balance of specified coin or token
  function _universalBalance(address token) private view returns(uint256) {
    if (token == _ETH) {
      return address(this).balance;
    } else {
      return IERC20(token).balanceOf(address(this));
    }
  }
  
  /// @notice helper function to transfer ERC20 or native coin
  /// @param token address of the token being transferred, null for native coin
  /// @param to address to transfer to
  /// @param amount to transfer
  function _universalTransfer(address token, address to, uint256 amount) private {
    if (token == _ETH) {
      (bool success,) = payable(to).call{value: amount}("");
      require(success, "ETH transfer failed");
    } else {
      IERC20(token).safeTransfer(to, amount);
    }
  }
}
