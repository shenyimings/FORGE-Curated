// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "../../interfaces/IRewardsPool.sol";
import "../../rewardsPools/RewardsPool.sol";
import "../../tokens/base/ERC677Upgradeable.sol";

/**
 * @title Rewards Pool Controller
 * @notice Acts as a proxy for any number of rewards pools
 */
abstract contract RewardsPoolControllerV1 is
    UUPSUpgradeable,
    OwnableUpgradeable,
    ERC677Upgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;

    mapping(address => IRewardsPool) public tokenPools;
    address[] internal tokens;

    mapping(address => address) public rewardRedirects; // deprecated
    mapping(address => uint256) public redirectedStakes; // deprecated
    mapping(address => address) public redirectApprovals; // deprecated

    event WithdrawRewards(address indexed account);
    event AddToken(address indexed token, address rewardsPool);
    event RemoveToken(address indexed token, address rewardsPool);

    function __RewardsPoolController_init(
        string memory _derivativeTokenName,
        string memory _derivativeTokenSymbol
    ) public onlyInitializing {
        __ERC677_init(_derivativeTokenName, _derivativeTokenSymbol, 0);
        __Ownable_init();
        __UUPSUpgradeable_init();
    }

    modifier updateRewards(address _account) {
        _updateRewards(_account);
        _;
    }

    /**
     * @notice returns a list of supported tokens
     * @return list of token addresses
     **/
    function supportedTokens() external view returns (address[] memory) {
        return tokens;
    }

    /**
     * @notice returns true/false to whether a given token is supported
     * @param _token token address
     * @return is token supported
     **/
    function isTokenSupported(address _token) public view returns (bool) {
        return address(tokenPools[_token]) != address(0) ? true : false;
    }

    /**
     * @notice returns balances of supported tokens within the controller
     * @return list of supported tokens
     * @return list of token balances
     **/
    function tokenBalances() external view returns (address[] memory, uint256[] memory) {
        uint256[] memory balances = new uint256[](tokens.length);

        for (uint256 i = 0; i < tokens.length; i++) {
            balances[i] = IERC20Upgradeable(tokens[i]).balanceOf(address(this));
        }

        return (tokens, balances);
    }

    /**
     * @notice ERC677 implementation to receive a token distribution
     **/
    function onTokenTransfer(address, uint256, bytes calldata) external virtual {
        if (isTokenSupported(msg.sender)) {
            distributeToken(msg.sender);
        }
    }

    /**
     * @notice returns an account's staked amount for use by reward pools
     * controlled by this contract
     * @param _account account address
     * @return account's staked amount
     */
    function staked(address _account) external view virtual returns (uint256) {
        return balanceOf(_account);
    }

    /**
     * @notice returns the total staked amount for use by reward pools
     * controlled by this contract
     * @return total staked amount
     */
    function totalStaked() external view virtual returns (uint256) {
        return totalSupply();
    }

    /**
     * @dev updates the rewards of the sender and receiver
     * @param _from account sending from
     * @param _to account sending to
     * @param _amount amount being sent
     */
    function _transfer(
        address _from,
        address _to,
        uint256 _amount
    ) internal virtual override updateRewards(_from) updateRewards(_to) {
        super._transfer(_from, _to, _amount);
    }

    /**
     * @notice distributes token balances to their respective rewards pools
     * @param _tokens list of token addresses
     */
    function distributeTokens(address[] memory _tokens) public {
        for (uint256 i = 0; i < _tokens.length; i++) {
            distributeToken(_tokens[i]);
        }
    }

    /**
     * @notice distributes a token balance to its respective rewards pool
     * @param _token token address
     */
    function distributeToken(address _token) public {
        require(isTokenSupported(_token), "Token not supported");

        IERC20Upgradeable token = IERC20Upgradeable(_token);
        uint256 balance = token.balanceOf(address(this));
        require(balance > 0, "Cannot distribute zero balance");

        token.safeTransfer(address(tokenPools[_token]), balance);
        tokenPools[_token].distributeRewards();
    }

    /**
     * @notice returns a list of withdrawable rewards for an account
     * @param _account account address
     * @return list of withdrawable reward amounts
     **/
    function withdrawableRewards(address _account) external view returns (uint256[] memory) {
        uint256[] memory withdrawable = new uint256[](tokens.length);

        for (uint256 i = 0; i < tokens.length; i++) {
            withdrawable[i] = tokenPools[tokens[i]].withdrawableRewards(_account);
        }

        return withdrawable;
    }

    /**
     * @notice withdraws an account's earned rewards for a list of tokens
     * @param _tokens list of token addresses to withdraw rewards from
     **/
    function withdrawRewards(address[] memory _tokens) public {
        for (uint256 i = 0; i < _tokens.length; i++) {
            tokenPools[_tokens[i]].withdraw(msg.sender);
        }
        emit WithdrawRewards(msg.sender);
    }

    /**
     * @notice adds a new token
     * @param _token token to add
     * @param _rewardsPool token rewards pool to add
     **/
    function addToken(address _token, address _rewardsPool) public onlyOwner {
        require(!isTokenSupported(_token), "Token is already supported");

        tokenPools[_token] = IRewardsPool(_rewardsPool);
        tokens.push(_token);

        if (IERC20Upgradeable(_token).balanceOf(address(this)) > 0) {
            distributeToken(_token);
        }

        emit AddToken(_token, _rewardsPool);
    }

    /**
     * @notice removes a supported token
     * @param _token address of token
     **/
    function removeToken(address _token) external onlyOwner {
        require(isTokenSupported(_token), "Token is not supported");

        IRewardsPool rewardsPool = tokenPools[_token];
        delete (tokenPools[_token]);
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == _token) {
                tokens[i] = tokens[tokens.length - 1];
                tokens.pop();
                break;
            }
        }

        emit RemoveToken(_token, address(rewardsPool));
    }

    /**
     * @dev triggers a reward update for a given account
     * @param _account account to update rewards for
     */
    function _updateRewards(address _account) internal {
        for (uint256 i = 0; i < tokens.length; i++) {
            tokenPools[tokens[i]].updateReward(_account);
        }
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
