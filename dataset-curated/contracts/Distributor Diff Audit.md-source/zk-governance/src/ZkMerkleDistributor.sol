// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {BitMaps} from "@openzeppelin/contracts/utils/structs/BitMaps.sol";
import {IMintableAndDelegatable} from "src/interfaces/IMintableAndDelegatable.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {Nonces} from "src/lib/Nonces.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

/// @title ZkMerkleDistributor
/// @author [ScopeLift](https://scopelift.co)
/// @notice A contract that allows a user to claim a token distribution against a Merkle tree root.
/// @custom:security-contact security@zksync.io
contract ZkMerkleDistributor is EIP712, Nonces {
  using BitMaps for BitMaps.BitMap;

  /// @dev A struct of delegate information used for signature based delegateOnBehalf.
  struct DelegateInfo {
    address delegatee;
    uint256 expiry;
    bytes signature;
  }

  /// @dev A struct of claim information used for signature based claiming.
  struct ClaimSignatureInfo {
    address claimant;
    uint256 expiry;
    bytes signature;
  }

  /// @notice Type hash of the data that makes up the claim request.
  bytes32 public constant ZK_CLAIM_TYPEHASH =
    keccak256("Claim(uint256 index,address claimant,uint256 amount,uint256 expiry,uint256 nonce)");

  /// @notice Type hash of the data that makes up the claim and delegate request.
  bytes32 public constant ZK_CLAIM_AND_DELEGATE_TYPEHASH = keccak256(
    "ClaimAndDelegate(uint256 index,address claimant,uint256 amount,address delegatee,uint256 expiry,uint256 nonce)"
  );

  /// @notice The address of the admin of the MerkleDistributor.
  address public immutable ADMIN;

  /// @notice The token contract for the tokens to be claimed / distributed.
  IMintableAndDelegatable public immutable TOKEN;

  /// @notice The Merkle root for the distribution.
  bytes32 public immutable MERKLE_ROOT;

  /// @notice The maximum number of tokens that may be claimed using the MerkleDistributor.
  uint256 public immutable MAXIMUM_TOTAL_CLAIMABLE;

  /// @notice The start of the period when claims may be made.
  uint256 public immutable WINDOW_START;

  /// @notice The end of the period when claims may be made.
  uint256 public immutable WINDOW_END;

  /// @notice This is a packed array of booleans for tracking completion of claims.
  BitMaps.BitMap internal claimedBitMap;

  /// @notice This is the total amount of tokens that have been claimed so far.
  uint256 public totalClaimed;

  /// @notice Event that is emitted whenever a call to claim succeeds.
  event Claimed(uint256 index, address account, uint256 amount);

  /// @notice Error thrown when the claim has already been claimed.
  error ZkMerkleDistributor__AlreadyClaimed();

  /// @notice Error thrown or when the claim window is not open and should be.
  error ZkMerkleDistributor__ClaimWindowNotOpen();

  /// @notice Error thrown when the claim window is open and should not be.
  error ZkMerkleDistributor__ClaimWindowNotYetClosed();

  /// @notice Error for when the claim has an invalid proof.
  error ZkMerkleDistributor__InvalidProof();

  /// @notice Error for when the total claimed exceeds the total amount claimed.
  error ZkMerkleDistributor__ClaimAmountExceedsMaximum();

  /// @notice Error for when the sweep has already been done.
  error ZkMerkleDistributor__SweepAlreadyDone();

  /// @notice Error for when the caller is not the admin.
  error ZkMerkleDistributor__Unauthorized(address account);

  /// @notice Thrown if a caller supplies an invalid signature to a method that requires one.
  error ZkMerkleDistributor__InvalidSignature();

  /// @notice Thrown if the caller submits an expired signature
  error ZkMerkleDistributor__ExpiredSignature();

  /// @notice Constructor for a new MerkleDistributor contract
  /// @param _admin The address that is allowed to execute "sweepUnclaimed"
  /// @param _token The contract of the token distributed by the Merkle Distributor.
  /// @param _merkleRoot The Merkle root for the distribution.
  /// @param _maximumTotalClaimable The maximum number of tokens that may be claimed by the MerkleDistributor.
  /// @param _windowStart The start of the time window during which claims may be made.
  /// @param _windowEnd The end of the time window during which claims may be made.
  constructor(
    address _admin,
    IMintableAndDelegatable _token,
    bytes32 _merkleRoot,
    uint256 _maximumTotalClaimable,
    uint256 _windowStart,
    uint256 _windowEnd
  ) EIP712("ZkMerkleDistributor", "1") {
    ADMIN = _admin;
    TOKEN = _token;
    MERKLE_ROOT = _merkleRoot;
    MAXIMUM_TOTAL_CLAIMABLE = _maximumTotalClaimable;
    WINDOW_START = _windowStart;
    WINDOW_END = _windowEnd;
  }

  /// @notice Returns true if the index has been claimed.
  /// @param _index The index of the claim.
  /// @return Whether a claim has been claimed.
  function isClaimed(uint256 _index) public view returns (bool) {
    return claimedBitMap.get(_index);
  }

  /// @notice Claims the tokens for a caller, given the index, amount, and merkle proof.
  /// @param _index The index of the claim.
  /// @param _amount The quantity of tokens, in raw decimals, that will be created.
  /// @param _merkleProof The Merkle proof for the claim.
  function claim(uint256 _index, uint256 _amount, bytes32[] calldata _merkleProof) external {
    _claim(_index, msg.sender, _amount, _merkleProof);
  }

  /// @notice Claims on behalf of another account, using the ERC-712 or ERC-1271 signature standard.
  /// @dev This method makes use of the _signature parameter to verify the claim on behalf of the claimer.
  /// @param _index The index of the claim.
  /// @param _amount The quantity of tokens, in raw decimals, that will be created.
  /// @param _merkleProof The Merkle proof for the claim.
  /// @param _claimSignatureInfo Signature information provided by the claimer.
  function claimOnBehalf(
    uint256 _index,
    uint256 _amount,
    bytes32[] calldata _merkleProof,
    ClaimSignatureInfo calldata _claimSignatureInfo
  ) external {
    bytes32 _dataHash;

    if (_claimSignatureInfo.expiry <= block.timestamp) {
      revert ZkMerkleDistributor__ExpiredSignature();
    }
    unchecked {
      _dataHash = ECDSA.toTypedDataHash(
        _domainSeparatorV4(),
        keccak256(
          abi.encode(
            ZK_CLAIM_TYPEHASH,
            _index,
            _claimSignatureInfo.claimant,
            _amount,
            _claimSignatureInfo.expiry,
            _useNonce(_claimSignatureInfo.claimant)
          )
        )
      );
    }
    _revertIfSignatureIsNotValidNow(_claimSignatureInfo.claimant, _dataHash, _claimSignatureInfo.signature);
    _claim(_index, _claimSignatureInfo.claimant, _amount, _merkleProof);
  }

  /// @notice Claims the tokens for a claimant, given a claimant address, an index, an amount, and a merkle proof.
  /// @dev This method makes use of signature parameters to delegate the claimant's voting power to another address,
  /// and therefore cannot be called by smart contract accounts.
  /// @param _index The index of the claim.
  /// @param _amount The quantity of tokens, in raw decimals, that will be created.
  /// @param _merkleProof The Merkle proof for the claim.
  /// @param _delegateInfo The address (and signature info) for where the claimer's voting power will be delegated.
  function claimAndDelegate(
    uint256 _index,
    uint256 _amount,
    bytes32[] calldata _merkleProof,
    DelegateInfo memory _delegateInfo
  ) external virtual {
    _claim(_index, msg.sender, _amount, _merkleProof);

    // Use delegateOnBehalf to delegate on behalf of the claimer.
    // Catch delegateOnBehalf reverts caused by a front-run delegateOnBehalf so entire claim doesn't revert.
    try TOKEN.delegateOnBehalf(msg.sender, _delegateInfo.delegatee, _delegateInfo.expiry, _delegateInfo.signature) {}
      catch (bytes memory) {}
  }

  /// @notice Claims on behalf of another account, using the ERC-712 or ERC-1271 signature standard.
  /// @dev This method makes use of the _signature parameter to verify the claim on behalf of the claimer, and
  /// separate signature parameters to delegate the claimer's voting power to another address.
  /// @param _index The index of the claim.
  /// @param _amount The quantity of tokens, in raw decimals, that will be created.
  /// @param _merkleProof The Merkle proof for the claim.
  /// @param _claimSignatureInfo Signature information provided by the claimer.
  /// @param _delegateInfo The address (and signature info) for where claimer's voting power will be delegated.
  /// In this function the delegateInfo expiry will be ignored.
  function claimAndDelegateOnBehalf(
    uint256 _index,
    uint256 _amount,
    bytes32[] calldata _merkleProof,
    ClaimSignatureInfo calldata _claimSignatureInfo,
    DelegateInfo memory _delegateInfo
  ) external {
    bytes32 _dataHash;

    if (_claimSignatureInfo.expiry <= block.timestamp) {
      revert ZkMerkleDistributor__ExpiredSignature();
    }

    unchecked {
      _dataHash = keccak256(
        abi.encodePacked(
          "\x19\x01",
          _domainSeparatorV4(),
          keccak256(
            abi.encode(
              ZK_CLAIM_AND_DELEGATE_TYPEHASH,
              _index,
              _claimSignatureInfo.claimant,
              _amount,
              _delegateInfo.delegatee,
              _claimSignatureInfo.expiry,
              _useNonce(_claimSignatureInfo.claimant)
            )
          )
        )
      );
    }
    _revertIfSignatureIsNotValidNow(_claimSignatureInfo.claimant, _dataHash, _claimSignatureInfo.signature);
    _claim(_index, _claimSignatureInfo.claimant, _amount, _merkleProof);

    // Use delegateOnBehalf to delegate on behalf of the claimer.
    // Catch delegateOnBehalf reverts caused by a front-run delegateOnBehalf so entire claim doesn't revert.
    try TOKEN.delegateOnBehalf(
      _claimSignatureInfo.claimant, _delegateInfo.delegatee, _delegateInfo.expiry, _delegateInfo.signature
    ) {} catch (bytes memory) {}
  }

  /// @notice Allows the admin to sweep unclaimed tokens to a given address.
  /// @param _unclaimedReceiver The address that will receive the unclaimed tokens.
  function sweepUnclaimed(address _unclaimedReceiver) external {
    _revertIfClaimWindowHasNotClosed();
    _revertIfUnauthorized();
    _revertIfAlreadySwept();
    TOKEN.mint(_unclaimedReceiver, MAXIMUM_TOTAL_CLAIMABLE - totalClaimed);
    totalClaimed = MAXIMUM_TOTAL_CLAIMABLE;
  }

  /// @notice Claims the tokens for a given index, account, amount, and merkle proof.
  /// @param _index The index of the claim.
  /// @param _claimant The address that will receive the new tokens.
  /// @param _amount The quantity of tokens, in raw decimals, that will be created.
  /// @param _merkleProof The Merkle proof for the claim.
  /// @dev Internal method for claiming tokens, called by 'claim' and 'claimOnBehalf'.
  function _claim(uint256 _index, address _claimant, uint256 _amount, bytes32[] calldata _merkleProof) internal {
    _revertIfClaimWindowNotOpen();
    _revertIfClaimAmountExceedsMaximum(_amount);
    _revertIfAlreadyClaimed(_index);

    // Verify the merkle proof.
    bytes32 node = keccak256(abi.encodePacked(_index, _claimant, _amount));
    if (!MerkleProof.verifyCalldata(_merkleProof, MERKLE_ROOT, node)) {
      revert ZkMerkleDistributor__InvalidProof();
    }

    // Bump the total amount claimed, mark it claimed, send the token, and emit the event.
    totalClaimed += _amount;
    _setClaimed(_index);
    TOKEN.mint(_claimant, _amount);
    emit Claimed(_index, _claimant, _amount);
  }

  /// @notice Allows a msg.sender to increment their nonce and invalidate any of their pending signatures.
  function invalidateNonce() external {
    _useNonce(msg.sender);
  }

  /// @dev Returns the domain separator used in the encoding of the signature for {permit}, as defined by {EIP712}.
  /// @return The domain seperator.
  function DOMAIN_SEPARATOR() external view returns (bytes32) {
    return _domainSeparatorV4();
  }

  /// @notice Reverts if the caller is not the admin.
  function _revertIfUnauthorized() internal view {
    if (msg.sender != ADMIN) {
      revert ZkMerkleDistributor__Unauthorized(msg.sender);
    }
  }

  /// @notice Updates the tracking data to mark the claim has been done.
  /// @param _index The index of the claim.
  function _setClaimed(uint256 _index) private {
    claimedBitMap.set(_index);
  }

  /// @notice Reverts if already claimed.
  /// @param _index The index of the claim.
  function _revertIfAlreadyClaimed(uint256 _index) internal view {
    if (isClaimed(_index)) {
      revert ZkMerkleDistributor__AlreadyClaimed();
    }
  }

  /// @notice Reverts if the claim window is not open.
  function _revertIfClaimWindowNotOpen() internal view {
    if (block.timestamp < WINDOW_START || block.timestamp >= WINDOW_END) {
      revert ZkMerkleDistributor__ClaimWindowNotOpen();
    }
  }

  /// @notice Reverts if the claim window is open.
  function _revertIfClaimWindowHasNotClosed() internal view {
    if (block.timestamp < WINDOW_END) {
      revert ZkMerkleDistributor__ClaimWindowNotYetClosed();
    }
  }

  /// @notice Reverts if the claim amount exceeds the maximum.
  /// @param _amount The quantity of tokens, in raw decimals, that will be created.
  function _revertIfClaimAmountExceedsMaximum(uint256 _amount) internal view {
    if (_amount + totalClaimed > MAXIMUM_TOTAL_CLAIMABLE) {
      revert ZkMerkleDistributor__ClaimAmountExceedsMaximum();
    }
  }

  /// @notice Reverts if the sweep has already been done.
  function _revertIfAlreadySwept() internal view {
    if (totalClaimed >= MAXIMUM_TOTAL_CLAIMABLE) {
      revert ZkMerkleDistributor__SweepAlreadyDone();
    }
  }

  /// @notice Reverts if the signature is not valid
  /// @param _signer Address of the signer.
  /// @param _hash Hash of the message.
  /// @param _signature Signature to validate.
  function _revertIfSignatureIsNotValidNow(address _signer, bytes32 _hash, bytes memory _signature) internal view {
    bool _isValid = SignatureChecker.isValidSignatureNow(_signer, _hash, _signature);
    if (!_isValid) {
      revert ZkMerkleDistributor__InvalidSignature();
    }
  }
}
