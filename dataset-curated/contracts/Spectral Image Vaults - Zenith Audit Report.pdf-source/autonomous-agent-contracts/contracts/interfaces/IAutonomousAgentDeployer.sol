// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "./ISwapRouter.sol";
import "./IAgentBalances.sol";
import "./IOctoDistributor.sol";

interface IAutonomousAgentDeployer {

    enum Parameter {
        INITIAL_TOKEN_SUPPLY,
        AGENT_TOKEN_DEPLOYMENT_FEE,
        AGENT_TOKEN_OWNERSHIP,
        DEPLOYMENT_COST_ETH,
        INITIAL_TRADING_BALANCE,
        DEPLOYMENT_TREASURY_FEE,
        INITIAL_VIRTUAL_LIQUIDITY
    }

    // Events
    event AgentDeployed(address indexed agentToken);
    event TokensSold(address indexed agentToken, address indexed buyer, uint256 amount);
    event TokensRedeemedForSPEC(address indexed redeemer, uint256 amount, uint256 specAmount);
    event UniswapV2PoolCreated(address indexed agentToken, address indexed poolAddress);
    event AgentWalletSet(address indexed agent, address indexed wallet);
    function distributor() external view returns (IOctoDistributor);
    function distributeTradingProfitsToStakers(uint256 _amount, address _token) external;
    // Functions
    function deployAgent(
        string memory _agentName,
        string memory _agentTicker,
        uint256 specAmount
    ) external payable;
    function deployAgentWithETH(
        string memory _agentName,
        string memory _agentTicker,
        uint256 minSpecAmount
    ) external payable returns (address agentToken);
    function getTokensReceived(uint _initialAmount, address _agentToken) external view returns (uint256);

    function getSPECAmountForTokens(uint tokenAmount, address token) external view returns (uint256);

    function swapExactSPECForTokens(
        uint amountIn,
        uint amountOutMin,
        address token,
        uint deadline
    ) external;

    function swapExactTokensForSPEC(
        uint amountIn,
        uint amountOutMin,
        address fromToken,
        uint deadline
    ) external;

    function accumulateSwapFees(uint256 amount) external;

    function withdrawTokens(address token, uint amount) external;

    // Variables (State Variables as Public Getters)
    function feeWallet() external view returns (address payable);

    function uniswapRouter() external view returns (IUniswapV2Router02);

    function uniswapFactory() external view returns (address);

    function uniswapV3Router() external view returns (ISwapRouter);

    function agentTokenImplementation() external view returns (address);

    function spectralToken() external view returns (address);

    function agentBalances() external view returns (IAgentBalances);

    function agentTokensSold(address token) external view returns (uint256);

    function agentWallets(address agent) external view returns (address);

    function totalSPECDeposited(address token) external view returns (uint256);

    function agentTokenUniswapPool(address token) external view returns (address);

    function isAgentToken(address token) external view returns (bool);

    function parameters(Parameter param) external view returns (uint256);
}
