// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

// Make sure the imports match the version specified in foundry.toml
import "openzeppelin-contracts/token/ERC20/ERC20.sol";
import "openzeppelin-contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "openzeppelin-contracts/token/ERC20/extensions/ERC20Pausable.sol";
import "openzeppelin-contracts/access/Ownable.sol";
// In OpenZeppelin 4.4.x, ERC20Permit is under 'drafts'
import "openzeppelin-contracts/token/ERC20/extensions/draft-ERC20Permit.sol";

contract MockERC20 is ERC20, ERC20Burnable, ERC20Pausable, Ownable, ERC20Permit {
    uint8 private _decimalsCustom;

    constructor(
        address initialOwner,
        string memory name_,
        string memory symbol_,
        uint256 initialSupply_,
        uint8 decimals_
    )
        ERC20(name_, symbol_)
        // Name also passed to ERC20Permit so that the permit domain is recognized
        ERC20Permit(name_)
    {
        // Store custom decimals
        _decimalsCustom = decimals_;

        // Mint initial supply to the desired owner
        _mint(initialOwner, initialSupply_);

        // Transfer ownership to initialOwner
        _transferOwnership(initialOwner);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    // Override decimals to use our custom decimals
    function decimals() public view virtual override returns (uint8) {
        return _decimalsCustom;
    }

    // This replaces the _update(...) used in newer OpenZeppelin versions.
    // In OZ <=4.7, the hook to check for pausing is _beforeTokenTransfer.
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    )
        internal
        override(ERC20, ERC20Pausable)
    {
        super._beforeTokenTransfer(from, to, amount);
    }
}
