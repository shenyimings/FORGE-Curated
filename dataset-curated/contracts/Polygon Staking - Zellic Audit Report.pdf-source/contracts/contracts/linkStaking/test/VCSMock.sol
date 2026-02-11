// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

import "../base/VaultControllerStrategy.sol";

/**
 * @title Mock Vault Controller Strategy
 * @dev Mocks contract for testing
 */
contract VCSMock is VaultControllerStrategy {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _token,
        address _stakingPool,
        address _stakeController,
        address _vaultImplementation,
        Fee[] memory _fees,
        uint256 _vaultMaxDeposits,
        address _vaultDepositController
    ) public initializer {
        __VaultControllerStrategy_init(
            _token,
            _stakingPool,
            _stakeController,
            _vaultImplementation,
            _fees,
            9000,
            _vaultMaxDeposits,
            _vaultDepositController
        );

        globalVaultState = GlobalVaultState(5, 0, 0, 0);
        for (uint64 i = 0; i < 5; ++i) {
            vaultGroups.push(VaultGroup(i, 0));
        }
    }

    function addVaults(address[] memory _vaults) external {
        for (uint256 i = 0; i < _vaults.length; i++) {
            address vault = _vaults[i];
            vaults.push(IVault(vault));
            token.approve(vault, type(uint256).max);
        }
    }

    function deployVault(bytes memory _data) external {
        _deployVault(_data);
    }

    function addFeeBypassUpdate(address _receiver, uint256 _feeBasisPoints) external {
        fees.push(Fee(_receiver, _feeBasisPoints));
    }
}
