// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract MockFeeOnTransferTokenWithPermit is ERC20Permit {
    uint256 public feePercentage; // Fee in basis points (100 = 1%)

    constructor(string memory name, string memory symbol, uint256 _feePercentage)
        ERC20(name, symbol)
        ERC20Permit(name)
    {
        feePercentage = _feePercentage;
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    function setFeePercentage(uint256 _feePercentage) public {
        feePercentage = _feePercentage;
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        return _transferWithFee(_msgSender(), to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        address spender = _msgSender();
        _spendAllowance(from, spender, amount);
        return _transferWithFee(from, to, amount);
    }

    function _transferWithFee(address from, address to, uint256 amount) internal returns (bool) {
        uint256 fee = (amount * feePercentage) / 10000;
        uint256 actualAmount = amount - fee;

        // Burn the fee (simulating fee-on-transfer)
        _transfer(from, address(0xdead), fee);
        _transfer(from, to, actualAmount);

        return true;
    }
}
