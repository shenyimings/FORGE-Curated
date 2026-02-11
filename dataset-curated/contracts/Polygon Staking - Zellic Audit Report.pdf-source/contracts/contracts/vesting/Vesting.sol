// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

import "@openzeppelin/contracts/finance/VestingWallet.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Vesting is VestingWallet, Ownable {
    bool public vestingTerminated;

    event VestingTerminated();

    error VestingNotTerminated();
    error VestingAlreadyTerminated();

    constructor(
        address _owner,
        address _beneficiary,
        uint64 _startTimestamp,
        uint64 _durationSeconds
    ) VestingWallet(_beneficiary, _startTimestamp, _durationSeconds) {
        _transferOwnership(_owner);
    }

    /**
     * @notice Terminates the vesting contract and withdraws unvested tokens
     */
    function terminateVesting(address[] calldata _tokens) external onlyOwner {
        if (vestingTerminated) revert VestingAlreadyTerminated();

        for (uint256 i = 0; i < _tokens.length; ++i) {
            address token = _tokens[i];
            uint256 toWithdraw = IERC20(token).balanceOf(address(this)) -
                vestedAmount(token, uint64(block.timestamp));
            SafeERC20.safeTransfer(IERC20(token), owner(), toWithdraw);
        }
        vestingTerminated = true;
        emit VestingTerminated();
    }

    /**
     * @notice Releases all remaining vested tokens after termination of the vesting contract
     */
    function releaseRemaining(address _token) external {
        if (!vestingTerminated) revert VestingNotTerminated();
        uint256 toRelease = IERC20(_token).balanceOf(address(this));
        emit ERC20Released(_token, toRelease);
        SafeERC20.safeTransfer(IERC20(_token), beneficiary(), toRelease);
    }
}
