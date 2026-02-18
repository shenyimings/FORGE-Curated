// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface IweETH is IERC20 {
    function wrap(uint256 eETHDeposit) external returns (uint256 weETHMinted);
    function unwrap(uint256 weETHDeposit) external returns (uint256 eETHMinted);
}

interface ILiquidityPool {
    function deposit() external payable returns (uint256 eETHMinted);
    function requestWithdraw(address requester, uint256 eETHAmount) external returns (uint256 requestId);
}

interface IWithdrawRequestNFT {
    function ownerOf(uint256 requestId) external view returns (address);
    function isFinalized(uint256 requestId) external view returns (bool);
    function getClaimableAmount(uint256 requestId) external view returns (uint256);
    function claimWithdraw(uint256 requestId) external;
    function finalizeRequests(uint256 requestId) external;
}

IweETH constant weETH = IweETH(0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee);
ERC20 constant eETH = ERC20(0x35fA164735182de50811E8e2E824cFb9B6118ac2);
ILiquidityPool constant LiquidityPool = ILiquidityPool(0x308861A430be4cce5502d0A12724771Fc6DaF216);
IWithdrawRequestNFT constant WithdrawRequestNFT = IWithdrawRequestNFT(0x7d5706f6ef3F89B3951E23e557CDFBC3239D4E2c);