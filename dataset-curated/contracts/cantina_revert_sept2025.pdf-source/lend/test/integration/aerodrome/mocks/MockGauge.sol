// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "../../../../src/interfaces/aerodrome/IGauge.sol";

contract MockGauge is IGauge {
    IERC20 internal immutable _rewardToken;
    address public immutable override stake;
    
    function rewardToken() external view override returns (address) {
        return address(_rewardToken);
    }
    
    mapping(address => uint256) public override balanceOf;
    mapping(uint256 => address) public tokenOwners;
    mapping(address => uint256[]) public userTokens;
    mapping(address => uint256) public rewards;
    
    uint256 public override totalSupply;
    uint256 public rewardRate = 1e18; // 1 AERO per block per token
    
    constructor(address rewardTokenAddress, address _stake) {
        _rewardToken = IERC20(rewardTokenAddress);
        stake = _stake;
    }

    function deposit(uint256 tokenId) external override {
        require(IERC721(stake).ownerOf(tokenId) == msg.sender, "Not owner");
        
        IERC721(stake).transferFrom(msg.sender, address(this), tokenId);
        
        tokenOwners[tokenId] = msg.sender;
        userTokens[msg.sender].push(tokenId);
        balanceOf[msg.sender]++;
        totalSupply++;
        
        emit Deposit(msg.sender, tokenId, 1);
    }

    function depositFor(uint256 tokenId, address recipient) external override {
        require(IERC721(stake).ownerOf(tokenId) == msg.sender, "Not owner");
        
        IERC721(stake).transferFrom(msg.sender, address(this), tokenId);
        
        tokenOwners[tokenId] = recipient;
        userTokens[recipient].push(tokenId);
        balanceOf[recipient]++;
        totalSupply++;
        
        emit Deposit(recipient, tokenId, 1);
    }

    function withdraw(uint256 tokenId) external override {
        require(tokenOwners[tokenId] == msg.sender, "Not owner");
        
        IERC721(stake).transferFrom(address(this), msg.sender, tokenId);
        
        delete tokenOwners[tokenId];
        _removeTokenFromUser(msg.sender, tokenId);
        balanceOf[msg.sender]--;
        totalSupply--;
        
        emit Withdraw(msg.sender, tokenId, 1);
    }

    function getReward() external override {
        uint256 reward = earned(msg.sender);
        if (reward > 0) {
            rewards[msg.sender] = 0;
            _rewardToken.transfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    function getReward(address user) external override {
        uint256 reward = earned(user);
        if (reward > 0) {
            rewards[user] = 0;
            _rewardToken.transfer(user, reward);
            emit RewardPaid(user, reward);
        }
    }

    function getReward(uint256 tokenId) external override {
        address user = tokenOwners[tokenId];
        require(user != address(0), "Token not staked");
        uint256 reward = earned(user);
        if (reward > 0) {
            rewards[user] = 0;
            _rewardToken.transfer(user, reward);
            emit RewardPaid(user, reward);
        }
    }

    function earned(address user) public view override returns (uint256) {
        // Simple mock: 1 AERO per staked position
        return balanceOf[user] * rewardRate + rewards[user];
    }

    function stakedTokenIds(address user) external view override returns (uint256[] memory) {
        return userTokens[user];
    }

    function isStaked(uint256 tokenId) external view override returns (bool) {
        return tokenOwners[tokenId] != address(0);
    }

    function setRewardForUser(address user, uint256 amount) external {
        rewards[user] = amount;
    }

    function _removeTokenFromUser(address user, uint256 tokenId) internal {
        uint256[] storage tokens = userTokens[user];
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == tokenId) {
                tokens[i] = tokens[tokens.length - 1];
                tokens.pop();
                break;
            }
        }
    }
}