// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract FeeCollectorSimple is Ownable {
    using SafeERC20 for IERC20;

    address public collector;
    uint256 public tradingFeeRate;
    uint256 public settlementFeeRate;

    event Collected(address indexed token, address indexed collector, uint256 amount);

    constructor(
        uint256 tradingFeeRate_,
        uint256 settlementFeeRate_
    ) {
        collector = msg.sender;
        tradingFeeRate = tradingFeeRate_;
        settlementFeeRate = settlementFeeRate_;
    }

    function setCollector(address collector_) external onlyOwner {
        collector = collector_;
    }
    // set feeRate
    function setTradingFeeRate(uint256 tradingFeeRate_) external onlyOwner {
        tradingFeeRate = tradingFeeRate_;
    }
    function setSettlementFeeRate(uint256 settlementFeeRate_) external onlyOwner {
        settlementFeeRate = settlementFeeRate_;
    }

    function collect(
        address token
    ) external {
        require(msg.sender == collector, "FeeCollector: unauthorized");
        uint256 balance = IERC20(token).balanceOf(address(this));
        require(balance > 0, "FeeCollector: nothing to collect");
        IERC20(token).safeTransfer(collector, balance);
        emit Collected(token, collector, balance);
    }
}
