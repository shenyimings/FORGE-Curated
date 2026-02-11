// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2024.
pragma solidity ^0.8.23;

import {IVersion} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IVersion.sol";

interface IInstanceManager is IVersion {
    function addressProvider() external view returns (address);
    function bytecodeRepository() external view returns (address);
    function instanceManagerProxy() external view returns (address);
    function treasuryProxy() external view returns (address);
    function crossChainGovernanceProxy() external view returns (address);
    function isActivated() external view returns (bool);

    function activate(address instanceOwner, address treasury, address weth, address gear) external;
    function deploySystemContract(bytes32 contractType, uint256 version, bool saveVersion) external;
    function setGlobalAddress(string memory key, address addr, bool saveVersion) external;
    function setLocalAddress(string memory key, address addr, bool saveVersion) external;
    function configureGlobal(address target, bytes calldata data) external;
    function configureLocal(address target, bytes calldata data) external;
    function configureTreasury(address target, bytes calldata data) external;
}
