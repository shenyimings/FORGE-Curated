// SPDX-License-Identifier: MIT OR Apache-2.0
// Forked from @hyperlane-xyz/core (https://github.com/hyperlane-xyz/hyperlane-monorepo)
// - rev: https://github.com/hyperlane-xyz/hyperlane-monorepo/commit/42ccee13eb99313a4a078f36938aec6dab16990c
// Modified by Mitosis Team
//
// CHANGES:
// - Use ERC7201 Namespaced Storage for storage variables.
pragma solidity >=0.6.11;

import { IPostDispatchHook } from '@hpl/interfaces/hooks/IPostDispatchHook.sol';
import { IInterchainSecurityModule } from '@hpl/interfaces/IInterchainSecurityModule.sol';
import { IMailbox } from '@hpl/interfaces/IMailbox.sol';
import { Message } from '@hpl/libs/Message.sol';
import { PackageVersioned } from '@hpl/PackageVersioned.sol';

import { Address } from '@oz/utils/Address.sol';
import { OwnableUpgradeable } from '@ozu/access/OwnableUpgradeable.sol';

import { ERC7201Utils } from '../../lib/ERC7201Utils.sol';

/*@@@@@@@       @@@@@@@@@
 @@@@@@@@@       @@@@@@@@@
  @@@@@@@@@       @@@@@@@@@
   @@@@@@@@@       @@@@@@@@@
    @@@@@@@@@@@@@@@@@@@@@@@@@
     @@@@@  HYPERLANE  @@@@@@@
    @@@@@@@@@@@@@@@@@@@@@@@@@
   @@@@@@@@@       @@@@@@@@@
  @@@@@@@@@       @@@@@@@@@
 @@@@@@@@@       @@@@@@@@@
@@@@@@@@@       @@@@@@@@*/
abstract contract MailboxClient is OwnableUpgradeable, PackageVersioned {
  using Message for bytes;
  using ERC7201Utils for string;

  event HookSet(address _hook);
  event IsmSet(address _ism);

  IMailbox public immutable mailbox;
  uint32 public immutable localDomain;

  struct MailboxClientStorage {
    IPostDispatchHook hook;
    IInterchainSecurityModule interchainSecurityModule;
  }

  string private constant _MAILBOX_CLIENT_STORAGE_NAMESPACE = 'hyperlane.storage.MailboxClient';
  bytes32 private immutable _slot = _MAILBOX_CLIENT_STORAGE_NAMESPACE.storageSlot();

  function _getHplMailboxClientStorage() internal view returns (MailboxClientStorage storage $) {
    bytes32 slot = _slot;
    assembly {
      $.slot := slot
    }
  }

  // ============ Getters ============
  function hook() public view returns (IPostDispatchHook) {
    return _getHplMailboxClientStorage().hook;
  }

  function interchainSecurityModule() public view returns (IInterchainSecurityModule) {
    return _getHplMailboxClientStorage().interchainSecurityModule;
  }

  // ============ Modifiers ============
  modifier onlyContract(address _contract) {
    require(_contract.code.length > 0, 'MailboxClient: invalid mailbox');
    _;
  }

  modifier onlyContractOrNull(address _contract) {
    require(_contract.code.length > 0 || _contract == address(0), 'MailboxClient: invalid contract setting');
    _;
  }

  /**
   * @notice Only accept messages from a Hyperlane Mailbox contract
   */
  modifier onlyMailbox() {
    require(msg.sender == address(mailbox), 'MailboxClient: sender not mailbox');
    _;
  }

  constructor(address _mailbox) onlyContract(_mailbox) {
    mailbox = IMailbox(_mailbox);
    localDomain = mailbox.localDomain();
    _transferOwnership(msg.sender);
  }

  /**
   * @notice Sets the address of the application's custom hook.
   * @param _hook The address of the hook contract.
   */
  function setHook(address _hook) public virtual onlyContractOrNull(_hook) onlyOwner {
    _getHplMailboxClientStorage().hook = IPostDispatchHook(_hook);
    emit HookSet(_hook);
  }

  /**
   * @notice Sets the address of the application's custom interchain security module.
   * @param _module The address of the interchain security module contract.
   */
  function setInterchainSecurityModule(address _module) public onlyContractOrNull(_module) onlyOwner {
    _getHplMailboxClientStorage().interchainSecurityModule = IInterchainSecurityModule(_module);
    emit IsmSet(_module);
  }

  // ======== Initializer =========
  function _MailboxClient_initialize(address _hook, address _interchainSecurityModule, address _owner)
    internal
    onlyInitializing
  {
    __Ownable_init(_owner);

    setHook(_hook);
    setInterchainSecurityModule(_interchainSecurityModule);
  }

  function _isLatestDispatched(bytes32 id) internal view returns (bool) {
    return mailbox.latestDispatchedId() == id;
  }

  function _isDelivered(bytes32 id) internal view returns (bool) {
    return mailbox.delivered(id);
  }
}
