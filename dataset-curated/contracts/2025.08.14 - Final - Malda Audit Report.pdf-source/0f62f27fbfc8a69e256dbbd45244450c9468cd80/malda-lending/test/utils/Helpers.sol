// SPDX-License-Identifier: BSL-1.1
pragma solidity =0.8.28;

/*
 _____ _____ __    ____  _____ 
|     |  _  |  |  |    \|  _  |
| | | |     |  |__|  |  |     |
|_|_|_|__|__|_____|____/|__|__|                             
*/

import {Test} from "forge-std/Test.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {ERC20Mock} from "../mocks/ERC20Mock.sol";

import {Constants} from "./Constants.sol";

abstract contract Helpers is Test, Constants {
    function _resetContext(address _executor) internal {
        vm.stopPrank();
        vm.startPrank(_executor);
    }

    function _erc20Approve(address _token, address _executor, address _on, uint256 _amount) internal {
        _resetContext(_executor);
        IERC20(_token).approve(_on, _amount);
    }

    // ----------- DEPLOYERS ------------
    function _getTokens(ERC20Mock _token, address _to, uint256 _amount) internal {
        _token.mint(_to, _amount);
    }

    function _spawnAccount(uint256 _key, string memory _name) internal returns (address) {
        address _user = vm.addr(_key);
        vm.deal(_user, LARGE);
        vm.label(_user, _name);
        return _user;
    }

    function _deployToken(string memory _name, string memory _symbol, uint8 _decimals) internal returns (ERC20Mock) {
        ERC20Mock _token = new ERC20Mock(_name, _symbol, _decimals, address(this), address(0), type(uint256).max);
        vm.label(address(_token), _name);
        return _token;
    }
}
