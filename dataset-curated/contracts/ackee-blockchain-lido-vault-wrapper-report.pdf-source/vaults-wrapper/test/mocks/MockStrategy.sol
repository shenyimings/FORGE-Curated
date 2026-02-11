// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {IStrategy} from "src/interfaces/IStrategy.sol";
import {StvPool} from "src/StvPool.sol";
import {StvStETHPool} from "src/StvStETHPool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockStrategy is IStrategy {
    address public immutable POOL;

    bytes32 public constant SUPPLY_PAUSE_ROLE = keccak256("SUPPLY_PAUSE_ROLE");

    bool public initialized;
    address public admin;
    address public supplyPauser;

    constructor(address _pool) {
        POOL = _pool;
    }

    function initialize(address _admin, address _supplyPauser) external {
        require(!initialized, "already initialized");
        initialized = true;
        admin = _admin;
        supplyPauser = _supplyPauser;
    }

    function supply(address _referral, uint256 _wstethToMint, bytes calldata _params)
        external
        payable
        returns (uint256 stv)
    {
        stv = StvPool(payable(POOL)).depositETH{value: msg.value}(address(this), _referral);
        emit StrategySupplied(msg.sender, _referral, msg.value, stv, _wstethToMint, _params);
    }

    /// @notice Test helper: user deposits existing STV into strategy and receives wstETH.
    /// @dev This mimics a "wrapper C" flow where users who already hold STV (from wrapper B)
    ///      can enter a strategy and mint wstETH against the strategy's STV collateral.
    function depositStvAndMintWsteth(uint256 _stvAmount, uint256 _wstethToMint) external {
        require(initialized, "not initialized");
        require(_stvAmount > 0, "zero stv");
        require(_wstethToMint > 0, "zero wsteth");

        IERC20(address(StvPool(payable(POOL)))).transferFrom(msg.sender, address(this), _stvAmount);

        StvStETHPool pool = StvStETHPool(payable(POOL));
        pool.mintWsteth(_wstethToMint);

        address wsteth = address(pool.WSTETH());
        IERC20(wsteth).transfer(msg.sender, _wstethToMint);
    }

    function remainingMintingCapacitySharesOf(address, uint256) external pure returns (uint256) {
        return 0;
    }

    function requestExitByWsteth(uint256, bytes calldata) external pure returns (bytes32) {
        return bytes32(0);
    }

    function finalizeRequestExit(bytes32) external pure {}

    function burnWsteth(uint256) external pure {}

    function requestWithdrawalFromPool(address, uint256, uint256) external pure returns (uint256) {
        return 0;
    }

    function wstethOf(address) external pure returns (uint256) {
        return 0;
    }

    function stvOf(address) external pure returns (uint256) {
        return 0;
    }

    function mintedStethSharesOf(address) external pure returns (uint256) {
        return 0;
    }
}