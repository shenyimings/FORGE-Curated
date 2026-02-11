// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title Metis Locking Info Mock
 * @dev Mocks contract for testing
 */
contract MetisLockingInfoMock {
    using SafeERC20 for IERC20;

    IERC20 public token;
    address public manager;

    uint256 public minLock;
    uint256 public maxLock;

    mapping(address => uint256) private locked;

    error InvalidAmount();

    constructor(address _token, uint256 _minLock, uint256 _maxLock) {
        token = IERC20(_token);
        minLock = _minLock;
        maxLock = _maxLock;
    }

    function newSequencer(address _owner, uint256 _amount) external {
        if (_amount < minLock) revert InvalidAmount();
        locked[_owner] = _amount;
        token.safeTransferFrom(_owner, address(this), _amount);
    }

    function increaseLocked(address _owner, uint256 _amount, uint256 _rewardsAmount) external {
        if (_amount + _rewardsAmount + locked[_owner] > maxLock) revert InvalidAmount();
        locked[_owner] += _amount + _rewardsAmount;
        token.safeTransferFrom(_owner, address(this), _amount);
    }

    function withdrawLocking(address _owner, uint256 _amount) external {
        require(_amount > 0 && (locked[_owner] - _amount) >= minLock, "invalid amount");
        locked[_owner] -= _amount;
        token.safeTransfer(_owner, _amount);
    }

    function exit(address _owner) external {
        token.safeTransfer(_owner, locked[_owner]);
        locked[_owner] = 0;
    }

    function setManager(address _manager) external {
        manager = _manager;
    }

    function setMaxLock(uint256 _maxLock) external {
        maxLock = _maxLock;
    }

    function setMinLock(uint256 _minLock) external {
        maxLock = _minLock;
    }
}
