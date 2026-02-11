// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC1363Spender} from "../interfaces/IERC1363Spender.sol";

contract Vult is ERC20 {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {
        _mint(msg.sender, 10_000_000 * 1e18);
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    function approveAndCall(address spender, uint256 value, bytes memory data) public virtual returns (bool) {
        if (!approve(spender, value)) {
            revert("ERC1363ApproveFailed");
        }
        _checkOnApprovalReceived(spender, value, data);
        return true;
    }

    function _checkOnApprovalReceived(address spender, uint256 value, bytes memory data) private {
        if (spender.code.length == 0) {
            revert("ERC1363EOASpender");
        }

        try IERC1363Spender(spender).onApprovalReceived(_msgSender(), value, data) returns (bytes4 retval) {
            if (retval != IERC1363Spender.onApprovalReceived.selector) {
                revert("ERC1363InvalidSpender");
            }
        } catch (bytes memory reason) {
            if (reason.length == 0) {
                revert("ERC1363InvalidSpender");
            } else {
                assembly {
                    revert(add(32, reason), mload(reason))
                }
            }
        }
    }
}
