// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "../interfaces/IAutonomousAgentDeployer.sol";
import "../interfaces/IAgenticCompany.sol";
import "../interfaces/IAgenticCompanyFactory.sol";
import "../interfaces/IANSReverseRegistrar.sol";
import "../interfaces/IANSResolver.sol";
import "../interfaces/IAgentBalances.sol";
import "../interfaces/IAgentToken.sol";

contract OctoDistributor is
    IOctoDistributor,
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeERC20 for IERC20;

    struct SystemAddresses {
        IAutonomousAgentDeployer autonomousDeployer;
        IAgenticCompanyFactory agenticCompanyFactory;
        IANSResolver ansResolver;
        IANSReverseRegistrar ansReverseRegistrar;
        address spectralTreasury;
    }

    uint256 public spectraCompanyIndex;

    IERC20Upgradeable public spectral_token;
    IERC20 public usdc_token;

    uint8 public version;
    address public admin;
    uint256 public constant PRECISION = 10**4;

    enum Parameter {
        TRADING_REWARDS_TREASURY_CUT,
        TRADING_REWARDS_CREATOR_CUT,
        TRADING_REWARDS_SPECTRA_CUT,
        TRADING_REWARDS_EMPLOYEES_CUT
    }

    struct UserBalances {
        uint256 spectral;
        uint256 usdc;
        mapping(address => uint256 balance) agent_tokens_list;
        mapping(address => uint256 index) agent_tokens_indecies;
        address[] agent_tokens;
    }

    SystemAddresses public systemAddresses;
    mapping(Parameter => uint256) public parameters;
    mapping(address => UserBalances) public userBalances;
    mapping(address => address) public agentCreators;

    event Withdraw(address indexed user, address indexed token, uint256 amount);
    event DistributeHiringBonuses(
        address indexed company,
        address indexed agentToken,
        uint256 count,
        uint256 totalSpec,
        uint256 totalAgentToken,
        uint256 totalUsdc,
        HiringDistributionByAddress[] distributions
    );
    event DistributeTradingRewards (
        address indexed agentToken,
        uint256 usdcAmount,
        address[] beneficiaries,
        uint256[] amounts
    );
    event SetParameter(Parameter parameter, uint256 value);
    event SetAgentCreator(address agentToken, address creator);
    event SetAdmin(address admin);
    event SetSpectraCompanyIndex(uint256 index);
    event UpdateSystemAddress(uint8 index, address newAddress);
    event Upgrade(address newImplementation, uint8 version);

    modifier onlyAutonomousDeployer() {
        require(
            msg.sender == address(systemAddresses.autonomousDeployer),
            "ONLY_AUTONOMOUS_DEPLOYER"
        );
        _;
    }
    modifier onlyAgenticCompany() {
        require(
            systemAddresses.agenticCompanyFactory.isCompany(msg.sender) || msg.sender == admin,
            "ONLY_AGENTIC_COMPANY_CAN_DISTRIBUTE"
        );
        _;
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "ONLY_ADMIN");
        _;
    }

    modifier onlyAdminOrOwner() {
        require(msg.sender == admin || msg.sender == owner(), "ONLY_ADMIN_OR_OWNER");
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _autonomousDeployer,
        address _agenticCompanyFactory,
        address _ansResolver,
        address _ansReverseRegistrar,
        address _spectralTreasury,
        uint256 _spectraCompanyIndex,
        address _usdc_token,
        address _spectral_token
    ) public initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
        admin = msg.sender;
        require(_autonomousDeployer != address(0), "AUTONOMOUS_ZERO_ADDRESS");
        require(_ansResolver != address(0), "ANS_RESOLVER_ZERO_ADDRESS");
        require(_ansReverseRegistrar != address(0), "ANS_REVERSE_REGISTRY_ZERO_ADDRESS");
        require(_spectralTreasury != address(0), "SPECTRAL_TREASURY_ZERO_ADDRESS");
        require(_usdc_token != address(0), "USDC_ZERO_ADDRESS");
        require(_spectral_token != address(0), "SPEC_ZERO_ADDRESS");
        // We don't check the _agenticCompanyFactory since both contracts depend on each other and we may deploy this contract first then set the factory address
        systemAddresses.autonomousDeployer = IAutonomousAgentDeployer(_autonomousDeployer);
        systemAddresses.agenticCompanyFactory = IAgenticCompanyFactory(_agenticCompanyFactory);
        systemAddresses.ansResolver = IANSResolver(_ansResolver);
        systemAddresses.ansReverseRegistrar = IANSReverseRegistrar(_ansReverseRegistrar);
        systemAddresses.spectralTreasury = _spectralTreasury;
        usdc_token = IERC20(_usdc_token);
        spectral_token = IERC20Upgradeable(_spectral_token);
        spectraCompanyIndex = _spectraCompanyIndex;
        parameters[Parameter.TRADING_REWARDS_TREASURY_CUT] = 2500;
        parameters[Parameter.TRADING_REWARDS_CREATOR_CUT] = 7500;
        parameters[Parameter.TRADING_REWARDS_SPECTRA_CUT] = 0;
        parameters[Parameter.TRADING_REWARDS_EMPLOYEES_CUT] = 2500;
        version = 1;
    }

    function setAgenticCompanyFactory(address _agenticCompanyFactory) external onlyOwner {
        require(_agenticCompanyFactory != address(0), "ZERO_ADDRESS");
        systemAddresses.agenticCompanyFactory = IAgenticCompanyFactory(_agenticCompanyFactory);
        emit UpdateSystemAddress(1, _agenticCompanyFactory);
    }

    function withdraw(address _token, uint256 _amount) external nonReentrant {
        require(_amount > 0, "AMOUNT_ZERO");
        require(_token != address(0), "ZERO_ADDRESS");
        UserBalances storage user = userBalances[msg.sender];
        if (_token == address(spectral_token)) {
            require(user.spectral >= _amount, "INSUFFICIENT_BALANCE");
            user.spectral -= _amount;
        } else if (_token == address(usdc_token)) {
            require(user.usdc >= _amount, "INSUFFICIENT_BALANCE");
            user.usdc -= _amount;
        } else {
            require(
                user.agent_tokens_list[_token] >= _amount,
                "INSUFFICIENT_BALANCE"
            );
            user.agent_tokens_list[_token] -= _amount;
            if (user.agent_tokens_list[_token] == 0) {
                _removeAgentToken(user, _token);
            }
        }
        IERC20Upgradeable(_token).safeTransfer(msg.sender, _amount);
        emit Withdraw(msg.sender, _token, _amount);
    }

    function getUserAgentTokensCount(address user)
        external
        view
        returns (uint256)
    {
        return userBalances[user].agent_tokens.length;
    }

    function setParameters(
        Parameter[] calldata _parameters,
        uint256[] calldata _values
    ) external onlyOwner {
        // Parameters need to be checked:
        // parameters[Parameter.TRADING_REWARDS_TREASURY_CUT] + parameters[Parameter.TRADING_REWARDS_CREATOR_CUT] = 10000;
        // parameters[Parameter.TRADING_REWARDS_TREASURY_CUT] + parameters[Parameter.TRADING_REWARDS_SPECTRA_CUT] + parameters[Parameter.TRADING_REWARDS_EMPLOYEES_CUT] = 5000;
        require(_parameters.length == _values.length, "INVALID_LENGTH");
        for (uint256 i = 0; i < _parameters.length; i++) {
            require(_values[i] <= PRECISION, "PARAMETER_OUT_OF_RANGE");
            parameters[_parameters[i]] = _values[i];
            emit SetParameter(_parameters[i], _values[i]);
        }
        require(
            parameters[Parameter.TRADING_REWARDS_TREASURY_CUT] +
                parameters[Parameter.TRADING_REWARDS_CREATOR_CUT] ==
                PRECISION,
            "INVALID_CREATOR_CUT"
        );
        require(
            parameters[Parameter.TRADING_REWARDS_TREASURY_CUT] +
                parameters[Parameter.TRADING_REWARDS_SPECTRA_CUT] +
                parameters[Parameter.TRADING_REWARDS_EMPLOYEES_CUT] ==
                PRECISION / 2,
            "INVALID_SPECTRA_CUT"
        );
    }

    function withdrawAllAgentTokens(uint256 start_index, uint256 end_index) external nonReentrant {
        require(start_index < end_index, "INVALID_INDEX");
        require(end_index <= userBalances[msg.sender].agent_tokens.length, "INVALID_INDEX");
        for (uint256 i = start_index; i < end_index; i++) {
            address token = userBalances[msg.sender].agent_tokens[i];
            uint256 amount = userBalances[msg.sender].agent_tokens_list[token];
            require(amount > 0, "AMOUNT_ZERO");
            userBalances[msg.sender].agent_tokens_list[token] = 0;
            IERC20Upgradeable(token).safeTransfer(msg.sender, amount);
            emit Withdraw(msg.sender, token, amount);
        }
        
        for (uint256 i = end_index - 1; i >= start_index; ) {
        	_removeAgentToken(userBalances[msg.sender], userBalances[msg.sender].agent_tokens[i]);
        	if (i == 0) {
        		break;
        	}
        	i --;
        }
    }

    function withdrawAllAgentTokensByAddresses(address[] calldata tokens) external nonReentrant {
        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 amount = userBalances[msg.sender].agent_tokens_list[tokens[i]];
            require(amount > 0, "AMOUNT_ZERO");
            userBalances[msg.sender].agent_tokens_list[tokens[i]] = 0;
            _removeAgentToken(userBalances[msg.sender], tokens[i]);
            IERC20Upgradeable(tokens[i]).safeTransfer(msg.sender, amount);
            emit Withdraw(msg.sender, tokens[i], amount);
        }
    }

    function transferTradingRewards(
        address agentToken,
        uint256 usdcAmount,
        TradingDistribution[] calldata contributors,
        address altTreasury
    ) external nonReentrant onlyAdmin() {
        require(agentToken != address(0), "ZERO_ADDRESS");
        require(usdcAmount > 0, "AMOUNT_ZERO");
        address[] memory beneficiaries;
        uint256[] memory amounts;
        usdc_token.safeTransferFrom(msg.sender, address(this), usdcAmount);
        uint256 remaining = usdcAmount;
        if(keccak256(abi.encodePacked("SPECTR")) == keccak256(abi.encodePacked(IAgentToken(agentToken).symbol()))) {
            uint256 employeesAmount = (usdcAmount * parameters[Parameter.TRADING_REWARDS_EMPLOYEES_CUT]) / PRECISION;
            uint256 socialContributorsAmount = (usdcAmount * 2500) / PRECISION;
            uint256 stakersAmount = (usdcAmount * 2500) / PRECISION;
            remaining -= stakersAmount;
            usdc_token.approve(address(systemAddresses.autonomousDeployer), stakersAmount);
            systemAddresses.autonomousDeployer.distributeTradingProfitsToStakers(stakersAmount, address(usdc_token));
            uint256 employeeCount = IAgenticCompany(systemAddresses.agenticCompanyFactory.getCompanyAddressAtIndex(spectraCompanyIndex)).employeeCount();
            require(employeeCount > 0, "NO_EMPLOYEES");
            // If contributors are 0 though, it will increase remaining and end up in treasury
            uint256 contributorCount = contributors.length;
            beneficiaries = new address[](employeeCount + contributorCount);
            amounts = new uint256[](employeeCount + contributorCount);
            uint256 perEmployeeAmount = employeesAmount / employeeCount;
            remaining -= (perEmployeeAmount * employeeCount);
            for (uint256 i = 0; i < employeeCount; i++) {
                address employee = _getAnsAddress(IAgenticCompany(systemAddresses.agenticCompanyFactory.getCompanyAddressAtIndex(spectraCompanyIndex)).getEmployeeAtIndex(i));
                userBalances[employee].usdc += perEmployeeAmount;
                beneficiaries[i] = employee;
                amounts[i] = perEmployeeAmount;
            }
            if(contributorCount == 0) {
                require(altTreasury != address(0), "ALT_TREASURY_ZERO_ADDRESS");
                usdc_token.safeTransfer(altTreasury, socialContributorsAmount);
                remaining -= socialContributorsAmount;
            }else
            {
                uint256 contributorSum = 0;
                for (uint256 j = 0; j < contributorCount; j++) {
                    remaining -= contributors[j].amount;
                    contributorSum += contributors[j].amount;
                    address contributor = _getAnsAddress(contributors[j].recipientAnsNode);
                    userBalances[contributor].usdc += contributors[j].amount;
                    beneficiaries[employeeCount + j] = contributor;
                    amounts[employeeCount + j] = contributors[j].amount;
                }
                require(contributorSum <= socialContributorsAmount, "INCORRECT_CONTRIBUTORS_AMOUNT");
            }
            emit DistributeTradingRewards(agentToken, usdcAmount, beneficiaries, amounts);
        } else {
            uint256 creatorAmount = (usdcAmount * parameters[Parameter.TRADING_REWARDS_CREATOR_CUT]) / PRECISION;
            remaining -= creatorAmount;
            require(agentCreators[agentToken] != address(0), "CREATOR_NOT_SET");
            userBalances[agentCreators[agentToken]].usdc += creatorAmount;
            beneficiaries = new address[](1);
            amounts = new uint256[](1);
            beneficiaries[0] = agentCreators[agentToken];
            amounts[0] = creatorAmount;
            emit DistributeTradingRewards(agentToken, usdcAmount,beneficiaries,amounts);
        }
        require(remaining >= (usdcAmount * parameters[Parameter.TRADING_REWARDS_TREASURY_CUT]) / PRECISION, "INSUFFICIENT_TREASURY_CUT");
        usdc_token.safeTransfer(systemAddresses.spectralTreasury, remaining);
    }
    
    
    function _addOrGetAgentToken(UserBalances storage user, address token) internal returns (uint256) {
        uint256 index = user.agent_tokens_indecies[token];
        
        if (index >= user.agent_tokens.length || user.agent_tokens[index] != token) {
            // Add to array
            user.agent_tokens.push(token);
            // Store and return new array index
            index = user.agent_tokens.length - 1;
            user.agent_tokens_indecies[token] = index;
        }
        
        return index;
    }

    function _removeAgentToken(UserBalances storage user, address token) internal {
        uint256 index = user.agent_tokens_indecies[token];
        require(index < user.agent_tokens.length, "Token not found");
        
        // Get the last element
        address lastToken = user.agent_tokens[user.agent_tokens.length - 1];

        // Move last element to the position we're deleting
        user.agent_tokens[index] = lastToken;
        // Update the index mapping for the moved token
        user.agent_tokens_indecies[lastToken] = index;
        
        // Remove token's index from mapping
        delete user.agent_tokens_indecies[token];
        
        // Remove last element
        user.agent_tokens.pop();
    }

    function transferHiringDistributions(
        HiringDistribution[] calldata distributions,
        address agentToken,
        uint256 totalSpec,
        uint256 totalAgentToken,
        uint256 totalUsdc
    ) external nonReentrant onlyAgenticCompany() {
        require(
            distributions.length > 0,
            "DISTRIBUTIONS_MUST_BE_PROVIDED"
        );
        HiringDistributionByAddress[] memory distributionsByAddress = new HiringDistributionByAddress[](distributions.length);
        usdc_token.safeTransferFrom(msg.sender, address(this), totalUsdc);
        spectral_token.safeTransferFrom(msg.sender, address(this), totalSpec);
        if(agentToken != address(0) && totalAgentToken > 0) {
            IERC20Upgradeable(agentToken).safeTransferFrom(msg.sender, address(this), totalAgentToken);
        }
        uint256 accSpecAmount = 0;
        uint256 accAgentTokenAmount = 0;
        uint256 accUsdcAmount = 0;
        for (uint256 i = 0; i < distributions.length; i++) {
            address recipient = _getAnsAddress(distributions[i].recipientAnsNode);
            distributionsByAddress[i] = HiringDistributionByAddress(
                recipient,
                distributions[i].specAmount,
                distributions[i].agentTokenAmount,
                distributions[i].usdcAmount
            );
            UserBalances storage user = userBalances[
                recipient
            ];
            user.spectral += distributions[i].specAmount;
            accSpecAmount += distributions[i].specAmount;
            if (agentToken != address(0) && totalAgentToken > 0) {
                _addOrGetAgentToken(user, agentToken);
                user.agent_tokens_list[agentToken] += distributions[i].agentTokenAmount;
                accAgentTokenAmount += distributions[i].agentTokenAmount;
            }
            user.usdc += distributions[i].usdcAmount;
            accUsdcAmount += distributions[i].usdcAmount;
        }
        require(accSpecAmount == totalSpec, "INCORRECT_SPEC_AMOUNT");
        require(agentToken == address(0) || totalAgentToken == 0 || accAgentTokenAmount == totalAgentToken, "INCORRECT_AGENT_TOKEN_AMOUNT");
        require(accUsdcAmount == totalUsdc, "INCORRECT_USDC_AMOUNT");
        emit DistributeHiringBonuses(
            msg.sender,
            agentToken,
            distributions.length,
            totalSpec,
            totalAgentToken,
            totalUsdc,
            distributionsByAddress
        );
    }

    function setAgentCreator(address agentToken, address creator)
        external
        onlyAutonomousDeployer
    {
        require(agentToken != address(0), "ZERO_ADDRESS");
        require(creator != address(0), "ZERO_ADDRESS");
        agentCreators[agentToken] = creator;
        emit SetAgentCreator(agentToken, creator);
    }

    function _getAnsAddress(bytes32 node) internal view returns (address add_) {
        add_ = systemAddresses.ansResolver.addr(node);
        if (add_ == address(0)) {
            revert AnsNodeMustResolveToAddress(node);
        }
    }

    function setAgentCreatorsBatch(
        address[] calldata agentTokens,
        address[] calldata creators
    ) external onlyOwner {
        require(agentTokens.length == creators.length, "INVALID_LENGTH");
        for (uint256 i = 0; i < agentTokens.length; i++) {
            require(agentTokens[i] != address(0), "ZERO_ADDRESS");
            require(creators[i] != address(0), "ZERO_ADDRESS");
            agentCreators[agentTokens[i]] = creators[i];
            emit SetAgentCreator(agentTokens[i], creators[i]);
        }
    }

    function setAdmin(address _admin) external onlyOwner {
        require(_admin != address(0), "ZERO_ADDRESS");
        admin = _admin;
        emit SetAdmin(_admin);
    }

    function updateSystemAddress(
    uint8 index,
    address newAddress
    ) external onlyOwner {
        require(index < 5, "INVALID_INDEX");
        require(newAddress != address(0), "ZERO_ADDRESS");
        
        assembly {
            // Store new address at the correct slot
            sstore(add(systemAddresses.slot, index), newAddress)
        }
        emit UpdateSystemAddress(index, newAddress);
    }

    function setSpectraCompanyIndex(uint256 index) external onlyOwner {
        require(index < systemAddresses.agenticCompanyFactory.companyCount(), "INVALID_INDEX");
        spectraCompanyIndex = index;
        emit SetSpectraCompanyIndex(index);
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {
        require(newImplementation != address(0), "ZERO_ADDRESS");
        ++version;
        emit Upgrade(newImplementation, version);
    }

    function getUserAgentBalance(address user, address agentToken)
        external
        view
        returns (uint256)
    {
        return userBalances[user].agent_tokens_list[agentToken];
    }
}
