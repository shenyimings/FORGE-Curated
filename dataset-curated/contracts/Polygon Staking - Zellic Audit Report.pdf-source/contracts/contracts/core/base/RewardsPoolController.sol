// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "../interfaces/IRewardsPool.sol";
import "../rewardsPools/RewardsPool.sol";

/**
 * @title Rewards Pool Controller
 * @notice Acts as a proxy for any number of rewards pools
 */
abstract contract RewardsPoolController is UUPSUpgradeable, OwnableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    mapping(address => IRewardsPool) public tokenPools;
    address[] internal tokens;

    event WithdrawRewards(address indexed account);
    event AddToken(address indexed token, address rewardsPool);
    event RemoveToken(address indexed token, address rewardsPool);

    error InvalidToken();
    error NothingToDistribute();

    function __RewardsPoolController_init() public onlyInitializing {
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

        for (uint256 i = 0; i < tokens.length; ++i) {
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
    function staked(address _account) external view virtual returns (uint256);

    /**
     * @notice returns the total staked amount for use by reward pools
     * controlled by this contract
     * @return total staked amount
     */
    function totalStaked() external view virtual returns (uint256);

    /**
     * @notice distributes token balances to their respective rewards pools
     * @param _tokens list of token addresses
     */
    function distributeTokens(address[] memory _tokens) public {
        for (uint256 i = 0; i < _tokens.length; ++i) {
            distributeToken(_tokens[i]);
        }
    }

    /**
     * @notice distributes a token balance to its respective rewards pool
     * @param _token token address
     */
    function distributeToken(address _token) public {
        if (!isTokenSupported(_token)) revert InvalidToken();

        IERC20Upgradeable token = IERC20Upgradeable(_token);
        uint256 balance = token.balanceOf(address(this));
        if (balance == 0) revert NothingToDistribute();

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

        for (uint256 i = 0; i < tokens.length; ++i) {
            withdrawable[i] = tokenPools[tokens[i]].withdrawableRewards(_account);
        }

        return withdrawable;
    }

    /**
     * @notice withdraws an account's earned rewards for a list of tokens
     * @param _tokens list of token addresses to withdraw rewards from
     **/
    function withdrawRewards(address[] memory _tokens) public {
        for (uint256 i = 0; i < _tokens.length; ++i) {
            tokenPools[_tokens[i]].withdraw(msg.sender);
        }
        emit WithdrawRewards(msg.sender);
    }

    /**
     * @notice adds a new token
     * @param _token token to add
     * @param _rewardsPool token rewards pool to add
     **/
    function addToken(address _token, address _rewardsPool) public virtual onlyOwner {
        if (isTokenSupported(_token)) revert InvalidToken();

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
        if (!isTokenSupported(_token)) revert InvalidToken();

        IRewardsPool rewardsPool = tokenPools[_token];
        delete (tokenPools[_token]);
        for (uint256 i = 0; i < tokens.length; ++i) {
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
        for (uint256 i = 0; i < tokens.length; ++i) {
            tokenPools[tokens[i]].updateReward(_account);
        }
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
