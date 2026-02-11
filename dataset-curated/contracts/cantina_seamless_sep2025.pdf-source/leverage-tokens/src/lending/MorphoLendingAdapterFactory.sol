// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Dependency imports
import {Id} from "@morpho-blue/interfaces/IMorpho.sol";
import {Clones} from "openzeppelin-contracts/contracts/proxy/Clones.sol";

// Internal imports
import {IMorphoLendingAdapter} from "src/interfaces/IMorphoLendingAdapter.sol";
import {IMorphoLendingAdapterFactory} from "src/interfaces/IMorphoLendingAdapterFactory.sol";
import {MorphoLendingAdapter} from "src/lending/MorphoLendingAdapter.sol";

/**
 * @dev The MorphoLendingAdapterFactory is a factory contract for deploying ERC-1167 minimal proxies of the
 * MorphoLendingAdapter contract using OpenZeppelin's Clones library.
 *
 * @custom:contact security@seamlessprotocol.com
 */
contract MorphoLendingAdapterFactory is IMorphoLendingAdapterFactory {
    using Clones for address;

    /// @inheritdoc IMorphoLendingAdapterFactory
    IMorphoLendingAdapter public immutable lendingAdapterLogic;

    /// @param _lendingAdapterLogic Logic contract for deploying new MorphoLendingAdapters.
    constructor(IMorphoLendingAdapter _lendingAdapterLogic) {
        lendingAdapterLogic = _lendingAdapterLogic;
    }

    /// @inheritdoc IMorphoLendingAdapterFactory
    function computeAddress(address sender, bytes32 baseSalt) external view returns (address) {
        return Clones.predictDeterministicAddress(address(lendingAdapterLogic), salt(sender, baseSalt), address(this));
    }

    /// @inheritdoc IMorphoLendingAdapterFactory
    function deployAdapter(Id morphoMarketId, address authorizedCreator, bytes32 baseSalt)
        public
        returns (IMorphoLendingAdapter)
    {
        IMorphoLendingAdapter lendingAdapter =
            IMorphoLendingAdapter(address(lendingAdapterLogic).cloneDeterministic(salt(msg.sender, baseSalt)));
        emit MorphoLendingAdapterDeployed(lendingAdapter);

        MorphoLendingAdapter(address(lendingAdapter)).initialize(morphoMarketId, authorizedCreator);

        return lendingAdapter;
    }

    /// @notice Given the `sender` and `baseSalt`, return the salt that will be used for deployment.
    /// @param sender The address of the sender of the `deployAdapter` call.
    /// @param baseSalt The user-provided base salt.
    function salt(address sender, bytes32 baseSalt) internal pure returns (bytes32) {
        return keccak256(abi.encode(sender, baseSalt));
    }
}
