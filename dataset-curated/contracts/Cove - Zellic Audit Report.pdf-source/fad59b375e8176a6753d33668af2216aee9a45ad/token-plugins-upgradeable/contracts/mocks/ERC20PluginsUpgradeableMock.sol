// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { ERC20PluginsUpgradeable } from "../ERC20PluginsUpgradeable.sol";

contract ERC20PluginsUpgradeableMock is ERC20PluginsUpgradeable {
    function initialize(string memory name, string memory symbol, uint256 maxPluginsPerAccount, uint256 pluginCallGasLimit) public initializer {
        __ERC20_init(name, symbol);
        __ERC20Plugins_init(maxPluginsPerAccount, pluginCallGasLimit);
    }

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }
}
