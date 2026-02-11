// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

import "@openzeppelin/contracts/access/Ownable.sol";

import "./base/ERC677.sol";

/**
 * @title Allowance token for staking fair-access
 * @notice Allows for an elastic supply where allowance is calculated by balance & supply
 */
contract StakingAllowance is ERC677, Ownable {
    constructor(string memory _name, string memory _symbol) ERC677(_name, _symbol, 0) {}

    /**
     * @dev Mints a given amount of tokens to an account
     * @param _account address to mint to
     * @param _amount amount of tokens to mint
     **/
    function mint(address _account, uint256 _amount) public onlyOwner {
        _mint(_account, _amount);
    }

    /**
     * @dev Mints a given amount of tokens to a contract on behalf of an account via ERC677
     * @param _contract contract to send tokens to
     * @param _account address to mint to
     * @param _amount amount of tokens to mint
     **/
    function mintToContract(
        address _contract,
        address _account,
        uint256 _amount,
        bytes calldata _calldata
    ) public onlyOwner {
        _mint(msg.sender, _amount);
        transferAndCallWithSender(_account, _contract, _amount, _calldata);
    }

    /**
     * @dev Burns a given amount of tokens from the sender
     * @param _amount amount of tokens to burn
     **/
    function burn(uint256 _amount) public {
        _burn(msg.sender, _amount);
    }

    /**
     * @dev Destroys `amount` tokens from `account`, deducting from the caller's
     * allowance.
     */
    function burnFrom(address account, uint256 amount) public {
        _spendAllowance(account, msg.sender, amount);
        _burn(account, amount);
    }

    /**
     * @dev re-implementation of ERC677 transferAndCall but with the ability to specify a custom sender,
     * needed as the allowance mint needs to be minted on behalf of an address and send to a contract fallback.
     * @param _sender the specified sender of the tokens, the party who 'receives' them into a contract
     * @param _to the contract to send the minted tokens to
     * @param _value the token amount
     * @param _data the calldata included in the transfer
     */
    function transferAndCallWithSender(
        address _sender,
        address _to,
        uint256 _value,
        bytes calldata _data
    ) private returns (bool) {
        require(isContract(_to), "to address has to be a contract");
        super.transfer(_to, _value);
        contractFallback(_sender, _to, _value, _data);
        return true;
    }
}
