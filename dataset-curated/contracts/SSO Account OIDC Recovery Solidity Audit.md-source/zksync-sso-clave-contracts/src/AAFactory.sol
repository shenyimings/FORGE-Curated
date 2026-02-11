// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { DEPLOYER_SYSTEM_CONTRACT } from "@matterlabs/zksync-contracts/l2/system-contracts/Constants.sol";
import { IContractDeployer } from "@matterlabs/zksync-contracts/l2/system-contracts/interfaces/IContractDeployer.sol";
import { SystemContractsCaller } from "@matterlabs/zksync-contracts/l2/system-contracts/libraries/SystemContractsCaller.sol";

import { ISsoAccount } from "./interfaces/ISsoAccount.sol";
import { Errors } from "./libraries/Errors.sol";

/// @title AAFactory
/// @author Matter Labs
/// @custom:security-contact security@matterlabs.dev
/// @dev This contract is used to deploy SSO accounts as beacon proxies.
contract AAFactory {
  /// @notice Emitted when a new account is successfully created.
  /// @param accountAddress The address of the newly created account.
  /// @param uniqueAccountId A unique identifier for the account.
  event AccountCreated(address indexed accountAddress, bytes32 uniqueAccountId);

  /// @dev The bytecode hash of the beacon proxy, used for deploying proxy accounts.
  bytes32 public immutable beaconProxyBytecodeHash;
  /// @dev The address of the SsoBeacon contract used for the SSO accounts' beacon proxies.
  address public immutable beacon;

  /// @notice A mapping from unique account IDs to their corresponding deployed account addresses.
  mapping(bytes32 accountId => address deployedAccount) public accountMappings;

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
  /// @dev Uses `create2` to deploy a proxy account, allowing for deterministic addresses based on the provided unique id.
  /// @param uniqueId Use to generate a unique account id and deterministic address calculation (create2 salt).
  /// @param initialValidators An array of initial validators for the new account.
  /// @param initialK1Owners An array of initial owners of the K1 key for the new account.
  /// @return accountAddress The address of the newly deployed SSO account.
  function deployProxySsoAccount(
    bytes32 uniqueId,
    bytes[] calldata initialValidators,
    address[] calldata initialK1Owners
  ) external returns (address accountAddress) {
    bytes32 uniqueAccountId = keccak256(abi.encodePacked(uniqueId, msg.sender));
    address existingAccountAddress = accountMappings[uniqueAccountId];
    if (existingAccountAddress != address(0)) {
      revert Errors.ACCOUNT_ALREADY_EXISTS(existingAccountAddress);
    }

    bytes memory returnData = SystemContractsCaller.systemCallWithPropagatedRevert(
      uint32(gasleft()),
      address(DEPLOYER_SYSTEM_CONTRACT),
      uint128(0),
      abi.encodeCall(
        DEPLOYER_SYSTEM_CONTRACT.create2Account,
        (
          uniqueAccountId,
          beaconProxyBytecodeHash,
          abi.encode(beacon),
          IContractDeployer.AccountAbstractionVersion.Version1
        )
      )
    );
    (accountAddress) = abi.decode(returnData, (address));

    accountMappings[uniqueAccountId] = accountAddress;

    // Initialize the newly deployed account with validators and K1 owners.
    ISsoAccount(accountAddress).initialize(initialValidators, initialK1Owners);

    emit AccountCreated(accountAddress, uniqueAccountId);
  }
}
