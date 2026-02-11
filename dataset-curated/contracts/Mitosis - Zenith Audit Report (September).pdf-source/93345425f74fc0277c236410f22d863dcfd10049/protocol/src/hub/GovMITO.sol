// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { IVotes } from '@oz/governance/utils/IVotes.sol';
import { IERC20 } from '@oz/interfaces/IERC20.sol';
import { IERC6372 } from '@oz/interfaces/IERC6372.sol';
import { SafeCast } from '@oz/utils/math/SafeCast.sol';
import { ReentrancyGuard } from '@oz/utils/ReentrancyGuard.sol';
import { Time } from '@oz/utils/types/Time.sol';
import { Ownable2StepUpgradeable } from '@ozu/access/Ownable2StepUpgradeable.sol';
import { OwnableUpgradeable } from '@ozu/access/OwnableUpgradeable.sol';
import { VotesUpgradeable } from '@ozu/governance/utils/VotesUpgradeable.sol';
import { UUPSUpgradeable } from '@ozu/proxy/utils/UUPSUpgradeable.sol';
import { ERC20Upgradeable } from '@ozu/token/ERC20/ERC20Upgradeable.sol';
import { ERC20PermitUpgradeable } from '@ozu/token/ERC20/extensions/ERC20PermitUpgradeable.sol';
import { ERC20VotesUpgradeable } from '@ozu/token/ERC20/extensions/ERC20VotesUpgradeable.sol';
import { NoncesUpgradeable } from '@ozu/utils/NoncesUpgradeable.sol';

import { SafeTransferLib } from '@solady/utils/SafeTransferLib.sol';

import { IGovMITO } from '../interfaces/hub/IGovMITO.sol';
import { ERC7201Utils } from '../lib/ERC7201Utils.sol';
import { LibQueue } from '../lib/LibQueue.sol';
import { StdError } from '../lib/StdError.sol';
import { SudoVotes } from '../lib/SudoVotes.sol';
import { Versioned } from '../lib/Versioned.sol';

contract GovMITO is
  IGovMITO,
  ERC20PermitUpgradeable,
  ERC20VotesUpgradeable,
  Ownable2StepUpgradeable,
  UUPSUpgradeable,
  SudoVotes,
  ReentrancyGuard,
  Versioned
{
  using ERC7201Utils for string;
  using SafeCast for uint256;
  using LibQueue for LibQueue.Trace208OffsetQueue;

  /// @custom:storage-location mitosis.storage.GovMITO
  struct GovMITOStorage {
    address minter;
    uint48 withdrawalPeriod;
    uint48 _reserved;
    mapping(address user => LibQueue.Trace208OffsetQueue) queue;
    mapping(address addr => bool) isModule;
    mapping(address sender => bool) isWhitelistedSender;
  }

  modifier onlyMinter() {
    require(_msgSender() == _getGovMITOStorage().minter, StdError.Unauthorized());
    _;
  }

  modifier onlyWhitelistedSender(address sender) {
    require(_getGovMITOStorage().isWhitelistedSender[sender], StdError.Unauthorized());
    _;
  }

  // =========================== NOTE: STORAGE DEFINITIONS =========================== //

  string private constant _NAMESPACE = 'mitosis.storage.GovMITO';
  bytes32 private immutable _slot = _NAMESPACE.storageSlot();

  function _getGovMITOStorage() private view returns (GovMITOStorage storage $) {
    bytes32 slot = _slot;
    // slither-disable-next-line assembly
    assembly {
      $.slot := slot
    }
  }

  // ============================ NOTE: INITIALIZATION FUNCTIONS ============================ //

  constructor() {
    _disableInitializers();
  }

  fallback() external payable {
    revert StdError.NotSupported();
  }

  receive() external payable {
    revert StdError.NotSupported();
  }

  function initialize(address owner_, uint256 withdrawalPeriod_) external initializer {
    require(withdrawalPeriod_ > 0, StdError.InvalidParameter('withdrawalPeriod'));

    // NOTE: not fixed yet. could be modified before launching.
    __ERC20_init('Mitosis Governance Token', 'gMITO');
    __ERC20Permit_init('Mitosis Governance Token');
    __ERC20Votes_init();

    __Ownable2Step_init();
    __Ownable_init(owner_);
    __UUPSUpgradeable_init();

    GovMITOStorage storage $ = _getGovMITOStorage();

    _setWithdrawalPeriod($, withdrawalPeriod_);
  }

  // ============================ NOTE: VIEW FUNCTIONS ============================ //

  function owner() public view override(OwnableUpgradeable, SudoVotes) returns (address) {
    return super.owner();
  }

  function minter() external view returns (address) {
    return _getGovMITOStorage().minter;
  }

  function isWhitelistedSender(address sender) external view returns (bool) {
    return _getGovMITOStorage().isWhitelistedSender[sender];
  }

  function isModule(address addr) external view returns (bool) {
    return _getGovMITOStorage().isModule[addr];
  }

  function withdrawalPeriod() external view returns (uint256) {
    return _getGovMITOStorage().withdrawalPeriod;
  }

  function withdrawalQueueOffset(address receiver) external view returns (uint256) {
    return _getGovMITOStorage().queue[receiver].offset();
  }

  function withdrawalQueueSize(address receiver) external view returns (uint256) {
    return _getGovMITOStorage().queue[receiver].size();
  }

  function withdrawalQueueRequestByIndex(address receiver, uint32 pos) external view returns (uint48, uint208) {
    return _getGovMITOStorage().queue[receiver].itemAt(pos);
  }

  function withdrawalQueueRequestByTime(address receiver, uint48 time) external view returns (uint48, uint208) {
    return _getGovMITOStorage().queue[receiver].recentItemAt(time);
  }

  function previewClaimWithdraw(address receiver) external view returns (uint256) {
    GovMITOStorage storage $ = _getGovMITOStorage();
    (, uint256 available) = $.queue[receiver].pending(clock() - $.withdrawalPeriod);
    return available;
  }

  // ============================ NOTE: MUTATIVE FUNCTIONS ============================ //

  function delegate(address delegatee) public pure override(IVotes, VotesUpgradeable, SudoVotes) {
    super.delegate(delegatee);
  }

  function delegateBySig(address delegatee, uint256 nonce, uint256 expiry, uint8 v, bytes32 r, bytes32 s)
    public
    pure
    override(IVotes, VotesUpgradeable, SudoVotes)
  {
    super.delegateBySig(delegatee, nonce, expiry, v, r, s);
  }

  function mint(address to) external payable onlyMinter {
    require(msg.value > 0, StdError.ZeroAmount());
    _mint(to, msg.value);
    emit Minted(to, msg.value);
  }

  function requestWithdraw(address receiver, uint256 amount) external returns (uint256) {
    require(receiver != address(0), StdError.ZeroAddress('receiver'));
    require(amount > 0, StdError.ZeroAmount());

    GovMITOStorage storage $ = _getGovMITOStorage();

    _burn(_msgSender(), amount);

    uint256 reqId = $.queue[receiver].append(clock(), amount.toUint208());

    emit WithdrawRequested(_msgSender(), receiver, amount, reqId);

    return reqId;
  }

  function claimWithdraw(address receiver) external nonReentrant returns (uint256) {
    GovMITOStorage storage $ = _getGovMITOStorage();

    LibQueue.Trace208OffsetQueue storage queue = $.queue[receiver];
    (uint32 reqIdFrom, uint32 reqIdTo) = queue.solveByKey(clock() - $.withdrawalPeriod);

    uint256 claimed;
    {
      uint256 fromValue = reqIdFrom == 0 ? 0 : queue.valueAt(reqIdFrom - 1);
      uint256 toValue = queue.valueAt(reqIdTo - 1);
      claimed = toValue - fromValue;
    }

    SafeTransferLib.safeTransferETH(receiver, claimed);

    emit WithdrawRequestClaimed(receiver, claimed, reqIdFrom, reqIdTo);

    return claimed;
  }

  // ============================ NOTE: OWNABLE FUNCTIONS ============================ //

  function _authorizeUpgrade(address) internal override onlyOwner { }

  function setMinter(address minter_) external onlyOwner {
    _setMinter(_getGovMITOStorage(), minter_);
  }

  function setModule(address addr, bool isModule_) external onlyOwner {
    require(addr != address(0), StdError.ZeroAddress('sender'));
    GovMITOStorage storage $ = _getGovMITOStorage();
    $.isModule[addr] = isModule_;
    emit ModuleSet(addr, isModule_);
  }

  function setWhitelistedSender(address sender, bool isWhitelisted) external onlyOwner {
    require(sender != address(0), StdError.ZeroAddress('sender'));
    _setWhitelistedSender(_getGovMITOStorage(), sender, isWhitelisted);
  }

  function setWithdrawalPeriod(uint256 withdrawalPeriod_) external onlyOwner {
    require(withdrawalPeriod_ > 0, StdError.InvalidParameter('withdrawalPeriod'));
    _setWithdrawalPeriod(_getGovMITOStorage(), withdrawalPeriod_);
  }

  // ============================ NOTE: IERC6372 OVERRIDES ============================ //

  function clock() public view override(IERC6372, VotesUpgradeable) returns (uint48) {
    return Time.timestamp();
  }

  function CLOCK_MODE() public view override(IERC6372, VotesUpgradeable) returns (string memory) {
    // Check that the clock was not modified
    require(clock() == Time.timestamp(), ERC6372InconsistentClock());
    return 'mode=timestamp';
  }

  // =========================== NOTE: ERC20 OVERRIDES =========================== //

  function approve(address spender, uint256 amount) public override(IERC20, ERC20Upgradeable) returns (bool) {
    GovMITOStorage storage $ = _getGovMITOStorage();

    require($.isModule[spender] || $.isWhitelistedSender[_msgSender()], StdError.Unauthorized());

    return super.approve(spender, amount);
  }

  function transfer(address to, uint256 amount) public override(IERC20, ERC20Upgradeable) returns (bool) {
    GovMITOStorage storage $ = _getGovMITOStorage();

    require($.isModule[_msgSender()] || $.isWhitelistedSender[_msgSender()], StdError.Unauthorized());

    return super.transfer(to, amount);
  }

  function transferFrom(address from, address to, uint256 amount)
    public
    override(IERC20, ERC20Upgradeable)
    returns (bool)
  {
    GovMITOStorage storage $ = _getGovMITOStorage();

    require(($.isModule[to] && _msgSender() == to) || $.isWhitelistedSender[from], StdError.Unauthorized());

    return super.transferFrom(from, to, amount);
  }

  function nonces(address owner_) public view override(ERC20PermitUpgradeable, NoncesUpgradeable) returns (uint256) {
    return super.nonces(owner_);
  }

  function _update(address from, address to, uint256 amount) internal override(ERC20Upgradeable, ERC20VotesUpgradeable) {
    super._update(from, to, amount);
  }

  // =========================== NOTE: INTERNAL FUNCTIONS =========================== //

  function _setMinter(GovMITOStorage storage $, address minter_) internal {
    $.minter = minter_;
    emit MinterSet(minter_);
  }

  function _setWhitelistedSender(GovMITOStorage storage $, address sender, bool isWhitelisted) internal {
    $.isWhitelistedSender[sender] = isWhitelisted;
    emit WhitelistedSenderSet(sender, isWhitelisted);
  }

  function _setWithdrawalPeriod(GovMITOStorage storage $, uint256 withdrawalPeriod_) internal {
    $.withdrawalPeriod = uint48(withdrawalPeriod_);
    emit WithdrawalPeriodSet(withdrawalPeriod_);
  }
}
