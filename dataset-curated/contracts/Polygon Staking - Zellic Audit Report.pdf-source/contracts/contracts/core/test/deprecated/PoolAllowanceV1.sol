// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

import "../../tokens/base/ERC677.sol";

/**
 * @title Pool Allowance
 * @dev Pool staking allowance token
 */
contract PoolAllowanceV1 is ERC677 {
    address public poolOwners;

    constructor(
        string memory _name,
        string memory _symbol,
        address _poolOwners
    ) ERC677(_name, _symbol, 0) {
        poolOwners = _poolOwners;
    }

    modifier onlyPoolOwners() {
        require(poolOwners == msg.sender, "PoolOwners only");
        _;
    }

    /**
     * @dev mints allowance tokens
     * @param _account address to mint tokens for
     * @param _amount amount to mint
     **/
    function mintAllowance(address _account, uint256 _amount) external onlyPoolOwners {
        _mint(_account, _amount);
    }

    /**
     * @dev burns allowance tokens
     * @param _account address to burn tokens from
     * @param _amount amount to burn
     **/
    function burnAllowance(address _account, uint256 _amount) external onlyPoolOwners {
        _burn(_account, _amount);
    }
}
