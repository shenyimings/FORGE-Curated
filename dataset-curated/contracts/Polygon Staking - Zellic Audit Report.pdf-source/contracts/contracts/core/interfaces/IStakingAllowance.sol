// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

interface IStakingAllowance {
    function mint(address _account, uint256 _amount) external;

    function burn(uint256 _amount) external;

    function burnFrom(address account, uint256 amount) external;
}
