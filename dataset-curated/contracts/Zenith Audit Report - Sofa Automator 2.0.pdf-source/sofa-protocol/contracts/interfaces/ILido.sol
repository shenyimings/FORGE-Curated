// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

interface ILido {
    function submit(address _referral) external payable returns (uint256);

    function balanceOf(address) external view returns (uint256);

    function deposit() external payable;

    function withdraw(uint256) external;

    function approve(address guy, uint256 wad) external returns (bool);

    function transfer(address to, uint256 amount) external returns (bool);

    function transferFrom(
                          address src,
                          address dst,
                          uint256 wad
    ) external returns (bool);

    function decimals() external view returns (uint8);

    function name() external view returns (string memory);

    function symbol() external view returns (string memory);
}
