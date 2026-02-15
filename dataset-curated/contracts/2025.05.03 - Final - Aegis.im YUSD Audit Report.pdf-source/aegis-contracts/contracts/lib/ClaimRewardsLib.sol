// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

library ClaimRewardsLib {
  struct ClaimRequest {
    address claimer;
    bytes32[] ids;
    uint256[] amounts;
  }

  /// @dev ClaimRequest type hash
  bytes32 private constant CLAIM_REQUEST_TYPE = keccak256("ClaimRequest(address claimer,bytes32[] ids,uint256[] amounts)");

  error InvalidSignature();
  error InvalidClaimer();
  error InvalidParams();

  /// @dev Hashes claim request struct
  function hashClaimRequest(ClaimRequest calldata req, bytes32 domainSeparator) internal pure returns (bytes32) {
    return MessageHashUtils.toTypedDataHash(domainSeparator, keccak256(encodeClaimRequest(req)));
  }

  function encodeClaimRequest(ClaimRequest calldata req) internal pure returns (bytes memory) {
    return abi.encode(CLAIM_REQUEST_TYPE, req.claimer, keccak256(abi.encodePacked(req.ids)), keccak256(abi.encodePacked(req.amounts)));
  }

  /// @dev Verifies validity of signed claim request
  function verify(
    ClaimRequest calldata self,
    bytes32 domainSeparator,
    address expectedSigner,
    bytes calldata signature
  ) internal view returns (bytes32 claimRequestHash) {
    claimRequestHash = hashClaimRequest(self, domainSeparator);
    address signer = ECDSA.recover(claimRequestHash, signature);

    if (self.claimer != msg.sender) revert InvalidClaimer();
    if (signer != expectedSigner) revert InvalidSignature();
    if (self.ids.length != self.amounts.length) revert InvalidParams();
  }
}
