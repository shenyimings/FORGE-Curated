// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "../interfaces/IAutonomousAgentDeployer.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";

contract AgentBalancesUpgradeTest is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable, UUPSUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    mapping (address => address) public agentWallets;
    // agent => token => balance
    mapping (address => mapping(address => uint256)) private agentBalance;
    mapping (address => uint256) public agentETHBalance;

    address public admin;

    uint8 public version;

    address public deployer;
    //gap for future variable additions
    uint256[49] private __gap;

    event AgentWalletSet(address agent, address agentWallet);
    event Withdraw(address agent, address token, uint256 amount);
    event Deposit(address agent, address token, uint256 amount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    modifier onlyAdminOrOwner() {
        require(msg.sender == owner() || msg.sender == admin, "AgentBalances: caller is not the owner or admin");
        _;
    }

    modifier onlyAgentTokenOrDeployer() {
        require(msg.sender == deployer || IAutonomousAgentDeployer(deployer).isAgentToken(msg.sender), "AgentBalances: caller is not the deployer or admin");
        _;
    }

    function initialize(address _admin) public initializer {
        require(_admin != address(0), "AgentBalances: admin cannot be the zero address");
        __Ownable_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
        admin = _admin;
        version = 1;
    }

    function setAdmin(address _admin) public onlyOwner {
        require(_admin != address(0), "AgentBalances: admin cannot be the zero address");
        admin = _admin;
    }

    function setDeployer(address _deployer) public onlyOwner {
        require(_deployer != address(0), "AgentBalances: deployer cannot be the zero address");
        deployer = _deployer;
    }

    //also used to update the agent wallet in the case that the agent gets a new EOA
    function setAgentWallet(address agent, address agentWallet) public onlyAdminOrOwner {
        require (agentWallet != address(0), "AgentBalances: agent wallet cannot be the zero address");
        require (agent != address(0), "AgentBalances: agent cannot be the zero address");

        agentWallets[agent] = agentWallet;

        emit AgentWalletSet(agent, agentWallet);
    }

    function withdraw(address agent, address token, uint256 amount) public {
        require(agentWallets[agent] == msg.sender, "AgentBalances: caller is not the agent wallet");
        require(agentBalance[agent][token] >= amount, "AgentBalances: insufficient balance");
        agentBalance[token][agent] -= amount;

        IERC20Upgradeable(token).safeTransfer(msg.sender, amount);

        emit Withdraw(agent, token, amount);
    }

    function withdrawETH(address agent, uint256 amount) public {
        require(agentWallets[agent] == msg.sender, "AgentBalances: caller is not the agent wallet");
        require(agentETHBalance[agent] >= amount, "AgentBalances: insufficient balance");
        agentETHBalance[agent] -= amount;

        payable(msg.sender).transfer(amount);

        emit Withdraw(agent, address(0), amount); //address 0 for ETH
    }

    function deposit(address from, address token, address agent, uint256 amount) public onlyAgentTokenOrDeployer {
        if(agentWallets[agent] != address(0)){
            //Pipe it straight through if the agent's wallet is set
            IERC20Upgradeable(token).safeTransferFrom(from, agentWallets[agent], amount);
        }
        else
        {
            //Otherwise store it here for later
            IERC20Upgradeable(token).safeTransferFrom(from, address(this), amount);
            agentBalance[agent][token] += amount;
        }

        emit Deposit(agent, token, amount);
    }

    function depositETH(address agent) public payable onlyAgentTokenOrDeployer {
        if(agentWallets[agent] != address(0))
        {
            payable(agentWallets[agent]).transfer(msg.value);
        }
        else
        {
            agentETHBalance[agent] += msg.value;
        }

        emit Deposit(agent, address(0), msg.value); //address 0 for ETH
    }

    function claimForAgent(address agent, address token, uint256 amount) public onlyAdminOrOwner {
        require(agentBalance[agent][token] >= amount, "AgentBalances: insufficient balance");
        agentBalance[agent][token] -= amount;
        IERC20Upgradeable(token).safeTransfer(agentWallets[agent], amount);

        emit Withdraw(agent, token, amount);
    }

    function claimETHForAgent(address agent, uint256 amount) public onlyAdminOrOwner {
        require(agentETHBalance[agent] >= amount, "AgentBalances: insufficient balance");
        agentETHBalance[agent] -= amount;
        payable(agentWallets[agent]).transfer(amount);

        emit Withdraw(agent, address(0), amount); //address 0 for ETH
    }

    function getLPBalance(address _token, address _deployer) public view returns (uint256) {
        address spectralToken = IAutonomousAgentDeployer(_deployer).spectralToken();
        address lpToken = IUniswapV2Factory(IAutonomousAgentDeployer(_deployer).uniswapFactory()).getPair(_token, spectralToken);
        return IERC20Upgradeable(lpToken).balanceOf(address(this));
    }

    function getAgentBalance(address agent, address token) public view returns (uint256) {
        return agentBalance[agent][token];
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {
        require(newImplementation != address(0), "ZERO_ADDRESS");
        ++version;
    }
}