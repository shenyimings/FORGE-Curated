// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract MockStETH is ERC20 {
    uint256 private totalShares;
    uint256 private totalPooledEth;
    mapping(address => uint256) private shares;

    constructor() ERC20("Mock stETH", "stETH") {
        totalShares = 1e18;
        totalPooledEth = 1e18;
    }

    //
    // simple shares
    //

    function getTotalShares() external view returns (uint256) {
        return totalShares;
    }

    function getSharesByPooledEth(uint256 _ethAmount) public view returns (uint256) {
        return _ethAmount * totalShares // denominator in shares
            / totalPooledEth; // numerator in ether
    }

    function getPooledEthByShares(uint256 _sharesAmount) public view returns (uint256) {
        return _sharesAmount * totalPooledEth // numerator in ether
            / totalShares; // denominator in shares
    }

    function getPooledEthBySharesRoundUp(uint256 _sharesAmount) public view returns (uint256) {
        return Math.mulDiv(_sharesAmount, totalPooledEth, totalShares, Math.Rounding.Ceil);
    }

    function transferSharesFrom(address from, address to, uint256 amount) external returns (bool) {
        require(shares[from] >= amount, "Not enough shares");

        uint256 steth = getPooledEthByShares(amount);
        uint256 allowance = allowance(from, msg.sender);
        require(allowance >= steth, "Not enough allowance");
        _approve(from, msg.sender, allowance - steth);

        shares[from] -= amount;
        shares[to] += amount;

        return true;
    }

    function transferShares(address to, uint256 amount) external returns (bool) {
        require(shares[msg.sender] >= amount, "Not enough shares");
        shares[msg.sender] -= amount;
        shares[to] += amount;
        return true;
    }

    function sharesOf(address account) external view returns (uint256) {
        return shares[account];
    }

    // simple steth

    function balanceOf(address account) public view override returns (uint256) {
        return getPooledEthByShares(shares[account]);
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        uint256 sharesToTransfer = getSharesByPooledEth(amount);
        require(shares[msg.sender] >= sharesToTransfer, "Not enough shares");

        shares[msg.sender] -= sharesToTransfer;
        shares[to] += sharesToTransfer;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        uint256 sharesToTransfer = getSharesByPooledEth(amount);
        require(shares[from] >= sharesToTransfer, "Not enough shares");

        uint256 currentAllowance = allowance(from, msg.sender);
        require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
        _approve(from, msg.sender, currentAllowance - amount);

        shares[from] -= sharesToTransfer;
        shares[to] += sharesToTransfer;
        return true;
    }

    function submit(address) external payable returns (uint256) {
        uint256 sharesToMint = getPooledEthByShares(msg.value);
        shares[msg.sender] += sharesToMint;
        totalShares += sharesToMint;
        totalPooledEth += msg.value;
        return sharesToMint;
    }

    function mock_mintExternalShares(address _recipient, uint256 _amountOfShares) external {
        require(_amountOfShares != 0, "MINT_ZERO_AMOUNT_OF_SHARES");
        uint256 pooledEther = getPooledEthByShares(_amountOfShares);

        shares[_recipient] += _amountOfShares;
        totalShares += _amountOfShares;
        totalPooledEth += pooledEther;
    }

    function mock_setTotalPooled(uint256 _pooledEthAmount, uint256 _sharesAmount) external {
        totalPooledEth = _pooledEthAmount;
        totalShares = _sharesAmount;
    }
}
