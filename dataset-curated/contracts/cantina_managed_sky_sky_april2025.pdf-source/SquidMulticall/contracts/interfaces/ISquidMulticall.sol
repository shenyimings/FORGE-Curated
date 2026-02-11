// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

/// @title SquidMulticall
/// @notice Multicall logic specific to Squid calls format. The contract specificity is mainly
/// to enable ERC20 and native token amounts in calldata between two calls.
/// @dev Support receiption of NFTs.
interface ISquidMulticall {
    /// @notice Call type that enables to specific behaviours of the multicall.
    enum CallType {
        // Will simply run calldata
        Default,
        // Will update amount field in calldata with ERC20 token balance of the multicall contract.
        FullTokenBalance,
        // Will update amount field in calldata with native token balance of the multicall contract.
        FullNativeBalance,
        // Will run a safeTransferFrom to get full ERC20 token balance of the caller.
        CollectTokenBalance
    }

    /// @notice Calldata format expected by multicall.
    struct Call {
        // Call type, see CallType struct description.
        CallType callType;
        // Address that will be called.
        address target;
        // Native token amount that will be sent in call.
        uint256 value;
        // Calldata that will be send in call.
        bytes callData;
        // Extra data used by multicall depending on call type.
        // Default: unused (provide 0x)
        // FullTokenBalance: address of the ERC20 token to get balance of and zero indexed position
        // of the amount parameter to update in function call contained by calldata.
        // Expect format is: abi.encode(address token, uint256 amountParameterPosition)
        // Eg: for function swap(address tokenIn, uint amountIn, address tokenOut, uint amountOutMin,)
        // amountParameterPosition would be 1.
        // FullNativeBalance: unused (provide 0x)
        // CollectTokenBalance: address of the ERC20 token to collect.
        // Expect format is: abi.encode(address token)
        bytes payload;
    }

    /// Thrown when the multicall contract does not hold any of the ERC20 token targeted by a
    /// FullTokenBalance call. The call is thus likely to be faulty.
    /// @param token Address of the faulty ERC20 token.
    error NoTokenAvailable(address token);
    /// Thrown when one of the calls fails.
    /// @param callPosition Zero indexed position of the call in the call set provided to the
    /// multicall.
    /// @param reason Revert data returned by contract called in failing call.
    error CallFailed(uint256 callPosition, bytes reason);

    /// @notice Main function of the multicall that runs the call set.
    /// @param calls Call set to be ran by multicall.
    function run(Call[] calldata calls) external payable;
}
