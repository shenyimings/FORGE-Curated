// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "node_modules/diamond-proxy-pattern/contracts/BeaconProxyManager.sol";
import "./AgentToken.sol";
import "./interfaces/IOctoDistributor.sol";
import "./interfaces/ISpectralStaking.sol";

contract AutonomousAgentDeployer is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable, UUPSUpgradeable, BeaconProxyManager, IAutonomousAgentDeployer {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    mapping(Parameter => uint256) public parameters;

    address payable public feeWallet;

    IUniswapV2Router02 public uniswapRouter;
    ISwapRouter public uniswapV3Router;

    address public uniswapFactory;
    address public agentTokenImplementation; 
    uint256 public UNISWAP_POOL_CREATION_VALUE; // Threshold for pool creation in SPEC

    address public spectralToken;
    address public WETH;
    IAgentBalances public override agentBalances;

    mapping (address => bool) public agentTokens;
    mapping (address => uint256) public agentTokensSold;
    mapping (address => address) public agentWallets;
    mapping (address => uint256) public totalSPECDeposited;
    mapping (address => address) public agentTokenUniswapPool;

    address public admin;

    uint8 public version;
    uint8 public agentsVersion;

    bool public paused;
    address public pauser;
    
    uint256 constant INITIAL_VIRTUAL_LIQUIDITY = 500 ether;

    IOctoDistributor public distributor;
    ISpectralStaking public spectralStaking;
    uint256 accumulatedTaxToSwap;
    mapping(address => uint256) public accumulatedTaxToSwapByAgent;
    //gap for future variable additions
    uint256[44] private __gap;

    event TokensSold(address indexed agentToken, address indexed buyer, uint256 amount, uint256 specAmount);
    event TokensRedeemedForSPEC(address indexed agentToken, address indexed redeemer, uint256 amount, uint256 specAmount);
    event ParameterSet(Parameter indexed param, uint256 value);
    event DistributorSet(address distributor);
    event SpectralStakingSet(address spectralStaking);
    event TaxDistributed(uint256 amount);
    event TaxAccumulated(uint256 amount,uint256 total);
    event UniswapV2PoolCreationFailed(address token, address pool);
    event ProfitDistributed(address token, uint256 amount);

    modifier ensure(uint deadline) {
        require(deadline >= block.timestamp, "EXPIRED");
        _;
    }

    modifier whenNotPaused() {
        require(!paused, "Pausable: paused");
        _;
    }

    modifier OnlyPauserOrOwner() {
        require(msg.sender == owner() || msg.sender == pauser, "AgentDeployer: caller is not the owner or admin");
        _;
    }

    modifier onlyAgentToken() {
        require(agentTokens[msg.sender], "Invalid agent token");
        _;
    }

    modifier onlyDistributor() {
        require(msg.sender == address(distributor), "Only distributor");
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    modifier onlyAdminOrOwner() {
        require(msg.sender == owner() || msg.sender == admin, "AgentDeployer: caller is not the owner or admin");
        _;
    }

    function initialize(
        address payable _fee,
        address _admin,
        address _uniswapRouter,
        address _uniswapFactory,
        address _spectralToken,
        address _agentBalances,
        uint256 _uniswap_pool_creation_value,
        address _agentTokenImplementation,
        address _uniswapV3Router,
        address _WETH
    ) public initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
        
        parameters[Parameter.INITIAL_TOKEN_SUPPLY] = 1_000_000_000 ether;
        parameters[Parameter.AGENT_TOKEN_DEPLOYMENT_FEE] = 6_500_000 ether;
        parameters[Parameter.AGENT_TOKEN_OWNERSHIP] = 500_000 ether;
        parameters[Parameter.DEPLOYMENT_COST_ETH] = 0.01 ether;
        parameters[Parameter.INITIAL_TRADING_BALANCE] = 0.007 ether;
        parameters[Parameter.DEPLOYMENT_TREASURY_FEE] = 0.003 ether;
        
        feeWallet = _fee;
        admin = _admin;
        agentsVersion = 1;
        uniswapRouter = IUniswapV2Router02(_uniswapRouter);
        uniswapFactory = _uniswapFactory;
        agentBalances = IAgentBalances(_agentBalances);
        spectralToken = _spectralToken;
        UNISWAP_POOL_CREATION_VALUE = _uniswap_pool_creation_value;
        agentTokenImplementation = _agentTokenImplementation;
        uniswapV3Router = ISwapRouter(_uniswapV3Router);
        WETH = _WETH;
    }

    function deployAgent(
        string memory _agentName,
        string memory _agentTicker,
        uint256 specAmount
    ) public payable whenNotPaused {
        require(msg.value >=
        parameters[Parameter.DEPLOYMENT_COST_ETH]
        , "Incorrect ETH amount");

        // Transfer SPEC from the deployer to this contract
        IERC20Upgradeable(spectralToken).transferFrom(msg.sender, address(this), specAmount);

        // Deploy the agent and perform common operations
        (address _agentToken, uint256 creatorTokensReceived) = initializeAgent(
            _agentName,
            _agentTicker,
            specAmount
        );

        //allocate tokens to the creator
        IERC20Upgradeable(_agentToken).transfer(msg.sender, creatorTokensReceived);

        // Emit tokens sold event for initial token sale
        emit TokensSold(_agentToken, msg.sender, creatorTokensReceived, specAmount);        
    }

    function deployAgentWithETH(
        string memory _agentName,
        string memory _agentTicker,
        uint256 minSpecAmount
    ) public payable whenNotPaused returns (address agentToken) {
        require(msg.value >= 
        parameters[Parameter.DEPLOYMENT_COST_ETH]
        , "Incorrect ETH amount");

        // Calculate ETH required for fees and deduct from the total ETH received
        uint256 treasuryFee = parameters[Parameter.DEPLOYMENT_TREASURY_FEE];
        uint256 initialTradingBalance = parameters[Parameter.INITIAL_TRADING_BALANCE];
        uint256 totalFees = initialTradingBalance + treasuryFee;

        require(msg.value >= totalFees, "Insufficient ETH for fees");

        uint256 swapAmountETH = msg.value - totalFees;

        // Perform the swap using the externally calculated minSpecAmount as the minimum output
        uint256 specAmount = swapETHForSPEC(swapAmountETH, minSpecAmount);
        // Deploy the agent and perform common operations
        (address _agentToken, uint256 creatorTokensReceived) = initializeAgent(
            _agentName,
            _agentTicker,
            specAmount
        );
        agentToken = _agentToken;

        if (specAmount > 0) {
            IERC20Upgradeable(_agentToken).transfer(msg.sender, creatorTokensReceived);
            emit TokensSold(_agentToken, msg.sender, creatorTokensReceived, specAmount);
        }
    }

    function initializeAgent(
        string memory _agentName,
        string memory _agentTicker,
        uint256 specAmount
    ) internal returns (address, uint256) {
        require(address(agentBalances) != address(0), "Invalid balances address");

        // Deploy the proxy with the AgentToken implementation address with diamond pattern
        address _agentToken = createBeaconProxy(agentTokenImplementation, abi.encodeWithSelector(
            AgentToken(address(0)).initialize.selector,
            _agentName,
            _agentTicker,
            parameters[Parameter.INITIAL_TOKEN_SUPPLY],
            feeWallet,
            address(agentBalances)
        ));

        agentTokens[_agentToken] = true;
        distributor.setAgentCreator(_agentToken, msg.sender);
        // Transfer deployment fee and treasury fee to feeWallet
        IERC20Upgradeable(_agentToken).transfer(feeWallet, parameters[Parameter.AGENT_TOKEN_DEPLOYMENT_FEE]);

        IERC20Upgradeable(_agentToken).approve(address(spectralStaking), 2_000_000 ether);
        spectralStaking.addDistribution(_agentToken, address(0), 2_000_000 ether, 0);

        IERC20Upgradeable(_agentToken).approve(address(agentBalances), parameters[Parameter.AGENT_TOKEN_OWNERSHIP]);
        agentBalances.deposit(address(this), _agentToken, _agentToken, parameters[Parameter.AGENT_TOKEN_OWNERSHIP]);
        // Calculate tokens received based on `specAmount`
        uint256 creatorTokensReceived = getTokensReceived(specAmount, _agentToken);
        require(creatorTokensReceived <= parameters[Parameter.INITIAL_TOKEN_SUPPLY] / 100, "Exceeds 1%");

        (bool success, ) = feeWallet.call{value: parameters[Parameter.DEPLOYMENT_TREASURY_FEE]}("");
        require(success, "Transfer failed.");

        // Deposit the initial trading balance to agent balance contract
        agentBalances.depositETH{value: parameters[Parameter.INITIAL_TRADING_BALANCE]}(_agentToken);

        // Update total SPEC deposited and tokens sold
        totalSPECDeposited[_agentToken] += specAmount;
        agentTokensSold[_agentToken] += creatorTokensReceived;

        // Account for deployment fee and ownership tokens in the tracking
        agentTokensSold[_agentToken] += parameters[Parameter.AGENT_TOKEN_DEPLOYMENT_FEE];
        agentTokensSold[_agentToken] += parameters[Parameter.AGENT_TOKEN_OWNERSHIP];
        // Emit agent deployment event
        emit AgentDeployed(_agentToken);

        return (_agentToken, creatorTokensReceived);
    }

    function swapETHForSPEC(uint256 ethAmount, uint256 minSpecAmount) internal returns (uint256 specAmount) {
        if(ethAmount == 0){
            return 0;
        }
        
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: WETH,
            tokenOut: spectralToken,
            fee: 3000,
            recipient: address(this),
            amountIn: ethAmount,
            amountOutMinimum: minSpecAmount,
            sqrtPriceLimitX96: 0
        });

        specAmount = uniswapV3Router.exactInputSingle{value: ethAmount}(params);

        require(specAmount >= minSpecAmount, "received less than expected");
        return specAmount;
    }

    function getTokensReceived(uint _amountSPECIn, address _agentToken) public view returns (uint256) {
        require(agentTokens[_agentToken], "Invalid agent token");

        if (agentTokenUniswapPool[_agentToken] != address(0)) {
            return _getTokensFromUniswap(_amountSPECIn, spectralToken, _agentToken);
        }
        return _getTokensFromBondingCurve(_amountSPECIn, _agentToken, true);
    }

    function getSPECReceived(uint _amountAgentTokenIn, address _agentToken) public view returns (uint256) {
        require(agentTokens[_agentToken], "Invalid agent token");

        if (agentTokenUniswapPool[_agentToken] != address(0)) {
            return _getTokensFromUniswap(_amountAgentTokenIn, _agentToken, spectralToken);
        }
        return _getTokensFromBondingCurve(_amountAgentTokenIn, _agentToken, false);
    }

    function _getTokensFromUniswap(uint _amountIn, address _tokenIn, address _tokenOut) internal view returns (uint256) {
        address[] memory path = new address[](2);
        path[0] = _tokenIn;
        path[1] = _tokenOut;

        uint256[] memory amounts = uniswapRouter.getAmountsOut(_amountIn, path);
        return amounts[amounts.length - 1];
    }

    function _getTokensFromBondingCurve(uint _amountIn, address _agentToken, bool isSpecToAgentToken) internal view returns (uint256) {
        uint256 currentSPECReserve = totalSPECDeposited[_agentToken] + INITIAL_VIRTUAL_LIQUIDITY;
        uint256 currentTokenReserve = IERC20Upgradeable(_agentToken).balanceOf(address(this));

        // Determine reserves based on input direction
        uint256 newReserve;
        uint256 k = currentSPECReserve * currentTokenReserve;

        if (isSpecToAgentToken) {
            // Calculate new SPEC reserve and agent token received
            newReserve = currentSPECReserve + _amountIn;
            uint256 newTokenReserve = k / newReserve;
            return currentTokenReserve - newTokenReserve;
        } else {
            // Calculate new agent token reserve and SPEC received
            newReserve = currentTokenReserve + _amountIn;
            uint256 newSPECReserve = k / newReserve;
            return currentSPECReserve - newSPECReserve;
        }
    }


    function getSPECAmountForTokens(uint tokenAmount, address token) public view returns (uint256) {
        require(agentTokens[token], "Invalid agent token");
        return getSPECReceived(tokenAmount, token);
    }

    function _createUniswapPool(address _agentToken, uint _deadline) internal {
        require(totalSPECDeposited[_agentToken] > UNISWAP_POOL_CREATION_VALUE && agentTokenUniswapPool[_agentToken] == address(0), "Invalid pool creation conditions");
        address poolAddress = deployUniswapPool(_agentToken);
        if(agentTokenUniswapPool[_agentToken] != address(0))
        {
            agentTokenUniswapPool[_agentToken] = poolAddress;
            uint256 agentTokenBalance = IERC20Upgradeable(_agentToken).balanceOf(address(this));
            // Approve tokens and add liquidity
            IERC20Upgradeable(spectralToken).approve(address(uniswapRouter), totalSPECDeposited[_agentToken]);
            IERC20Upgradeable(_agentToken).approve(address(uniswapRouter), agentTokenBalance);
            uniswapRouter.addLiquidity(
                spectralToken,
                _agentToken,
                totalSPECDeposited[_agentToken],
                agentTokenBalance,
                0, 
                0,
                address(agentBalances), //agentBalances will burn the LPs by the Agent Wallet
                _deadline
            );
        }
    }

    function swapExactSPECForTokens(uint _amountIn, uint amountOutMin, address _agentToken, uint _deadline) public ensure(_deadline) whenNotPaused nonReentrant {   
        require(agentTokens[_agentToken], "Invalid agent token");
        require(_amountIn > 0, "Invalid amount");
        uint256 taxSpecAmount = (_amountIn * AgentToken(_agentToken).taxPercentage() / 10000);
        uint256 userSpecAmount = _amountIn - taxSpecAmount;
        IERC20Upgradeable(spectralToken).transferFrom(msg.sender, address(this), _amountIn);
        if(agentTokenUniswapPool[_agentToken] != address(0)) {
            address[] memory path = new address[](2);
            path[0] = spectralToken;
            path[1] = _agentToken;

            IERC20Upgradeable(spectralToken).approve(address(uniswapRouter), userSpecAmount);

            //We won't emit an event here because Uniswap's event has all the info we need
            //Uniswap checks if amount received > amountOutMin
            uniswapRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(userSpecAmount, amountOutMin, path, msg.sender, _deadline);
        } else {
            uint256 tokensReceived = getTokensReceived(userSpecAmount, _agentToken);
            require(tokensReceived >= amountOutMin, "Insufficient tokens output");
            agentTokensSold[_agentToken] += tokensReceived;
            totalSPECDeposited[_agentToken] += userSpecAmount;
            IERC20Upgradeable(_agentToken).safeTransfer(msg.sender, tokensReceived);
            emit TokensSold(_agentToken, msg.sender, tokensReceived, _amountIn);
        }
        _distributeSwapFees(taxSpecAmount);
        //Create liquidity pool if we meet liquidity conditions
        if(totalSPECDeposited[_agentToken] > UNISWAP_POOL_CREATION_VALUE && agentTokenUniswapPool[_agentToken] == address(0)) {
            _createUniswapPool(_agentToken, _deadline);
        }
    }

    function swapExactTokensForSPEC(uint amountIn, uint amountOutMin, address fromToken, uint deadline) public ensure(deadline) whenNotPaused nonReentrant {
        require(agentTokens[fromToken], "Invalid agent token");
        require(amountIn > 0, "Invalid amount");
        uint256 taxAmount = (amountIn * AgentToken(fromToken).taxPercentage() / 10000);
        uint256 protocolSwapAmount = taxAmount + accumulatedTaxToSwapByAgent[fromToken];
        accumulatedTaxToSwapByAgent[fromToken] = 0;
        uint256 userSwapAfterTax = amountIn - taxAmount;
        uint256 actualSpecTax;
        IERC20Upgradeable(fromToken).safeTransferFrom(msg.sender, address(this), amountIn);
        if(agentTokenUniswapPool[fromToken] != address(0)) {
            address[] memory path = new address[](2);
            path[0] = fromToken;
            path[1] = spectralToken;
            IERC20Upgradeable(fromToken).approve(address(uniswapRouter), userSwapAfterTax);
            

            //Uniswap checks if amount received > amountOutMin
            uniswapRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(userSwapAfterTax, amountOutMin, path, msg.sender, deadline);

            //Swap the current tax and accumulated tax that was from outside our protocol operations (since this contract is ignored in the conditions of the agentToken tax taking)
            uint256 protocolSpecAmount = getSPECReceived(protocolSwapAmount, fromToken);
            uint256 initialSpecBalance = IERC20(spectralToken).balanceOf(address(this));
            IERC20Upgradeable(fromToken).approve(address(uniswapRouter), protocolSwapAmount);
            uniswapRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(protocolSwapAmount, (protocolSpecAmount * 95) / 100, path, address(this), deadline);
            uint256 specBalance = IERC20(spectralToken).balanceOf(address(this)) - initialSpecBalance;
            actualSpecTax = specBalance;
        } else {
            uint256 userSpecAmount = getSPECReceived(userSwapAfterTax, fromToken);
            require(userSpecAmount >= amountOutMin, "Insufficient SPEC output");
            agentTokensSold[fromToken] -= userSwapAfterTax;
            totalSPECDeposited[fromToken] -= userSpecAmount;
            IERC20Upgradeable(spectralToken).safeTransfer(msg.sender, userSpecAmount);
            uint256 protocolSpecAmount = getSPECReceived(protocolSwapAmount, fromToken);
            agentTokensSold[fromToken] -= protocolSwapAmount;
            totalSPECDeposited[fromToken] -= protocolSpecAmount;
            actualSpecTax = protocolSpecAmount;
            emit TokensRedeemedForSPEC(fromToken, msg.sender, userSwapAfterTax, userSpecAmount);
        }
        if(actualSpecTax == 0) {
            return;
        }
        _distributeSwapFees(actualSpecTax);
    }

    function accumulateSwapFees(uint256 amount) external onlyAgentToken() {
        accumulatedTaxToSwapByAgent[msg.sender] += amount;
        emit TaxAccumulated(amount,accumulatedTaxToSwapByAgent[msg.sender]);
    }

    function _distributeSwapFees(uint256 specAmount) internal {
        uint256 splitAmount = specAmount / 2;
        IERC20(spectralToken).transfer(feeWallet, splitAmount);
        IERC20(spectralToken).approve(address(spectralStaking), splitAmount);
        spectralStaking.addDistributionToBuffer(spectralToken, address(0), splitAmount, 0);
        emit TaxDistributed(specAmount);
    }

    function distributeTradingProfitsToStakers(uint256 _amount, address _token) external onlyDistributor {
        require(_token != address(0), "ZERO_ADDRESS");
        require(_amount > 0, "AMOUNT_ZERO");
        require(address(spectralStaking) != address(0), "STAKING_ADDRESS_ZERO");
        IERC20Upgradeable(_token).safeTransferFrom(msg.sender, address(this), _amount);
        IERC20Upgradeable(_token).approve(address(spectralStaking),_amount);
        spectralStaking.addDistribution(_token, address(0), _amount, 0);
        emit ProfitDistributed(_token, _amount);
    }

    function deployUniswapPool(address token) internal whenNotPaused returns(address) {
        address pair;
        try IUniswapV2Factory(uniswapFactory).createPair(token, spectralToken) returns (address createdPair) {
            pair = createdPair;
            agentTokenUniswapPool[token] = pair;
            emit UniswapV2PoolCreated(token, pair);
            return pair;
        } catch {
            pair = IUniswapV2Factory(uniswapFactory).getPair(token, spectralToken);
            emit UniswapV2PoolCreationFailed(token, pair);
            return address(0);
        }
    }

    function withdrawTokens(address token, uint amount) public onlyOwner whenNotPaused {
        require(IERC20Upgradeable(token).balanceOf(address(this)) >= amount, "Insufficient balance");
        IERC20Upgradeable(token).safeTransfer(owner(), amount);
    }

    function withdrawEther(uint amount) public onlyOwner whenNotPaused {
        require(address(this).balance >= amount, "Insufficient balance");
        (bool success, ) = payable(owner()).call{value: amount}("");
        require(success, "Transfer failed.");
    }

    function setParameter(Parameter param, uint256 value) external onlyOwner whenNotPaused {
        parameters[param] = value;
        emit ParameterSet(param, value);
    }

    /* Someone could buy AGENT tokens and set up a pool before liquidity conditions are met in this contract,
    so we need to account for this and potentially set it up in here retrospectively */
    function addAlreadyExistingUniswapPool(address token, address pool) external onlyAdminOrOwner whenNotPaused {
        require(pool != address(0), "ZERO_ADDRESS");
        require(agentTokens[token], "Invalid agent token");
        agentTokenUniswapPool[token] = pool;
        emit UniswapV2PoolCreated(token, pool);
    }

    function setAdmin(address _admin) external onlyOwner whenNotPaused {
        require(_admin != address(0), "ZERO_ADDRESS");
        admin = _admin;
    }

    function upgradeAllAgents(address newImplementation) external onlyOwner {
        require(newImplementation != address(0), "ZERO_ADDRESS");
        agentTokenImplementation = newImplementation;
        updateBeaconLogic(newImplementation);
        ++agentsVersion;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {
        require(newImplementation != address(0), "ZERO_ADDRESS");
        ++version;
    }

    function pause() external OnlyPauserOrOwner {
        paused = true;
    }

    function unpause() external onlyOwner {
        paused = false;
    }

    function isAgentToken(address token) public view returns (bool) {
        return agentTokens[token];
    }

    function setPauser(address _pauser) external onlyOwner() {
        require(_pauser != address(0), "ZERO_ADDRESS");
        pauser = _pauser;
    }

    function setDistributor(address _distributor) external onlyOwner() {
        require(_distributor != address(0), "ZERO_ADDRESS");
        distributor = IOctoDistributor(_distributor);
        emit DistributorSet(_distributor);
    }

    function setSpectralStaking(address _spectralStaking) external onlyOwner() {
        require(_spectralStaking != address(0), "ZERO_ADDRESS");
        spectralStaking = ISpectralStaking(_spectralStaking);
        emit SpectralStakingSet(_spectralStaking);
    }
}