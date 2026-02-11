// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./interfaces/ICurveStableSwapNG.sol";
import "./interfaces/ILiquidityGaugeV6.sol";

/**
 * @title Curve Gauge Distributor
 * @notice Receives and distributes LST rewards to a Curve Gauge
 */
contract CurveGaugeDistributor is Ownable {
    using SafeERC20 for IERC20;

    // address of staking pool
    address public stakingPool;
    // address of curve stable swap NG pool
    ICurveStableSwapNG public curveStableSwapNG;
    // address of curve gauge for stable swap pool
    ILiquidityGaugeV6 public liquidityGaugeV6;

    // address authorized to distribute gauge rewards
    address public rewardsDistributor;

    // duration of reward epoch in seconds
    uint64 public epochDuration;

    error SenderNotAuthorized();
    error NoRewards();

    /**
     * @notice Initializes the contract
     * @param _stakingPool address of staking pool
     * @param _curveStableSwapNG address of curve stable swap NG pool
     * @param _liquidityGaugeV6 address of curve gauge for stable swap pool
     * @param _rewardsDistributor address authorized to distribute gauge rewards
     * @param _epochDuration duration of reward epoch in seconds
     */
    constructor(
        address _stakingPool,
        address _curveStableSwapNG,
        address _liquidityGaugeV6,
        address _rewardsDistributor,
        uint64 _epochDuration
    ) {
        stakingPool = _stakingPool;
        curveStableSwapNG = ICurveStableSwapNG(_curveStableSwapNG);
        liquidityGaugeV6 = ILiquidityGaugeV6(_liquidityGaugeV6);
        rewardsDistributor = _rewardsDistributor;
        epochDuration = _epochDuration;

        IERC20(_stakingPool).safeApprove(_curveStableSwapNG, type(uint256).max);
        IERC20(_curveStableSwapNG).safeApprove(_liquidityGaugeV6, type(uint256).max);
    }

    /**
     * @notice Reverts if sender is not rewards distributor
     */
    modifier onlyRewardsDistributor() {
        if (msg.sender != rewardsDistributor) revert SenderNotAuthorized();
        _;
    }

    /**
     * @notice Receives transfers of LST rewards from staking pool
     */
    function onTokenTransfer(address, uint256, bytes calldata) external {}

    /**
     * @notice Returns the expected amount of LP tokens to be minted when rewards are distributed
     * @return expected LP tokens to be minted
     */
    function getLPTokenAmount() external view returns (uint256) {
        uint256 balance = IERC20(stakingPool).balanceOf(address(this));
        if (balance == 0) return 0;

        uint256[] memory amounts = new uint256[](2);
        amounts[1] = balance;

        uint256 minMintAmount = curveStableSwapNG.calc_token_amount(amounts, true);
        return minMintAmount;
    }

    /**
     * @notice Distributes rewards
     * @param _minMintAmount minimum LP tokens to be minted when rewards are distributed
     */
    function distributeRewards(uint256 _minMintAmount) external onlyRewardsDistributor {
        uint256 balance = IERC20(stakingPool).balanceOf(address(this));
        if (balance == 0) revert NoRewards();

        uint256[] memory amounts = new uint256[](2);
        amounts[1] = balance;

        uint256 mintAmount = curveStableSwapNG.add_liquidity(
            amounts,
            _minMintAmount,
            address(this)
        );
        liquidityGaugeV6.deposit_reward_token(
            address(curveStableSwapNG),
            mintAmount,
            epochDuration
        );
    }

    /**
     * @notice Sets the reward epoch duration
     * @param _epochDuration reward epoch duration in seconds
     */
    function setEpochDuration(uint64 _epochDuration) external onlyOwner {
        epochDuration = _epochDuration;
    }

    /**
     * @notice Sets the address authorized to distribute rewards
     * @param _rewardsDistributor distributor address
     */
    function setRewardsDistributor(address _rewardsDistributor) external onlyOwner {
        rewardsDistributor = _rewardsDistributor;
    }
}
