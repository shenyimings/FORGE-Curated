// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";

import {ERC20} from "solady/tokens/ERC20.sol";

contract DeployERC20 is Script {
    function run() public {
        vm.startBroadcast();
        MockERC20 token = new MockERC20();
        token.mint(vm.envAddress("ADMIN"), 100 ether);
        vm.stopBroadcast();
    }
}

contract MockERC20 is ERC20 {
    function name() public view virtual override returns (string memory) {
        return "ERC20Mock";
    }

    function symbol() public view virtual override returns (string memory) {
        return "E20M";
    }

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) external {
        _burn(account, amount);
    }
}
