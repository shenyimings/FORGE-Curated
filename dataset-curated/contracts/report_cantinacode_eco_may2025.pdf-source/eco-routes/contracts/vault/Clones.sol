// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Proxy} from "./Proxy.sol";

/**
 * @title Clones
 * @notice Library for deploying CREATE2 proxies using minimal proxy pattern
 * @dev Provides deterministic proxy deployment with address prediction functionality
 *      Based on ERC-1167 minimal proxy standard for gas-efficient contract cloning
 */
library Clones {
    /**
     * @notice Thrown when proxy deployment fails
     * @dev A clone instance deployment failed
     */
    error ERC1167FailedCreateClone();

    /**
     * @notice Deploys a minimal proxy contract using CREATE2
     * @dev Creates a new proxy instance that delegates all calls to the implementation
     * @param implementation Address of the implementation contract to proxy to
     * @param salt Unique salt for deterministic address generation
     * @return instance Address of the deployed proxy contract
     */
    function clone(
        address implementation,
        bytes32 salt
    ) internal returns (address instance) {
        instance = address(new Proxy{salt: salt}(implementation));
    }

    /**
     * @notice Predicts the address of a proxy before deployment
     * @dev Calculates deterministic CREATE2 address using implementation, salt, and prefix
     *      Supports different chain prefixes (standard 0xff, TRON 0x41, etc.)
     * @param implementation Address of the implementation contract
     * @param salt Salt used for address generation
     * @param prefix CREATE2 prefix byte (0xff for standard chains, 0x41 for TRON)
     * @return predicted The deterministic address where the proxy will be deployed
     */
    function predict(
        address implementation,
        bytes32 salt,
        bytes1 prefix
    ) internal view returns (address predicted) {
        /* Convert a hash which is bytes32 to an address which is 20-byte long
        according to https://docs.soliditylang.org/en/v0.8.9/control-structures.html?highlight=create2#salted-contract-creations-create2 */
        predicted = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            prefix,
                            address(this),
                            salt,
                            keccak256(
                                abi.encodePacked(
                                    type(Proxy).creationCode,
                                    abi.encode(implementation)
                                )
                            )
                        )
                    )
                )
            )
        );
    }
}
