// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { MockERC20 } from "./MockERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { ERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { StdCheats } from "forge-std/StdCheats.sol";
import { console } from "forge-std/console.sol";

contract MockERC4626 is ERC4626, StdCheats {
    using SafeERC20 for IERC20;
    using Math for uint256;

    uint256 public interestRate; // 18 decimals (1e18 = 100%)
    uint256 public lastUpdate;

    constructor(address _asset, uint256 _interestRate, string memory _name, string memory _symbol)
        ERC4626(IERC20(_asset))
        ERC20(_name, _symbol)
    {
        interestRate = _interestRate;
        lastUpdate = block.timestamp;
    }

    function deposit(uint256 assets, address receiver) public override returns (uint256) {
        __mockYield();
        return super.deposit(assets, receiver);
    }

    function mint(uint256 shares, address receiver) public override returns (uint256) {
        __mockYield();
        return super.mint(shares, receiver);
    }

    function withdraw(uint256 assets, address receiver, address owner) public override returns (uint256) {
        __mockYield();
        return super.withdraw(assets, receiver, owner);
    }

    function redeem(uint256 shares, address receiver, address owner) public override returns (uint256) {
        __mockYield();
        return super.redeem(shares, receiver, owner);
    }

    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal override {
        __mockYield();
        super._deposit(caller, receiver, assets, shares);
    }

    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares)
        internal
        override
    {
        __mockYield();
        super._withdraw(caller, receiver, owner, assets, shares);
    }

    function __mockYield() public {
        uint256 interest = __estimateMockErc4626Yield();
        if (interest > 0) {
            lastUpdate = block.timestamp;
            uint256 balance = IERC20(asset()).balanceOf(address(this));
            deal(asset(), address(this), balance + interest);
        }
    }

    function setInterestRate(uint256 _interestRate) external {
        interestRate = _interestRate;
    }

    function __interestRate() external view returns (uint256) {
        return interestRate;
    }

    function __lastUpdate() external view returns (uint256) {
        return lastUpdate;
    }

    function __estimateMockErc4626Yield() public view returns (uint256) {
        uint256 principal = IERC20(asset()).balanceOf(address(this));
        uint256 timeElapsed = block.timestamp - lastUpdate;
        return (principal * interestRate * timeElapsed) / (365 days * 1e18);
    }
}
