pragma solidity ^0.8.28;

interface ILaunchList {
    function isTransactionAllowed(address from, address to, uint256 amount) external returns (bool);
}
