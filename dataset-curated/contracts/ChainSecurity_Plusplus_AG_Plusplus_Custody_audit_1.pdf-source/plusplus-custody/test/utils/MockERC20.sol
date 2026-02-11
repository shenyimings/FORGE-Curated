// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title MockERC20
/// @notice A simple ERC20-style token for testing purposes. This contract
/// implements the minimal subset of the ERC20 interface required by
/// ZCHFSavingsManager. It exposes a `mint` function for creating
/// balances during tests and a flag to simulate `transferFrom` failure.
contract MockERC20 {
    /// Token metadata
    string public name;
    string public symbol;
    uint8 public decimals;

    // Internal accounting of balances and allowances.
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    // Flag to control the behaviour of transferFrom and transfer. When true the next
    // call will return false without moving funds. This enables testing of error paths.
    bool public failTransfer;
    bool public failTransferFrom;

    // Savings module address for setting unlimited allowance.
    address public savingsModule;

    /// @param name_   Human‑readable token name
    /// @param symbol_ Token ticker symbol
    /// @param decimals_ Number of decimals (WBTC uses 8 decimals, most other ERC20s use 18)
    constructor(string memory name_, string memory symbol_, uint8 decimals_) {
        name = name_;
        symbol = symbol_;
        decimals = decimals_;
    }

    /// @notice Sets the failure flag for transferFrom.
    /// @param failFlag When true, the next transferFrom will return false.
    function setFailTransferFrom(bool failFlag) external {
        failTransferFrom = failFlag;
    }

    /// @notice Set the transfer failure flag. When true, calls to transfer will revert early
    /// @param failFlag Boolean flag to toggle failure
    function setFailTransfer(bool failFlag) external {
        failTransfer = failFlag;
    }

    /// @notice Mints tokens to the given address.
    /// @dev This function is non-standard and intended for test setup only.
    /// @param to The address receiving the newly minted tokens.
    /// @param amount The number of tokens to mint.
    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function setUnlimitedAllowanceForSavingsModule(address savingsModule_) external {
        // Used to set an unlimited allowance for the savings module.
        savingsModule = savingsModule_;
    }

    /// @notice Transfers tokens from the caller to another address.
    /// @param to The recipient of the tokens.
    /// @param amount The number of tokens to transfer.
    /// @return success True if the transfer succeeded.
    function transfer(address to, uint256 amount) external returns (bool success) {
        if (failTransfer) {
            // reset the flag so only the next call fails
            failTransfer = false;
            return false;
        }

        uint256 senderBalance = balanceOf[msg.sender];
        require(senderBalance >= amount, "MockERC20: insufficient balance");
        unchecked {
            balanceOf[msg.sender] = senderBalance - amount;
            balanceOf[to] += amount;
        }
        return true;
    }

    /// @notice Approves a spender to transfer tokens on behalf of the caller.
    /// @param spender The address that will be able to spend tokens.
    /// @param amount The maximum amount of tokens the spender can spend.
    /// @return success True if the approval succeeded.
    function approve(address spender, uint256 amount) external returns (bool success) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    /// @notice Transfers tokens from one address to another using an allowance.
    /// @dev If `shouldFailTransferFrom` is set the function returns false
    /// without modifying balances or allowances. Otherwise it behaves like a
    /// standard ERC20 transferFrom.
    /// @param from The address to pull tokens from.
    /// @param to The address to send tokens to.
    /// @param amount The number of tokens to transfer.
    /// @return success True if the transfer succeeded, false if failure flag was set.
    function transferFrom(address from, address to, uint256 amount) external returns (bool success) {
        if (failTransferFrom) {
            // reset the flag so only the next call fails
            failTransferFrom = false;
            return false;
        }
        uint256 currentAllowance = allowance[from][msg.sender];
        // If the savings module is set, allow unlimited transfers from it.
        if (msg.sender == savingsModule) {
            currentAllowance = type(uint256).max;
        }
        require(currentAllowance >= amount, "MockERC20: insufficient allowance");
        uint256 fromBalance = balanceOf[from];
        require(fromBalance >= amount, "MockERC20: insufficient balance");
        unchecked {
            allowance[from][msg.sender] = currentAllowance - amount;
            balanceOf[from] = fromBalance - amount;
            balanceOf[to] += amount;
        }
        return true;
    }
}
