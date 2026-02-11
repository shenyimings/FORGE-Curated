// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

/// @title Zap Router Interface
/// @author kexley, @capLabs
/// @notice Interface for zap router that contains the structs for orders and routes
interface IZapRouter {
    /// @notice Input token and amount used in a step of the zap
    /// @param token Address of token
    /// @param amount Amount of token
    struct Input {
        address token;
        uint256 amount;
    }

    /// @notice Output token and amount from the end of the zap
    /// @param token Address of token
    /// @param minOutputAmount Minimum amount of token received
    struct Output {
        address token;
        uint256 minOutputAmount;
    }

    /// @notice External call at the end of zap
    /// @param target Target address to be called
    /// @param value Ether value of the call
    /// @param data Payload to call target address with
    struct Relay {
        address target;
        uint256 value;
        bytes data;
    }

    /// @notice Token relevant to the current step of the route
    /// @param token Address of token
    /// @param index Location in the data that the balance of the token should be inserted
    struct StepToken {
        address token;
        int32 index;
    }

    /// @notice Step in a route
    /// @param target Target address to be called
    /// @param value Ether value to call the target address with
    /// @param data Payload to call target address with
    /// @param tokens Tokens relevant to the step that require approvals or their balances inserted into the data
    struct Step {
        address target;
        uint256 value;
        bytes data;
        StepToken[] tokens;
    }

    /// @notice Order created by the user
    /// @param inputs Tokens and amounts to be pulled from the user
    /// @param outputs Tokens and minimums to be sent to recipient
    /// @param relay External call to make after zap is completed
    /// @param user Source of input tokens
    /// @param recipient Destination of output tokens
    struct Order {
        Input[] inputs;
        Output[] outputs;
        Relay relay;
        address user;
        address recipient;
    }

    /// @notice Execute an order directly
    /// @param _order Order created by the user
    /// @param _route Route supplied by user
    function executeOrder(Order calldata _order, Step[] calldata _route) external payable;

    /// @notice Get the token manager immutable address
    /// @return address Address of the token manager
    function tokenManager() external view returns (address);
}
