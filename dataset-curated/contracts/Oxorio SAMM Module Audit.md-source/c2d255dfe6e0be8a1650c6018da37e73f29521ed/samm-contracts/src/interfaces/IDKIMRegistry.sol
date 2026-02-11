// SPDX-License-Identifier: GPL-3
pragma solidity 0.8.23;

interface IDKIMRegistry {
    function isDKIMPublicKeyHashValid(string memory domainName, bytes32 publicKeyHash) external view returns (bool);
}
