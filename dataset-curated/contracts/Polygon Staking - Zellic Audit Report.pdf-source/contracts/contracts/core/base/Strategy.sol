// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "../interfaces/IStrategy.sol";
import "../interfaces/IStakingPool.sol";

/**
 * @title Strategy
 * @notice Base strategy contract to inherit from
 */
abstract contract Strategy is IStrategy, Initializable, UUPSUpgradeable, OwnableUpgradeable {
    IERC20Upgradeable public token;
    IStakingPool public stakingPool;

    function __Strategy_init(address _token, address _stakingPool) public onlyInitializing {
        token = IERC20Upgradeable(_token);
        stakingPool = IStakingPool(_stakingPool);
        __Ownable_init();
        __UUPSUpgradeable_init();
    }

    modifier onlyStakingPool() {
        require(address(stakingPool) == msg.sender, "StakingPool only");
        _;
    }

    /**
     * @notice returns the available deposit room for this strategy
     * @return available deposit room
     */
    function canDeposit() public view virtual returns (uint256) {
        uint256 deposits = getTotalDeposits();
        if (deposits >= getMaxDeposits()) {
            return 0;
        } else {
            return getMaxDeposits() - deposits;
        }
    }

    /**
     * @notice returns the available withdrawal room for this strategy
     * @return available withdrawal room
     */
    function canWithdraw() public view virtual returns (uint256) {
        uint256 deposits = getTotalDeposits();
        if (deposits <= getMinDeposits()) {
            return 0;
        } else {
            return deposits - getMinDeposits();
        }
    }

    /**
     * @notice returns the total amount of deposits in this strategy
     * @return total deposits
     */
    function getTotalDeposits() public view virtual returns (uint256);

    /**
     * @notice returns the maximum that can be deposited into this strategy
     * @return max deposits
     */
    function getMaxDeposits() public view virtual returns (uint256);

    /**
     * @notice returns the minimum that must remain in this strategy
     * @return min deposits
     */
    function getMinDeposits() public view virtual returns (uint256);

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
