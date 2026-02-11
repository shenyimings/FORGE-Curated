// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "../interfaces/IERC677.sol";
import "../interfaces/IStakingPool.sol";
import "../interfaces/ILSTRewardsSplitterController.sol";

/**
 * @title LST Rewards Splitter
 * @notice Allows an account to send LST rewards to other addresses
 */
contract LSTRewardsSplitter is Ownable {
    using SafeERC20 for IERC677;

    struct Fee {
        // address to receive fee
        address receiver;
        // value of fee in basis points
        uint256 basisPoints;
    }

    // address of contract that conrols this splitter
    ILSTRewardsSplitterController public controller;
    // address of liquid staking token
    IERC677 public lst;

    // list of fees that are paid on rewards
    Fee[] private fees;

    // total number of tokens deposited without rewards
    uint256 public principalDeposits;

    event Deposit(uint256 amount);
    event Withdraw(uint256 amount);
    event RewardsSplit(uint256 rewardsAmount);

    error SenderNotAuthorized();
    error FeesExceedLimit();
    error InsufficientRewards();

    /**
     * @notice Inititalizes contract
     * @param _lst address of liquid staking token
     * @param _fees list of fees to be applied to new rewards
     * @param _owner address of owner
     */
    constructor(address _lst, Fee[] memory _fees, address _owner) {
        controller = ILSTRewardsSplitterController(msg.sender);
        lst = IERC677(_lst);
        for (uint256 i = 0; i < _fees.length; ++i) {
            fees.push(_fees[i]);
        }
        _transferOwnership(_owner);
    }

    modifier onlyController() {
        if (msg.sender != address(controller)) revert SenderNotAuthorized();
        _;
    }

    /**
     * @notice Deposits tokens
     * @param _amount amount to deposit
     */
    function deposit(uint256 _amount) external onlyController {
        lst.safeTransferFrom(msg.sender, address(this), _amount);
        principalDeposits += _amount;
        emit Deposit(_amount);
    }

    /**
     * @notice Withdraws tokens
     * @param _amount amount to withdraw
     * @param _receiver address to receive tokens
     */
    function withdraw(uint256 _amount, address _receiver) external onlyController {
        principalDeposits -= _amount;
        lst.safeTransfer(_receiver, _amount);
        emit Withdraw(_amount);
    }

    /**
     * @notice Returns whether a call should be made to performUpkeep to split new rewards
     * @return upkeepNeeded true if performUpkeep should be called, false otherwise
     */
    function checkUpkeep(bytes calldata) external view returns (bool, bytes memory) {
        int256 newRewards = int256(lst.balanceOf(address(this))) - int256(principalDeposits);

        if (newRewards < 0 || uint256(newRewards) >= controller.rewardThreshold())
            return (true, bytes(""));

        return (false, bytes(""));
    }

    /**
     * @notice Splits new rewards between fee receivers
     */
    function performUpkeep(bytes calldata) external {
        int256 newRewards = int256(lst.balanceOf(address(this))) - int256(principalDeposits);
        if (newRewards < 0) {
            principalDeposits -= uint256(-1 * newRewards);
        } else if (uint256(newRewards) < controller.rewardThreshold()) {
            revert InsufficientRewards();
        } else {
            _splitRewards(uint256(newRewards));
        }
    }

    /**
     * @notice Splits new rewards between fee receivers
     * @dev bypasses rewardThreshold
     */
    function splitRewards() external {
        int256 newRewards = int256(lst.balanceOf(address(this))) - int256(principalDeposits);
        if (newRewards < 0) {
            principalDeposits -= uint256(-1 * newRewards);
        } else if (newRewards == 0) {
            revert InsufficientRewards();
        } else {
            _splitRewards(uint256(newRewards));
        }
    }

    /**
     * @notice Returns a list of all fees
     * @return list of fees
     */
    function getFees() external view returns (Fee[] memory) {
        return fees;
    }

    /**
     * @notice Sdds a new fee
     * @param _receiver receiver of fee
     * @param _feeBasisPoints fee in basis points
     **/
    function addFee(address _receiver, uint256 _feeBasisPoints) external onlyOwner {
        fees.push(Fee(_receiver, _feeBasisPoints));
        if (_totalFeesBasisPoints() > 10000) revert FeesExceedLimit();
    }

    /**
     * @notice Updates an existing fee
     * @param _index index of fee
     * @param _receiver receiver of fee
     * @param _feeBasisPoints fee in basis points
     **/
    function updateFee(
        uint256 _index,
        address _receiver,
        uint256 _feeBasisPoints
    ) external onlyOwner {
        require(_index < fees.length, "Fee does not exist");

        if (_feeBasisPoints == 0) {
            fees[_index] = fees[fees.length - 1];
            fees.pop();
        } else {
            fees[_index].receiver = _receiver;
            fees[_index].basisPoints = _feeBasisPoints;
        }

        if (_totalFeesBasisPoints() > 10000) revert FeesExceedLimit();
    }

    /**
     * @notice Splits new rewards
     * @param _rewardsAmount amount of new rewards
     */
    function _splitRewards(uint256 _rewardsAmount) private {
        for (uint256 i = 0; i < fees.length; ++i) {
            Fee memory fee = fees[i];
            uint256 amount = (_rewardsAmount * fee.basisPoints) / 10000;

            if (fee.receiver == address(lst)) {
                IStakingPool(address(lst)).burn(amount);
            } else {
                lst.safeTransfer(fee.receiver, amount);
            }
        }

        principalDeposits = lst.balanceOf(address(this));
        emit RewardsSplit(_rewardsAmount);
    }

    /**
     * @notice Returns the sum of all fees
     * @return sum of fees in basis points
     **/
    function _totalFeesBasisPoints() private view returns (uint256) {
        uint256 totalFees;
        for (uint i = 0; i < fees.length; i++) {
            totalFees += fees[i].basisPoints;
        }
        return totalFees;
    }
}
