// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "../libraries/math/SafeMath.sol";
import "../libraries/token/IERC20.sol";
import "../libraries/token/SafeERC20.sol";
import "../libraries/utils/ReentrancyGuard.sol";
import "../libraries/utils/Address.sol";

import "./interfaces/IRewardTracker.sol";
import "../tokens/interfaces/IMintable.sol";
import "../tokens/interfaces/IWETH.sol";
import "../access/Governable.sol";

contract StakingRewardRouter is ReentrancyGuard, Governable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Address for address payable;

    bool public isInitialized;

    address public stakingToken; // 1st reward token
    address public weth; // 2nd reward token
    address public bnToken; // multiplier points

    address public stakedTokenTracker;
    address public bonusTokenTracker;
    address public feeTokenTracker;

    event Stake(address account, address token, uint256 amount);
    event Unstake(address account, address token, uint256 amount);

    receive() external payable {
        require(msg.sender == weth, "Router: invalid sender");
    }

    function initialize(
        address _weth,
        address _stakingToken,
        address _bnToken,
        address _stakedTokenTracker,
        address _bonusTokenTracker,
        address _feeTokenTracker
    ) external onlyGov {
        require(!isInitialized, "RewardRouter: already initialized");
        isInitialized = true;

        weth = _weth;
        stakingToken = _stakingToken;
        bnToken = _bnToken;

        stakedTokenTracker = _stakedTokenTracker;
        bonusTokenTracker = _bonusTokenTracker;
        feeTokenTracker = _feeTokenTracker;
    }

    // to help users who accidentally send their tokens to this contract
    function withdrawToken(address _token, address _account, uint256 _amount) external onlyGov {
        IERC20(_token).safeTransfer(_account, _amount);
    }

    function batchStakeForAccount(address[] memory _accounts, uint256[] memory _amounts) external nonReentrant onlyGov {
        address _stakingToken = stakingToken;
        for (uint256 i = 0; i < _accounts.length; i++) {
            _stake(msg.sender, _accounts[i], _stakingToken, _amounts[i]);
        }
    }

    function stakeForAccount(address _account, uint256 _amount) external nonReentrant onlyGov {
        _stake(msg.sender, _account, stakingToken, _amount);
    }

    function stake(uint256 _amount) external nonReentrant {
        _stake(msg.sender, msg.sender, stakingToken, _amount);
    }

    function unstake(uint256 _amount) external nonReentrant {
        _unstake(msg.sender, stakingToken, _amount, true);
    }

    function claim() external nonReentrant {
        address account = msg.sender;

        IRewardTracker(feeTokenTracker).claimForAccount(account, account);
        IRewardTracker(stakedTokenTracker).claimForAccount(account, account);
    }

    function claimNativeRewards() external nonReentrant {
        address account = msg.sender;

        IRewardTracker(stakedTokenTracker).claimForAccount(account, account);
    }

    function claimWETH() external nonReentrant {
        address account = msg.sender;

        IRewardTracker(feeTokenTracker).claimForAccount(account, account);
    }

    function compound() external nonReentrant {
        _compound(msg.sender);
    }

    function compoundForAccount(address _account) external nonReentrant onlyGov {
        _compound(_account);
    }

    function batchCompoundForAccounts(address[] memory _accounts) external nonReentrant onlyGov {
        for (uint256 i = 0; i < _accounts.length; i++) {
            _compound(_accounts[i]);
        }
    }

    function handleRewards(
        bool _shouldClaimNativeRewards,
        bool _shouldStakeMultiplierPoints,
        bool _shouldClaimWeth,
        bool _shouldConvertWethToEth
    ) external nonReentrant {
        address account = msg.sender;

        uint256 nativeRewardsAmount = 0;
        if (_shouldClaimNativeRewards) {
            nativeRewardsAmount = IRewardTracker(stakedTokenTracker).claimForAccount(account, account);
        }

        if (_shouldStakeMultiplierPoints) {
            uint256 bnTokenAmount = IRewardTracker(bonusTokenTracker).claimForAccount(account, account);
            if (bnTokenAmount > 0) {
                IRewardTracker(feeTokenTracker).stakeForAccount(account, account, bnToken, bnTokenAmount);
            }
        }

        if (_shouldClaimWeth) {
            if (_shouldConvertWethToEth) {
                uint256 wethAmount = IRewardTracker(feeTokenTracker).claimForAccount(account, address(this));

                IWETH(weth).withdraw(wethAmount);

                payable(account).sendValue(wethAmount);
            } else {
                IRewardTracker(feeTokenTracker).claimForAccount(account, account);
            }
        }
    }

    function _compound(address _account) private {
        uint256 nativeRewardsAmount = IRewardTracker(stakedTokenTracker).claimForAccount(_account, _account);
        if (nativeRewardsAmount > 0) {
            _stake(_account, _account, stakingToken, nativeRewardsAmount);
        }

        uint256 bnTokenAmount = IRewardTracker(bonusTokenTracker).claimForAccount(_account, _account);
        if (bnTokenAmount > 0) {
            IRewardTracker(feeTokenTracker).stakeForAccount(_account, _account, bnToken, bnTokenAmount);
        }
    }

    function _stake(address _fundingAccount, address _account, address _token, uint256 _amount) private {
        require(_amount > 0, "RewardRouter: invalid _amount");

        IRewardTracker(stakedTokenTracker).stakeForAccount(_fundingAccount, _account, _token, _amount);
        IRewardTracker(bonusTokenTracker).stakeForAccount(_account, _account, stakedTokenTracker, _amount);
        IRewardTracker(feeTokenTracker).stakeForAccount(_account, _account, bonusTokenTracker, _amount);

        emit Stake(_account, _token, _amount);
    }

    function _unstake(address _account, address _token, uint256 _amount, bool _shouldReduceBnBmx) private {
        require(_amount > 0, "RewardRouter: invalid _amount");

        uint256 balance = IRewardTracker(stakedTokenTracker).stakedAmounts(_account);

        IRewardTracker(feeTokenTracker).unstakeForAccount(_account, bonusTokenTracker, _amount, _account);
        IRewardTracker(bonusTokenTracker).unstakeForAccount(_account, stakedTokenTracker, _amount, _account);
        IRewardTracker(stakedTokenTracker).unstakeForAccount(_account, _token, _amount, _account);

        if (_shouldReduceBnBmx) {
            uint256 bnTokenAmount = IRewardTracker(bonusTokenTracker).claimForAccount(_account, _account);
            if (bnTokenAmount > 0) {
                IRewardTracker(feeTokenTracker).stakeForAccount(_account, _account, bnToken, bnTokenAmount);
            }

            uint256 stakedBnBmx = IRewardTracker(feeTokenTracker).depositBalances(_account, bnToken);
            if (stakedBnBmx > 0) {
                uint256 reductionAmount = stakedBnBmx.mul(_amount).div(balance);
                IRewardTracker(feeTokenTracker).unstakeForAccount(_account, bnToken, reductionAmount, _account);
                IMintable(bnToken).burn(_account, reductionAmount);
            }
        }

        emit Unstake(_account, _token, _amount);
    }
}
