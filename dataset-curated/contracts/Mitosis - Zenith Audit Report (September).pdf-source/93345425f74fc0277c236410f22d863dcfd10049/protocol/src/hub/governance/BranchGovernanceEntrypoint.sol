// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { IMessageRecipient } from '@hpl/interfaces/IMessageRecipient.sol';

import { ReentrancyGuard } from '@oz/utils/ReentrancyGuard.sol';
import { AccessControlEnumerableUpgradeable } from '@ozu/access/extensions/AccessControlEnumerableUpgradeable.sol';
import { Ownable2StepUpgradeable } from '@ozu/access/Ownable2StepUpgradeable.sol';
import { UUPSUpgradeable } from '@ozu/proxy/utils/UUPSUpgradeable.sol';

import { GasRouter } from '../../external/hyperlane/GasRouter.sol';
import { ICrossChainRegistry } from '../../interfaces/hub/cross-chain/ICrossChainRegistry.sol';
import { IBranchGovernanceEntrypoint } from '../../interfaces/hub/governance/IBranchGovernanceEntrypoint.sol';
import { Conv } from '../../lib/Conv.sol';
import { StdError } from '../../lib/StdError.sol';
import { Versioned } from '../../lib/Versioned.sol';
import '../../message/Message.sol';

contract BranchGovernanceEntrypoint is
  IBranchGovernanceEntrypoint,
  GasRouter,
  Ownable2StepUpgradeable,
  UUPSUpgradeable,
  ReentrancyGuard,
  AccessControlEnumerableUpgradeable,
  Versioned
{
  using Message for *;
  using Conv for *;

  /// @notice Role for manager (keccak256("MANAGER_ROLE"))
  bytes32 public constant MANAGER_ROLE = 0x241ecf16d79d0f8dbfb92cbc07fe17840425976cf0667f022fe9877caa831b08;

  ICrossChainRegistry internal immutable _ccRegistry;

  modifier onlyDispatchable(uint256 chainId) {
    require(_ccRegistry.isRegisteredChain(chainId), ICrossChainRegistry.ICrossChainRegistry__NotRegistered());
    require(
      _ccRegistry.governanceEntrypointEnrolled(chainId),
      ICrossChainRegistry.ICrossChainRegistry__GovernanceEntrypointNotEnrolled()
    );
    _;
  }

  constructor(address mailbox, address ccRegistry_) GasRouter(mailbox) initializer {
    require(ccRegistry_.code.length > 0, StdError.InvalidAddress('ccRegistry'));

    _ccRegistry = ICrossChainRegistry(ccRegistry_);
  }

  function initialize(address owner_, address[] memory managers, address hook, address ism) public initializer {
    __UUPSUpgradeable_init();

    __Ownable_init(_msgSender());
    __Ownable2Step_init();

    _MailboxClient_initialize(hook, ism);
    _transferOwnership(owner_);

    __AccessControlEnumerable_init();
    _grantRole(DEFAULT_ADMIN_ROLE, owner_);
    _setRoleAdmin(MANAGER_ROLE, DEFAULT_ADMIN_ROLE);

    for (uint256 i = 0; i < managers.length; i++) {
      _grantRole(MANAGER_ROLE, managers[i]);
    }
  }

  function quoteGovernanceExecution(
    uint256 chainId,
    address[] calldata targets,
    bytes[] calldata data,
    uint256[] calldata values,
    bytes32 predecessor,
    bytes32 salt
  ) external view returns (uint256) {
    bytes memory enc = MsgDispatchGovernanceExecution({
      targets: _convertAddressArrayToBytes32Array(targets),
      values: values,
      data: data,
      predecessor: predecessor,
      salt: salt
    }).encode();

    return _quoteToBranch(chainId, MsgType.MsgDispatchGovernanceExecution, enc);
  }

  function dispatchGovernanceExecution(
    uint256 chainId,
    address[] calldata targets,
    bytes[] calldata data,
    uint256[] calldata values,
    bytes32 predecessor,
    bytes32 salt
  ) external payable onlyRole(MANAGER_ROLE) onlyDispatchable(chainId) {
    bytes memory enc = MsgDispatchGovernanceExecution({
      targets: _convertAddressArrayToBytes32Array(targets),
      values: values,
      data: data,
      predecessor: predecessor,
      salt: salt
    }).encode();

    _dispatchToBranch(chainId, MsgType.MsgDispatchGovernanceExecution, enc);

    emit ExecutionDispatched(chainId, targets, values, data, predecessor, salt);
  }

  function _quoteToBranch(uint256 chainId, MsgType msgType, bytes memory enc) internal view returns (uint256) {
    uint32 hplDomain = _ccRegistry.hyperlaneDomain(chainId);
    uint96 action = uint96(msgType);
    return _GasRouter_quoteDispatch(hplDomain, action, enc, address(hook()));
  }

  function _dispatchToBranch(uint256 chainId, MsgType msgType, bytes memory enc) internal {
    uint32 hplDomain = _ccRegistry.hyperlaneDomain(chainId);

    uint96 action = uint96(msgType);
    uint256 fee = _GasRouter_quoteDispatch(hplDomain, action, enc, address(hook()));
    _GasRouter_dispatch(hplDomain, action, fee, enc, address(hook()));
  }

  function _handle(uint32, bytes32, bytes calldata) internal override { }

  function _convertAddressArrayToBytes32Array(address[] calldata arr)
    internal
    pure
    returns (bytes32[] memory addressed)
  {
    addressed = new bytes32[](arr.length);
    for (uint256 i = 0; i < arr.length; i++) {
      addressed[i] = arr[i].toBytes32();
    }
  }

  function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) { }

  function _authorizeManageMailbox(address) internal override onlyOwner { }

  function _authorizeConfigureGas(address sender) internal view override {
    require(sender == owner() || sender == address(_ccRegistry), StdError.Unauthorized());
  }

  function _authorizeConfigureRoute(address sender) internal view override {
    require(sender == owner() || sender == address(_ccRegistry), StdError.Unauthorized());
  }
}
