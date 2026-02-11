// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "../base/Strategy.sol";
import "../rewardsPools/RewardsPool.sol";

/**
 * @title Strategy Mock
 * @notice Mocks contract for testing
 */
contract StrategyMock is Strategy {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    uint256 private maxDeposits;
    uint256 private minDeposits;

    uint256 private totalDeposits;
    uint256 public feeBasisPoints;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _token,
        address _stakingPool,
        uint256 _maxDeposits,
        uint256 _minDeposits
    ) public initializer {
        __Strategy_init(_token, _stakingPool);
        feeBasisPoints = 0;
        maxDeposits = _maxDeposits;
        minDeposits = _minDeposits;
    }

    // should return the change in deposits since updateRewards was last called (can be positive or negative)
    function getDepositChange() public view returns (int) {
        return int(token.balanceOf(address(this))) - int(totalDeposits);
    }

    function deposit(uint256 _amount, bytes calldata) external onlyStakingPool {
        token.safeTransferFrom(msg.sender, address(this), _amount);
        totalDeposits += _amount;
        // Deposit into earning protocol/node
    }

    function withdraw(uint256 _amount, bytes calldata) external onlyStakingPool {
        require(_amount <= canWithdraw(), "Total deposits must remain >= minimum");
        totalDeposits -= _amount;
        //Withdraw from earning protocol/node
        token.safeTransfer(msg.sender, _amount);
    }

    function updateDeposits(
        bytes calldata
    )
        external
        onlyStakingPool
        returns (int256 depositChange, address[] memory receivers, uint256[] memory amounts)
    {
        depositChange = getDepositChange();
        if (depositChange > 0) {
            totalDeposits += uint256(depositChange);
            if (feeBasisPoints > 0) {
                receivers = new address[](1);
                amounts = new uint256[](1);
                receivers[0] = owner();
                amounts[0] = (feeBasisPoints * uint256(depositChange)) / 10000;
            }
        } else if (depositChange < 0) {
            totalDeposits -= uint256(depositChange * -1);
        }
    }

    function setFeeBasisPoints(uint256 _feeBasisPoints) external {
        feeBasisPoints = _feeBasisPoints;
    }

    function simulateSlash(uint256 _amount) external {
        token.safeTransfer(msg.sender, _amount);
    }

    function getTotalDeposits() public view override returns (uint256) {
        return totalDeposits;
    }

    function getMaxDeposits() public view override returns (uint256) {
        return maxDeposits;
    }

    function getMinDeposits() public view override returns (uint256) {
        return minDeposits;
    }

    function setMaxDeposits(uint256 _maxDeposits) external onlyOwner {
        maxDeposits = _maxDeposits;
    }

    function setMinDeposits(uint256 _minDeposits) external onlyOwner {
        minDeposits = _minDeposits;
    }

    function createRewardsPool(address _token) public {
        RewardsPool rewardsPool = new RewardsPool(address(stakingPool), _token);
        IRewardsPoolController rewardsPoolController = IRewardsPoolController(address(stakingPool));
        rewardsPoolController.addToken(_token, address(rewardsPool));
    }
}
