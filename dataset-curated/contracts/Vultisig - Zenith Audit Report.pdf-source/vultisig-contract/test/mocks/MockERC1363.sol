// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../../contracts/interfaces/IERC1363Spender.sol";

contract MockERC1363 is ERC20 {
    constructor(uint256 initialSupply) ERC20("Mock Token", "MTK") {
        _mint(msg.sender, initialSupply);
    }

    function approveAndCall(address spender, uint256 amount, bytes memory data) external returns (bool) {
        approve(spender, amount);
        require(
            IERC1363Spender(spender).onApprovalReceived(msg.sender, amount, data)
                == IERC1363Spender.onApprovalReceived.selector,
            "ERC1363: spender rejected tokens"
        );
        return true;
    }
}
