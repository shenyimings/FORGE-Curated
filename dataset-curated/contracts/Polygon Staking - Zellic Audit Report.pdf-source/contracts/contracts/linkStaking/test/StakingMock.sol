// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../../core/interfaces/IERC677.sol";
import "../../core/interfaces/IERC677Receiver.sol";

/**
 * @title Staking Mock
 * @dev Mocks contract for testing
 */
contract StakingMock is IERC677Receiver {
    using SafeERC20 for IERC677;

    struct Staker {
        uint256 unbondingPeriodEndsAt;
        uint256 claimPeriodEndsAt;
        uint256 principal;
        uint256 removedPrincipal;
    }

    IERC677 public token;
    address public rewardVault;

    uint256 public depositMin;
    uint256 public depositMax;
    uint256 public maxPoolSize;

    uint256 public unbondingPeriod;
    uint256 public claimPeriod;

    bool public active;

    mapping(address => Staker) public stakers;
    mapping(address => bool) public isRemoved;

    error UnbondingPeriodActive();
    error NotInClaimPeriod();
    error UnstakeZeroAmount();
    error UnstakeExceedsPrincipal();
    error UnstakePrincipalBelowMinAmount();

    constructor(
        address _token,
        address _rewardVault,
        uint256 _depositMin,
        uint256 _depositMax,
        uint256 _maxPoolSize,
        uint256 _unbondingPeriod,
        uint256 _claimPeriod
    ) {
        token = IERC677(_token);
        rewardVault = _rewardVault;
        active = true;
        depositMin = _depositMin;
        depositMax = _depositMax;
        maxPoolSize = _maxPoolSize;
        unbondingPeriod = _unbondingPeriod;
        claimPeriod = _claimPeriod;
    }

    function onTokenTransfer(address _sender, uint256 _value, bytes calldata _data) external {
        require(msg.sender == address(token), "has to be token");
        if (_data.length != 0) {
            address sender = abi.decode(_data, (address));
            stakers[sender].principal += _value;
        } else {
            stakers[_sender].principal += _value;
        }

        delete stakers[_sender].unbondingPeriodEndsAt;
        delete stakers[_sender].claimPeriodEndsAt;
    }

    function unbond() external {
        Staker memory staker = stakers[msg.sender];

        if (staker.unbondingPeriodEndsAt != 0 && block.timestamp <= staker.claimPeriodEndsAt) {
            revert UnbondingPeriodActive();
        }

        staker.unbondingPeriodEndsAt = block.timestamp + unbondingPeriod;
        staker.claimPeriodEndsAt = staker.unbondingPeriodEndsAt + claimPeriod;
        stakers[msg.sender] = staker;
    }

    function unstake(uint256 _amount) external {
        Staker memory staker = stakers[msg.sender];

        if (
            staker.unbondingPeriodEndsAt == 0 ||
            block.timestamp < staker.unbondingPeriodEndsAt ||
            block.timestamp > staker.claimPeriodEndsAt
        ) {
            revert NotInClaimPeriod();
        }
        if (_amount == 0) revert UnstakeZeroAmount();

        if (_amount > staker.principal) revert UnstakeExceedsPrincipal();

        uint256 updatedPrincipal = staker.principal - _amount;
        if (_amount < staker.principal && updatedPrincipal < depositMin) {
            revert UnstakePrincipalBelowMinAmount();
        }

        stakers[msg.sender].principal -= _amount;
        token.safeTransfer(msg.sender, _amount);
    }

    function getStakerLimits() external view returns (uint256, uint256) {
        return (depositMin, depositMax);
    }

    function getMaxPoolSize() external view returns (uint256) {
        return maxPoolSize;
    }

    function getTotalPrincipal() external view returns (uint256) {
        return token.balanceOf(address(this));
    }

    function getStakerPrincipal(address _staker) external view returns (uint256) {
        return stakers[_staker].principal;
    }

    function getRemovedPrincipal(address _staker) external view returns (uint256) {
        return stakers[_staker].removedPrincipal;
    }

    function getUnbondingEndsAt(address _staker) external view returns (uint256) {
        return stakers[_staker].unbondingPeriodEndsAt;
    }

    function getClaimPeriodEndsAt(address _staker) external view returns (uint256) {
        return stakers[_staker].claimPeriodEndsAt;
    }

    function getRewardVault() external view returns (address) {
        return rewardVault;
    }

    function removeOperator(address _operator) external {
        isRemoved[_operator] = true;
        stakers[_operator].removedPrincipal = stakers[_operator].principal;
        delete stakers[_operator].principal;
    }

    function unstakeRemovedPrincipal() external {
        token.transfer(msg.sender, stakers[msg.sender].removedPrincipal);
        delete stakers[msg.sender].removedPrincipal;
    }

    function slashOperator(address _operator, uint256 _amount) external {
        stakers[_operator].principal -= _amount;
    }

    function getMerkleRoot() external view returns (bytes32) {
        return bytes32(0);
    }

    function isActive() external view returns (bool) {
        return active;
    }

    function setActive(bool _active) external {
        active = _active;
    }

    function setMaxPoolSize(uint256 _maxPoolSize) external {
        maxPoolSize = _maxPoolSize;
    }

    function setDepositLimits(uint256 _depositMin, uint256 _depositMax) external {
        depositMin = _depositMin;
        depositMax = _depositMax;
    }
}
