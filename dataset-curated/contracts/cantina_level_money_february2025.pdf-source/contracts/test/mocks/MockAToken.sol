// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// From Aave's WadRayMath library
library WadRayMath {
    uint256 internal constant WAD = 1e18;
    uint256 internal constant RAY = 1e27;
    uint256 internal constant HALF_RAY = RAY / 2;

    function rayMul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0 || b == 0) {
            return 0;
        }
        return (a * b + HALF_RAY) / RAY;
    }

    function rayDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 halfB = b / 2;
        return (a * RAY + halfB) / b;
    }
}

contract MockAToken is IERC20 {
    using WadRayMath for uint256;

    uint256 public exchangeRate;
    mapping(address => uint256) private _userBalances;
    uint256 private _totalSupply;
    string public name;
    string public symbol;
    uint8 public decimals;

    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
        exchangeRate = WadRayMath.RAY; // Initial 1:1 rate
    }

    function mint(address account, uint256 amount) external {
        uint256 aTokenAmount = amount.rayDiv(exchangeRate);
        _userBalances[account] += aTokenAmount;
        _totalSupply += aTokenAmount;
        emit Transfer(address(0), account, amount);
    }

    function burn(address account, uint256 amount) external {
        uint256 aTokenAmount = amount.rayDiv(exchangeRate);
        require(_userBalances[account] >= aTokenAmount, "Insufficient balance");
        _userBalances[account] -= aTokenAmount;
        _totalSupply -= aTokenAmount;
        emit Transfer(account, address(0), amount);
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _userBalances[account].rayMul(exchangeRate);
    }

    function totalSupply() public view override returns (uint256) {
        return _totalSupply.rayMul(exchangeRate);
    }

    function transfer(
        address recipient,
        uint256 amount
    ) public override returns (bool) {
        uint256 aTokenAmount = amount.rayDiv(exchangeRate);
        require(
            _userBalances[msg.sender] >= aTokenAmount,
            "Insufficient balance"
        );
        _userBalances[msg.sender] -= aTokenAmount;
        _userBalances[recipient] += aTokenAmount;
        emit Transfer(msg.sender, recipient, amount);
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public override returns (bool) {
        uint256 aTokenAmount = amount.rayDiv(exchangeRate);
        require(_userBalances[sender] >= aTokenAmount, "Insufficient balance");
        _userBalances[sender] -= aTokenAmount;
        _userBalances[recipient] += aTokenAmount;
        emit Transfer(sender, recipient, amount);
        return true;
    }

    function allowance(
        address owner,
        address spender
    ) public view override returns (uint256) {
        return type(uint256).max;
    }

    function approve(
        address spender,
        uint256 amount
    ) public override returns (bool) {
        return true;
    }

    function accrueInterest(uint256 interestRate) external {
        // interestRate in basis points (1% = 100)
        exchangeRate += exchangeRate.rayMul(
            (interestRate * WadRayMath.RAY) / 10000
        );
    }

    function test() public {}
}
