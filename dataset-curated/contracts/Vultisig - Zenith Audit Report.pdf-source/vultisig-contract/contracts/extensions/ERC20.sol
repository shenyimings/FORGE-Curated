// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Token} from "../Token.sol";
import {ILaunchList} from "../interfaces/ILaunchList.sol";

/**
 * @title Extended token contract with launch list contract interactions
 * @notice During launch list period, `_beforeTokenTransfer` function will call `isTransactionAllowed` function of launch list contract
 * @notice If launch list period is ended, owner will set launch list contract address back to address(0) and tokens will be transferred freely
 */
contract ERC20 is Token {
    /// @notice launch list contract address
    address public _launchListContract;
    bool private _launchListRevoked = false;

    constructor(string memory name_, string memory ticker_) Token(name_, ticker_) {}

    /// @notice Returns current launch list contract address
    function launchListContract() external view returns (address) {
        return _launchListContract;
    }

    /// @notice Ownable function to revoke setting LaunchList
    function revokeSettingLaunchList() external onlyOwner {
        _launchListRevoked = true;
        _launchListContract = address(0);
    }

    /// @notice Ownable function to set new launch list contract address
    function setLaunchListContract(address newLaunchListContract) external onlyOwner {
        // Allow setting the launch list contract only if not revoked
        if (!_launchListRevoked) {
            _launchListContract = newLaunchListContract;
        }
    }

    /// @notice Before token transfer hook
    /// @dev It will call `isTransactionAllowed` function and if it's succsessful, it will transfer tokens, unless revert
    function _update(address from, address to, uint256 amount) internal override {
        require(to != address(this), "Cannot transfer to the token contract address");
        if (_launchListContract != address(0)) {
            require(
                ILaunchList(_launchListContract).isTransactionAllowed(from, to, amount),
                "Transaction not allowed by launch list"
            );
        }
        super._update(from, to, amount);
    }
}
