// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

/* solhint-disable var-name-mixedcase  */

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IslvlUSDSiloDefinitions.sol";

/**
 * @title slvlUSDSilo
 * @notice The Silo allows to store lvlUSD during the stake cooldown process.
 *         Forked from Ethena's USDeSilo contract.
 */
contract slvlUSDSilo is IslvlUSDSiloDefinitions {
    address immutable _STAKING_VAULT;
    IERC20 immutable _lvlUSD;

    constructor(address stakingVault, address lvlUSD) {
        _STAKING_VAULT = stakingVault;
        _lvlUSD = IERC20(lvlUSD);
    }

    modifier onlyStakingVault() {
        if (msg.sender != _STAKING_VAULT) revert OnlyStakingVault();
        _;
    }

    function withdraw(address to, uint256 amount) external onlyStakingVault {
        _lvlUSD.transfer(to, amount);
    }
}
