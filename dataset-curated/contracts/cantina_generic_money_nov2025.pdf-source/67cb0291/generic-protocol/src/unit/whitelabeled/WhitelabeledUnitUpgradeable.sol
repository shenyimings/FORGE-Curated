// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Metadata, IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {
    ERC20PermitUpgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";

import { IWhitelabeledUnit } from "../../interfaces/IWhitelabeledUnit.sol";

/**
 * @title WhitelabeledUnitUpgradeable
 * @notice Upgradeable implementation of a whitelabeled unit token that wraps underlying Generic units
 * @dev This contract provides a concrete implementation of the IWhitelabeledUnit interface using
 * OpenZeppelin's upgradeable contracts pattern. It enables wrapping of underlying unit tokens
 * into a branded token with custom name and symbol while maintaining 1:1 conversion mechanics.
 *
 * Key features:
 * - Upgradeable proxy pattern for future enhancements
 * - EIP-2612 permit functionality for gasless approvals via off-chain signatures
 * - 1:1 wrapping and unwrapping of underlying unit tokens
 * - Safe token transfers using OpenZeppelin's SafeERC20
 * - Event emission for transparent tracking of wrap/unwrap operations
 * - Virtual functions allowing for customization in derived contracts
 */
contract WhitelabeledUnitUpgradeable is IWhitelabeledUnit, ERC20PermitUpgradeable {
    using SafeERC20 for IERC20;

    /**
     * @notice The address of the underlying Generic unit token that this contract wraps
     */
    IERC20 private _genericUnit;

    /**
     * @notice Contract constructor that disables initializers for the implementation contract
     * @dev This prevents the implementation contract from being initialized directly.
     * Only proxy contracts can call initializer functions, ensuring proper upgradeable pattern usage.
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Internal initialization function for setting up the whitelabeled unit token
     * @dev This function initializes the ERC20Permit token with the provided name and symbol,
     * sets up EIP-2612 permit functionality, and configures the underlying unit token address.
     * @param name_ The human-readable name for the whitelabeled token (e.g., "Generic USD")
     * @param symbol_ The symbol for the whitelabeled token (e.g., "GUSD")
     * @param genericUnit_ The address of the underlying Generic unit token to wrap
     */
    // forge-lint: disable-next-line(mixed-case-function)
    function __WhitelabeledUnit_init(
        string memory name_,
        string memory symbol_,
        IERC20 genericUnit_
    )
        internal
        onlyInitializing
    {
        __ERC20_init(name_, symbol_);
        __ERC20Permit_init(name_);
        _genericUnit = genericUnit_;
    }

    /**
     * @inheritdoc IWhitelabeledUnit
     */
    function wrap(address owner, uint256 amount) external virtual {
        _genericUnit.safeTransferFrom(msg.sender, address(this), amount);
        _mint(owner, amount);
        emit Wrapped(owner, amount);
    }

    /**
     * @inheritdoc IWhitelabeledUnit
     */
    function unwrap(address owner, address recipient, uint256 amount) external virtual {
        _burn(owner, amount);
        if (msg.sender != owner) _spendAllowance(owner, msg.sender, amount);
        _genericUnit.safeTransfer(recipient, amount);
        emit Unwrapped(owner, recipient, amount);
    }

    /**
     * @inheritdoc IWhitelabeledUnit
     */
    function genericUnit() external view returns (address) {
        return address(_genericUnit);
    }

    /**
     * @notice Returns the number of decimals used by the whitelabeled unit token
     * @dev This function overrides the default ERC20 decimals implementation to
     * match the decimals of the underlying unit token, ensuring consistency in value representation.
     */
    function decimals() public view override returns (uint8) {
        return IERC20Metadata(address(_genericUnit)).decimals();
    }
}
