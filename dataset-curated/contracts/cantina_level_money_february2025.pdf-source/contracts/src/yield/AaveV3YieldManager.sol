// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19;

import {SingleAdminAccessControl} from "../auth/v5/SingleAdminAccessControl.sol";
import {BaseYieldManager} from "./BaseYieldManager.sol";
import "../WrappedRebasingERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IPool} from "aave-v3-core/contracts/interfaces/IPool.sol";
import {DataTypes} from "aave-v3-core/contracts/protocol/libraries/types/DataTypes.sol";

/**
 * @title Aave Yield Manager
 * @notice This contract serves as middleware to wrap native tokens into ERC20
 *          wrapped aTokens
 */
contract AaveV3YieldManager is BaseYieldManager {
    using SafeERC20 for IERC20;

    event DepositedToAave(uint amount, address token);
    event WithdrawnFromAave(uint amount, address token);

    error TokenERC20WrapperNotSet();
    error InvalidWrapper();
    error TokenAndWrapperDecimalsMismatch();
    error ZeroYieldToWithdraw();

    /* --------------- STATE VARIABLES --------------- */

    // aave pool proxy
    IPool public aavePoolProxy;
    mapping(address => address) public aTokenToUnderlying;
    mapping(address => address) public underlyingToaToken;

    // mapping of a token address to an ERC20 wrapper address
    mapping(address => address) public tokenToWrapper;

    /* --------------- CONSTRUCTOR --------------- */

    constructor(IPool _aavePoolProxy, address _admin) BaseYieldManager(_admin) {
        aavePoolProxy = _aavePoolProxy;
    }

    /* --------------- INTERNAL --------------- */

    function _wrapToken(address token, uint256 amount) internal {
        if (tokenToWrapper[token] == address(0)) {
            revert TokenERC20WrapperNotSet();
        }
        IERC20(token).forceApprove(tokenToWrapper[token], amount);
        WrappedRebasingERC20(tokenToWrapper[token]).depositFor(
            address(this),
            amount
        );
    }

    function _unwrapToken(address wrapper, uint256 amount) internal {
        WrappedRebasingERC20(wrapper).withdrawTo(address(this), amount);
    }

    function _withdrawFromAave(address token, uint256 amount) internal {
        aavePoolProxy.withdraw(token, amount, address(this));
        emit WithdrawnFromAave(amount, token);
    }

    function _depositToAave(address token, uint256 amount) internal {
        IERC20(token).forceApprove(address(aavePoolProxy), amount);
        aavePoolProxy.supply(token, amount, address(this), 0);
        emit DepositedToAave(amount, token);
    }

    function _getATokenAddress(address underlying) internal returns (address) {
        DataTypes.ReserveData memory reserveData = aavePoolProxy.getReserveData(
            underlying
        );
        if (aTokenToUnderlying[reserveData.aTokenAddress] == address(0)) {
            aTokenToUnderlying[reserveData.aTokenAddress] = underlying;
        }
        if (underlyingToaToken[underlying] == address(0)) {
            underlyingToaToken[underlying] = reserveData.aTokenAddress;
        }
        return reserveData.aTokenAddress;
    }

    /* --------------- EXTERNAL --------------- */

    // deposit collateral to Aave pool, and immediately wrap AToken in
    // wrapper class, so that AToken rewards accrue to that contract and not this one.
    // https://docs.aave.com/developers/deployed-contracts/v3-testnet-addresses
    function depositForYield(address token, uint256 amount) external {
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        _depositToAave(token, amount);
        address aTokenAddress = _getATokenAddress(token);
        _wrapToken(aTokenAddress, amount);
        IERC20(tokenToWrapper[aTokenAddress]).safeTransfer(msg.sender, amount);
    }

    function withdraw(
        address token, // e.g. USDC
        uint256 amount // quoted in terms of underlying (e.g. USDC)
    ) external {
        address aTokenAddress = underlyingToaToken[token];
        address wrapper = tokenToWrapper[aTokenAddress];
        IERC20(wrapper).safeTransferFrom(msg.sender, address(this), amount);
        _unwrapToken(wrapper, amount);
        _withdrawFromAave(token, amount); // burns aTokens held nby this contract
        IERC20(token).safeTransfer(msg.sender, amount);
    }

    // collect all accrued yield in the form of native token
    function collectYield(
        address token // e.g. USDC
    ) external onlyRole(YIELD_RECOVERER_ROLE) returns (uint256) {
        address aTokenAddress = underlyingToaToken[token];
        address wrapper = tokenToWrapper[aTokenAddress];
        // amount is quoted in terms of the underlying of the aToken
        // that is transferred to this contract by recoverUnderlying (e.g. USDC)
        uint amount = WrappedRebasingERC20(wrapper).recoverUnderlying();
        if (amount == 0) {
            revert ZeroYieldToWithdraw();
        }
        // the amount argument here is quoted in terms of the underlying (e.g. USDC)
        _withdrawFromAave(token, amount);
        IERC20(token).safeTransfer(msg.sender, amount);
        return amount;
    }

    /* --------------- SETTERS --------------- */

    function setAaveV3PoolAddress(
        address newAddress
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        aavePoolProxy = IPool(newAddress);
    }

    function setWrapperForToken(
        address token,
        address wrapper
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (address(WrappedRebasingERC20(wrapper).underlying()) != token) {
            revert InvalidWrapper();
        }
        if (ERC20(token).decimals() != ERC20(wrapper).decimals()) {
            revert TokenAndWrapperDecimalsMismatch();
        }
        tokenToWrapper[token] = wrapper;
    }
}
