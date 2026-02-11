// SPDX-License-Identifier: GPL-3
pragma solidity 0.8.23;

contract SimpleContract {
    mapping(address account => bool isCaller) private s_magicMapping;
    mapping(address account => uint256 balance) public s_balances;

    function call() external {
        s_magicMapping[msg.sender] = true;
    }

    function getMagicValue(address acc) external view returns (bool isCaller) {
        return s_magicMapping[acc];
    }

    function deposit() external payable {
        s_balances[msg.sender] += msg.value;
    }

    receive() external payable virtual {}
}
