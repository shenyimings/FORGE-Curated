// SPDX-FileCopyrightText: 2024 Lido <info@lido.fi>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ManageableStub} from "./ManageableStub.sol";

interface IOrder {
    function AGENT() external view returns (address);

    function isValidSignature(
        bytes32 hash,
        bytes calldata
    ) external view returns (bytes4 magicValue);

    function getOrderDetails()
        external
        view
        returns (bytes32, address, address, uint256, uint256, uint32);
}

error InvalidSignature();

/**
 * @title Stub for the CoWSwap's VaultRelayer contract
 * @notice Contract is supposed to be used as the stub for the relayer address in the StonksFactory
 *     and Order contracts to fill the order, returning tokenFrom from the order instance to the
 *     agent instead of performing a swap.
 */
contract CoWSwapVaultRelayerStub is ManageableStub {
    using SafeERC20 for IERC20;

    // ==================== Constants ====================

    bytes4 private constant ERC1271_MAGIC_VALUE = 0x1626ba7e;

    // ==================== Constructor ====================

    constructor(address owner_, address manager_) ManageableStub(owner_, manager_) {
        owner = owner_;
    }

    // ==================== External Functions ====================

    /**
     * @notice Fills an order by transferring tokens from the order to the agent.
     * @param order The order contract to fill.
     */
    function fill(IOrder order) external onlyManager {
        (bytes32 hash, address tokenFrom, , uint256 sellAmount, , ) = order.getOrderDetails();

        if (order.isValidSignature(hash, new bytes(0)) != ERC1271_MAGIC_VALUE) {
            revert InvalidSignature();
        }

        IERC20(tokenFrom).safeTransferFrom(address(order), order.AGENT(), sellAmount);
    }
}
