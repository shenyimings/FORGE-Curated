// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

interface IAgentBalances {

    // View functions
    function agentWallets(address agent) external view returns (address);
    function agentETHBalance(address agent) external view returns (uint256);
    function getAgentTokenBalance(address agent, address token) external view returns (uint256);

    // External functions
    function setAgentWallet(address agent, address agentWallet) external;
    function withdraw(address agent, address token, uint256 amount) external;
    function withdrawETH(address agent, uint256 amount) external;
    function deposit(address from, address token, address agent, uint256 amount) external;
    function depositETH(address agent) external payable;

    // Events
    event AgentWalletSet(address indexed agent, address indexed agentWallet);
    event Withdraw(address indexed agent, address indexed token, uint256 amount);
    event Deposit(address indexed agent, address indexed token, uint256 amount);
}
