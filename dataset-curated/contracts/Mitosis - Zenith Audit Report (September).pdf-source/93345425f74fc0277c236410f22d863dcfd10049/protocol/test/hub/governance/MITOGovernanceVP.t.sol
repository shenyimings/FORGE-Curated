// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { IVotes } from '@oz/governance/utils/IVotes.sol';
import { MessageHashUtils } from '@oz/utils/cryptography/MessageHashUtils.sol';
import { Nonces } from '@oz/utils/Nonces.sol';

import { MITOGovernanceVP } from '../../../src/hub/governance/MITOGovernanceVP.sol';
import { ISudoVotes } from '../../../src/interfaces/lib/ISudoVotes.sol';
import { MockContract } from '../../util/MockContract.sol';
import { Toolkit } from '../../util/Toolkit.sol';

contract MITOGovernanceVPTest is Toolkit {
  address owner = makeAddr('owner');
  address user1;
  uint256 user1Key;
  address user2;
  uint256 user2Key;

  MockContract vpt1;
  MockContract vpt2;
  ISudoVotes[] vpts;
  MITOGovernanceVP vp;

  function setUp() public {
    (user1, user1Key) = makeAddrAndKey('user1');
    (user2, user2Key) = makeAddrAndKey('user2');

    vpt1 = new MockContract();
    vpt2 = new MockContract();

    vpt1.setCall(ISudoVotes.sudoDelegate.selector);
    vpt2.setCall(ISudoVotes.sudoDelegate.selector);

    vpts.push(ISudoVotes(address(vpt1)));
    vpts.push(ISudoVotes(address(vpt2)));

    vp = MITOGovernanceVP(
      _proxy(
        address(new MITOGovernanceVP()), //
        abi.encodeCall(MITOGovernanceVP.initialize, (owner, vpts))
      )
    );
  }

  function test_init() public view {
    assertEq(vp.owner(), owner);
    assertEq(vp.tokens().length, 2);
    assertEq(address(vp.tokens()[0]), address(vpt1));
    assertEq(address(vp.tokens()[1]), address(vpt2));
  }

  function test_updateTokens() public {
    vm.prank(user1);
    vm.expectRevert(_errOwnableUnauthorizedAccount(user1));
    vp.updateTokens(new ISudoVotes[](0));

    vm.prank(owner);
    vm.expectRevert(abi.encodeWithSelector(MITOGovernanceVP.MITOGovernanceVP__InvalidToken.selector, (address(0))));
    vp.updateTokens(new ISudoVotes[](1));

    vm.prank(owner);
    vm.expectEmit();
    emit MITOGovernanceVP.TokensUpdated(vpts, vpts);
    vp.updateTokens(vpts);

    assertEq(vp.tokens().length, 2);
    assertEq(address(vp.tokens()[0]), address(vpt1));
    assertEq(address(vp.tokens()[1]), address(vpt2));
  }

  function test_getVotes() public {
    vpt1.setRet(abi.encodeCall(IVotes.getVotes, (user1)), false, abi.encode(100));
    vpt2.setRet(abi.encodeCall(IVotes.getVotes, (user1)), false, abi.encode(200));

    assertEq(vp.getVotes(user1), 300);
  }

  function test_getPastVotes() public {
    vpt1.setRet(abi.encodeCall(IVotes.getPastVotes, (user1, 0)), false, abi.encode(100));
    vpt2.setRet(abi.encodeCall(IVotes.getPastVotes, (user1, 0)), false, abi.encode(200));

    assertEq(vp.getPastVotes(user1, 0), 300);
  }

  function test_getPastTotalSupply() public {
    vpt1.setRet(abi.encodeCall(IVotes.getPastTotalSupply, (0)), false, abi.encode(100));
    vpt2.setRet(abi.encodeCall(IVotes.getPastTotalSupply, (0)), false, abi.encode(200));

    assertEq(vp.getPastTotalSupply(0), 300);
  }

  function test_delegates() public {
    vpt1.setRet(abi.encodeCall(IVotes.delegates, (user1)), false, abi.encode(user2));
    vpt2.setRet(abi.encodeCall(IVotes.delegates, (user1)), false, abi.encode(user1));

    // always pick the first token's delegate
    assertEq(vp.delegates(user1), user2);
  }

  function test_delegate() public {
    vpt1.setRet(abi.encodeCall(IVotes.delegates, (user1)), false, abi.encode(0));
    vpt2.setRet(abi.encodeCall(IVotes.delegates, (user1)), false, abi.encode(0));

    vm.prank(user1);
    vm.expectEmit();
    emit IVotes.DelegateChanged(user1, address(0), user2);
    vp.delegate(user2);

    vpt1.assertLastCall(abi.encodeCall(ISudoVotes.sudoDelegate, (user1, user2)));
    vpt2.assertLastCall(abi.encodeCall(ISudoVotes.sudoDelegate, (user1, user2)));
  }

  function test_delegateBySig() public {
    bytes32 hash_;
    {
      (, string memory name, string memory version, uint256 chainId, address verifyingContract,,) = vp.eip712Domain();

      hash_ = MessageHashUtils.toTypedDataHash(
        keccak256(
          abi.encode(
            keccak256('EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)'),
            keccak256(bytes(name)),
            keccak256(bytes(version)),
            chainId,
            verifyingContract
          )
        ),
        keccak256(abi.encode(keccak256('Delegation(address delegatee,uint256 nonce,uint256 expiry)'), user1, 0, 1 days))
      );
    }

    (uint8 v, bytes32 r, bytes32 s) = vm.sign(user2Key, hash_);

    vpt1.setRet(abi.encodeCall(IVotes.delegates, (user2)), false, abi.encode(0));
    vpt2.setRet(abi.encodeCall(IVotes.delegates, (user2)), false, abi.encode(0));

    vm.prank(owner);
    vm.expectEmit();
    emit IVotes.DelegateChanged(user2, address(0), user1);
    vp.delegateBySig(user1, 0, 1 days, v, r, s);

    vpt1.assertLastCall(abi.encodeCall(ISudoVotes.sudoDelegate, (user2, user1)));
    vpt2.assertLastCall(abi.encodeCall(ISudoVotes.sudoDelegate, (user2, user1)));
  }
}
