// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "../../../core/interfaces/IERC677.sol";

interface IStakingV1 {
    function getCommunityStakerLimits() external view returns (uint256, uint256);

    function getOperatorLimits() external view returns (uint256, uint256);

    function getMaxPoolSize() external view returns (uint256);

    function getTotalStakedAmount() external view returns (uint256);

    function isActive() external view returns (bool);

    function isOperator(address staker) external view returns (bool);

    function getStake(address staker) external view returns (uint256);

    function migrate(bytes calldata data) external;

    function getBaseReward(address staker) external view returns (uint256);

    function getDelegationReward(address staker) external view returns (uint256);

    function getMigrationTarget() external view returns (address);

    function isPaused() external view returns (bool);

    function raiseAlert() external;
}

/**
 * @title Vault
 * @notice Base vault contract for depositing LINK collateral into the Chainlink staking controller
 */
abstract contract VaultV1 is Initializable, UUPSUpgradeable, OwnableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    IERC20Upgradeable public token;
    address public vaultController;
    IStakingV1 public stakeController;

    uint256[10] private __gap;

    function __Vault_init(
        address _token,
        address _vaultController,
        address _stakeController
    ) public onlyInitializing {
        __Ownable_init();
        __UUPSUpgradeable_init();
        token = IERC20Upgradeable(_token);
        vaultController = _vaultController;
        stakeController = IStakingV1(_stakeController);
    }

    modifier onlyVaultController() {
        require(vaultController == msg.sender, "Vault controller only");
        _;
    }

    /**
     * @notice deposits tokens into the Chainlink staking contract
     * @param _amount amount to deposit
     */
    function deposit(uint256 _amount) external onlyVaultController {
        token.safeTransferFrom(msg.sender, address(this), _amount);
        IERC677(address(token)).transferAndCall(address(stakeController), _amount, "0x00");
    }

    /**
     * @notice withdrawals are not yet implemented in this iteration of Chainlink staking
     */
    function withdraw(uint256) external view onlyVaultController {
        revert("withdrawals not yet implemented");
    }

    /**
     * @notice returns the total balance of this contract in the Chainlink staking contract
     * @return total balance
     */
    function getTotalDeposits() public view virtual returns (uint256);

    /**
     * @notice returns the principal balance of this contract in the Chainlink staking contract
     * @return principal balance
     */
    function getPrincipalDeposits() public view returns (uint256) {
        return stakeController.getStake(address(this));
    }

    /**
     * @notice migrates the deposited tokens into a new stake controller
     */
    function migrate(bytes calldata data) external onlyVaultController {
        stakeController.migrate(data);
        stakeController = IStakingV1(stakeController.getMigrationTarget());
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
