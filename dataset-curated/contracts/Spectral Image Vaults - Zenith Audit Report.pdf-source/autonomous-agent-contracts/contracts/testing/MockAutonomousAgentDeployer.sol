// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../interfaces/IAutonomousAgentDeployer.sol";
import "../interfaces/IOctoDistributor.sol";

contract MockAutonomousAgentDeployer is IAutonomousAgentDeployer {
    address public _distributor;
    mapping(address => bool) private _isAgentToken;
    mapping(Parameter => uint256) public parameters;


    function agentTokenImplementation() external pure override returns (address) { return address(0); }
    function agentBalances() external pure override returns (IAgentBalances) { return IAgentBalances(address(0)); }
    function agentTokensSold(address /* token */) external pure override returns (uint256) { return 0; }
    function agentWallets(address /* agent */) external pure override returns (address) { return address(0); }
    function agentTokenUniswapPool(address /* token */) external pure override returns (address) { return address(0); }
    function totalSPECDeposited(address /* token */) external pure override returns (uint256) { return 0; }
    function spectralToken() external pure override returns (address) { return address(0); }
    function uniswapFactory() external pure override returns (address) { return address(0); }
    function uniswapRouter() external pure override returns (IUniswapV2Router02) { return IUniswapV2Router02(address(0)); }
    function uniswapV3Router() external pure override returns (ISwapRouter) { return ISwapRouter(address(0)); }
    function feeWallet() external pure override returns (address payable) { return payable(address(0)); }

    function setDistributorAddress(address _newDistributor) external {
        _distributor = _newDistributor;
    }

    function setAgentToken(address token, bool isAgent) external {
        _isAgentToken[token] = isAgent;
    }

    function distributor() external view override returns (IOctoDistributor) {
        return IOctoDistributor(_distributor);
    }

    function isAgentToken(address token) external view override returns (bool) {
        return _isAgentToken[token];
    }

    function deployAgent(
        string memory /* _agentName */,
        string memory /* _agentTicker */,
        uint256 /* specAmount */
    ) external payable override {}

    function deployAgentWithETH(
        string memory /* _agentName */,
        string memory /* _agentTicker */,
        uint256 /* specAmount */
    ) external payable override returns(address) {}

    function getTokensReceived(uint /* _initialAmount */, address /* _agentToken */) external pure override returns (uint256) { return 0; }
    function getSPECAmountForTokens(uint /* tokenAmount */, address /* token */) external pure override returns (uint256) { return 0; }

    function swapExactSPECForTokens(
        uint /* amountIn */,
        uint /* amountOutMin */,
        address /* token */,
        uint /* deadline */
    ) external override {}

    function swapExactTokensForSPEC(
        uint /* amountIn */,
        uint /* amountOutMin */,
        address /* fromToken */,
        uint /* deadline */
    ) external override {}

    function accumulateSwapFees(uint256 /* amount */) external pure override {}
    function withdrawTokens(address /* token */, uint256 /* amount */) external pure override {}
    function distributeTradingProfitsToStakers(uint256 /* _amount */, address /* _token */) external pure override {}
} 