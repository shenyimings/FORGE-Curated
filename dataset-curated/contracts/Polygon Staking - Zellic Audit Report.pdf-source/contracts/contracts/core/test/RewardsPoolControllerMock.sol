// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

import "../base/RewardsPoolController.sol";

/**
 * @title Rewards Pool Controler Mock
 * @notice Mocks contract for testing
 */
contract RewardsPoolControllerMock is RewardsPoolController {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    IERC20Upgradeable public token;

    uint256 public stakedTotal;
    mapping(address => uint256) public stakeBalances;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _token) public initializer {
        __RewardsPoolController_init();
        token = IERC20Upgradeable(_token);
    }

    function staked(address _account) external view override returns (uint256) {
        return stakeBalances[_account];
    }

    function totalStaked() external view override returns (uint256) {
        return stakedTotal;
    }

    function stake(uint256 _amount) external updateRewards(msg.sender) {
        token.safeTransferFrom(msg.sender, address(this), _amount);
        stakeBalances[msg.sender] += _amount;
        stakedTotal += _amount;
    }

    function withdraw(uint256 _amount) external updateRewards(msg.sender) {
        stakeBalances[msg.sender] -= _amount;
        stakedTotal -= _amount;
        token.safeTransfer(msg.sender, _amount);
    }
}
