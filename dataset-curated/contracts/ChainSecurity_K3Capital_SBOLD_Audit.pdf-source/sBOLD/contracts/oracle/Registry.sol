// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IRegistry} from "../interfaces/IRegistry.sol";
import {IPriceOracle} from "../interfaces/IPriceOracle.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Common} from "../libraries/Common.sol";

/// @title Registry
/// @notice Registry for `IPriceOracle` compatible price oracles.
contract Registry is IRegistry, IPriceOracle, Ownable {
    /// @notice Onboarded price oracles mapped to base asset.
    mapping(address => address) public baseToOracle;

    /// @notice Deploys a price oracle registry.
    /// @dev Sets owner of the contract.
    constructor() Ownable(_msgSender()) {}

    /// @inheritdoc IRegistry
    function setOracles(Oracle[] calldata oracles) external onlyOwner {
        for (uint256 i = 0; i < oracles.length; i++) {
            Common.revertZeroAddress(oracles[i].base);
            // Map new oracle address to `base`
            baseToOracle[oracles[i].base] = oracles[i].addr;
            // Detach oracle from `base`
            if (oracles[i].addr == address(0)) continue;
            // Verify that `base` is supported
            if (!IPriceOracle(oracles[i].addr).isBaseSupported(oracles[i].base)) revert InvalidFeed();
        }

        emit OraclesSet(oracles);
    }

    /// @notice Derives quote from price oracle adapters.
    /// @param inAmount The amount of `base` to convert.
    /// @param base The token that is being priced.
    function getQuote(uint256 inAmount, address base) external view returns (uint256) {
        address _oracle = baseToOracle[base];

        // Check if the feed is supported
        if (_oracle == address(0)) revert InvalidFeed();

        // Get the actual quote for `base`
        return IPriceOracle(_oracle).getQuote(inAmount, base);
    }

    /// @inheritdoc IPriceOracle
    function isBaseSupported(address base) external view returns (bool) {
        return baseToOracle[base] != address(0);
    }
}
