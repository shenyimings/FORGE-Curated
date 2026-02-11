// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { IVotes } from '@oz/governance/utils/IVotes.sol';
import { ECDSA } from '@oz/utils/cryptography/ECDSA.sol';
import { Ownable2StepUpgradeable } from '@ozu/access/Ownable2StepUpgradeable.sol';
import { UUPSUpgradeable } from '@ozu/proxy/utils/UUPSUpgradeable.sol';
import { EIP712Upgradeable } from '@ozu/utils/cryptography/EIP712Upgradeable.sol';
import { NoncesUpgradeable } from '@ozu/utils/NoncesUpgradeable.sol';

import { ISudoVotes } from '../../interfaces/lib/ISudoVotes.sol';
import { ERC7201Utils } from '../../lib/ERC7201Utils.sol';
import { StdError } from '../../lib/StdError.sol';
import { Versioned } from '../../lib/Versioned.sol';

contract MITOGovernanceVP is
  IVotes,
  Ownable2StepUpgradeable,
  UUPSUpgradeable,
  EIP712Upgradeable,
  NoncesUpgradeable,
  Versioned
{
  using ERC7201Utils for string;

  event TokensUpdated(ISudoVotes[] oldTokens, ISudoVotes[] newTokens);

  error MITOGovernanceVP__ZeroLengthTokens();
  error MITOGovernanceVP__InvalidToken(address token);
  error MITOGovernanceVP__MaxTokensLengthExceeded(uint256 max, uint256 actual);

  uint256 public constant MAX_TOKENS = 25;

  bytes32 private constant DELEGATION_TYPEHASH = keccak256('Delegation(address delegatee,uint256 nonce,uint256 expiry)');

  struct StorageV1 {
    ISudoVotes[] tokens;
  }

  string private constant _NAMESPACE = 'mitosis.storage.MITOGovernanceVP.v1';
  bytes32 private immutable _slot = _NAMESPACE.storageSlot();

  function _getStorageV1() internal view returns (StorageV1 storage $) {
    bytes32 slot = _slot;
    // slither-disable-next-line assembly
    assembly {
      $.slot := slot
    }
  }

  constructor() {
    _disableInitializers();
  }

  function initialize(address owner_, ISudoVotes[] calldata tokens_) external initializer {
    __Ownable2Step_init();
    __Ownable_init(owner_);
    __UUPSUpgradeable_init();
    __EIP712_init('Mitosis Governance VP', '1');
    __Nonces_init();

    _getStorageV1().tokens = tokens_;
  }

  function tokens() external view returns (ISudoVotes[] memory) {
    return _getStorageV1().tokens;
  }

  function updateTokens(ISudoVotes[] calldata newTokens_) external onlyOwner {
    require(newTokens_.length > 0, MITOGovernanceVP__ZeroLengthTokens());
    require(newTokens_.length <= MAX_TOKENS, MITOGovernanceVP__MaxTokensLengthExceeded(MAX_TOKENS, newTokens_.length));

    uint256 newTokensLen = newTokens_.length;
    for (uint256 i = 0; i < newTokensLen;) {
      require(
        address(newTokens_[i]).code.length > 0, //
        MITOGovernanceVP__InvalidToken(address(newTokens_[i]))
      );

      unchecked {
        i++;
      }
    }

    StorageV1 storage $ = _getStorageV1();
    ISudoVotes[] memory oldTokens = $.tokens;
    $.tokens = newTokens_;

    emit TokensUpdated(oldTokens, newTokens_);
  }

  function getVotes(address account) external view returns (uint256) {
    uint256 votes = 0;
    ISudoVotes[] memory tokens_ = _getStorageV1().tokens;
    uint256 tokensLen = tokens_.length;
    for (uint256 i = 0; i < tokensLen; i++) {
      votes += tokens_[i].getVotes(account);
    }
    return votes;
  }

  function getPastVotes(address account, uint256 timepoint) external view returns (uint256) {
    uint256 votes = 0;
    ISudoVotes[] memory tokens_ = _getStorageV1().tokens;
    uint256 tokensLen = tokens_.length;
    for (uint256 i = 0; i < tokensLen; i++) {
      votes += tokens_[i].getPastVotes(account, timepoint);
    }
    return votes;
  }

  function getPastTotalSupply(uint256 timepoint) external view returns (uint256) {
    uint256 totalSupply = 0;
    ISudoVotes[] memory tokens_ = _getStorageV1().tokens;
    uint256 tokensLen = tokens_.length;
    for (uint256 i = 0; i < tokensLen; i++) {
      totalSupply += tokens_[i].getPastTotalSupply(timepoint);
    }
    return totalSupply;
  }

  function delegates(address account) external view returns (address) {
    return _getStorageV1().tokens[0].delegates(account);
  }

  function delegate(address delegatee) external {
    address account = _msgSender();
    _delegate(account, delegatee);
  }

  function delegateBySig(address delegatee, uint256 nonce, uint256 expiry, uint8 v, bytes32 r, bytes32 s) external {
    require(block.timestamp <= expiry, VotesExpiredSignature(expiry));

    bytes32 hash_ = _hashTypedDataV4(keccak256(abi.encode(DELEGATION_TYPEHASH, delegatee, nonce, expiry)));
    address signer = ECDSA.recover(hash_, v, r, s);

    _useCheckedNonce(signer, nonce);
    _delegate(signer, delegatee);
  }

  function _delegate(address account, address delegatee) internal {
    address previousDelegate = _getStorageV1().tokens[0].delegates(account);

    ISudoVotes[] memory tokens_ = _getStorageV1().tokens;
    uint256 tokensLen = tokens_.length;
    for (uint256 i = 0; i < tokensLen; i++) {
      tokens_[i].sudoDelegate(account, delegatee);
    }

    emit DelegateChanged(account, previousDelegate, delegatee);
  }

  function _authorizeUpgrade(address) internal override onlyOwner { }
}
