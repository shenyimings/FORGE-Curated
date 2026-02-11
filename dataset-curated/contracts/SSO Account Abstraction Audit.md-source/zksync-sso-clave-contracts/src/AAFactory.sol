// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { DEPLOYER_SYSTEM_CONTRACT, IContractDeployer } from "@matterlabs/zksync-contracts/l2/system-contracts/Constants.sol";
import { SystemContractsCaller } from "@matterlabs/zksync-contracts/l2/system-contracts/libraries/SystemContractsCaller.sol";

import { ISsoAccount } from "./interfaces/ISsoAccount.sol";

/// @title AAFactory
/// @author Matter Labs
/// @custom:security-contact security@matterlabs.dev
/// @dev This contract is used to deploy SSO accounts as beacon proxies.
contract AAFactory {
  /// @notice Emitted when a new account is successfully created.
  /// @param accountAddress The address of the newly created account.
  /// @param uniqueAccountId A unique identifier for the account.
  event AccountCreated(address indexed accountAddress, string uniqueAccountId);

  /// @dev The bytecode hash of the beacon proxy, used for deploying proxy accounts.
  bytes32 public immutable beaconProxyBytecodeHash;
  address public immutable beacon;

  /// @notice A mapping from unique account IDs to their corresponding deployed account addresses.
  mapping(string => address) public accountMappings;

  /// @notice Constructor that initializes the factory with a beacon proxy bytecode hash and implementation contract address.
  /// @param _beaconProxyBytecodeHash The bytecode hash of the beacon proxy.
  /// @param _beacon The address of the UpgradeableBeacon contract used for the SSO accounts' beacon proxies.
  constructor(bytes32 _beaconProxyBytecodeHash, address _beacon) {
    beaconProxyBytecodeHash = _beaconProxyBytecodeHash;
    beacon = _beacon;
  }

  function getEncodedBeacon() external view returns (bytes memory) {
    return abi.encode(beacon);
  }

  /// @notice Deploys a new SSO account as a beacon proxy with the specified parameters.
  /// @dev Uses `create2` to deploy a proxy account, allowing for deterministic addresses based on the provided salt.
  /// @param _salt The salt used for the `create2` deployment to make the address deterministic.
  /// @param _uniqueAccountId A unique identifier for the new account.
  /// @param _initialValidators An array of initial validators for the new account.
  /// @param _initialK1Owners An array of initial owners of the K1 key for the new account.
  /// @return accountAddress The address of the newly deployed SSO account.
  function deployProxySsoAccount(
    bytes32 _salt,
    string calldata _uniqueAccountId,
    bytes[] calldata _initialValidators,
    address[] calldata _initialK1Owners
  ) external returns (address accountAddress) {
    require(accountMappings[_uniqueAccountId] == address(0), "Account already exists");

    (bool success, bytes memory returnData) = SystemContractsCaller.systemCallWithReturndata(
      uint32(gasleft()),
      address(DEPLOYER_SYSTEM_CONTRACT),
      uint128(0),
      abi.encodeCall(
        DEPLOYER_SYSTEM_CONTRACT.create2Account,
        (_salt, beaconProxyBytecodeHash, abi.encode(beacon), IContractDeployer.AccountAbstractionVersion.Version1)
      )
    );
    require(success, "Deployment failed");
    (accountAddress) = abi.decode(returnData, (address));

    // Initialize the newly deployed account with validators, hooks and K1 owners.
    ISsoAccount(accountAddress).initialize(_initialValidators, _initialK1Owners);

    accountMappings[_uniqueAccountId] = accountAddress;

    emit AccountCreated(accountAddress, _uniqueAccountId);
  }
}
