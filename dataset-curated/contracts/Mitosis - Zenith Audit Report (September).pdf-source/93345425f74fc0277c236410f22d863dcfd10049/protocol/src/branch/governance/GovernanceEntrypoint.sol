// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { AccessControlEnumerableUpgradeable } from '@ozu/access/extensions/AccessControlEnumerableUpgradeable.sol';
import { UUPSUpgradeable } from '@ozu/proxy/utils/UUPSUpgradeable.sol';

import { GasRouter } from '../../external/hyperlane/GasRouter.sol';
import { IGovernanceEntrypoint } from '../../interfaces/branch/governance/IGovernanceEntrypoint.sol';
import { Conv } from '../../lib/Conv.sol';
import { StdError } from '../../lib/StdError.sol';
import { Timelock } from '../../lib/Timelock.sol';
import { Versioned } from '../../lib/Versioned.sol';
import '../../message/Message.sol';

contract GovernanceEntrypoint is
  IGovernanceEntrypoint,
  GasRouter,
  UUPSUpgradeable,
  AccessControlEnumerableUpgradeable,
  Versioned
{
  using Message for *;
  using Conv for *;

  Timelock internal immutable _timelock;
  uint32 internal immutable _mitosisDomain;
  bytes32 internal immutable _mitosisAddr; // Hub.BranchGovernanceEntrypoint

  constructor(address mailbox, Timelock timelock_, uint32 mitosisDomain_, bytes32 mitosisAddr_)
    GasRouter(mailbox)
    initializer
  {
    _timelock = timelock_;
    _mitosisDomain = mitosisDomain_;
    _mitosisAddr = mitosisAddr_;
  }

  function initialize(address owner_, address hook, address ism) public initializer {
    __UUPSUpgradeable_init();

    __AccessControlEnumerable_init();
    _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());

    _MailboxClient_initialize(hook, ism);
    _revokeRole(DEFAULT_ADMIN_ROLE, _msgSender());
    _grantRole(DEFAULT_ADMIN_ROLE, owner_);

    _enrollRemoteRouter(_mitosisDomain, _mitosisAddr);
  }

  receive() external payable { }

  //=========== NOTE: HANDLER FUNCTIONS ===========//

  function _handle(uint32 origin, bytes32 sender, bytes calldata msg_) internal override {
    require(origin == _mitosisDomain && sender == _mitosisAddr, StdError.Unauthorized());

    MsgType msgType = msg_.msgType();

    if (msgType == MsgType.MsgDispatchGovernanceExecution) {
      MsgDispatchGovernanceExecution memory decoded = msg_.decodeDispatchGovernanceExecution();
      _timelock.scheduleBatch(
        _convertBytes32ArrayToAddressArray(decoded.targets),
        decoded.values,
        decoded.data,
        decoded.predecessor,
        decoded.salt,
        _timelock.getMinDelay()
      );
    }
  }

  function _convertBytes32ArrayToAddressArray(bytes32[] memory targets)
    internal
    pure
    returns (address[] memory addressed)
  {
    addressed = new address[](targets.length);
    for (uint256 i = 0; i < targets.length; i++) {
      addressed[i] = targets[i].toAddress();
    }
  }

  //=========== NOTE: Internal methods ===========//

  function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) { }

  function _authorizeConfigureGas(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) { }

  function _authorizeConfigureRoute(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) { }

  function _authorizeManageMailbox(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) { }
}
