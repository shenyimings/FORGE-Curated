// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

library OrderLib {
  enum OrderType {
    MINT,
    REDEEM,
    DEPOSIT_INCOME
  }

  struct Order {
    OrderType orderType;
    address userWallet;
    address collateralAsset;
    uint256 collateralAmount;
    uint256 yusdAmount;
    uint256 slippageAdjustedAmount;
    uint256 expiry;
    uint256 nonce;
    bytes additionalData;
  }

  /// @dev Order type hash
  bytes32 private constant ORDER_TYPE =
    keccak256(
      "Order(uint8 orderType,address userWallet,address collateralAsset,uint256 collateralAmount,uint256 yusdAmount,uint256 slippageAdjustedAmount,uint256 expiry,uint256 nonce,bytes additionalData)"
    );

  error InvalidSignature();
  error InvalidAmount();
  error InvalidSender();
  error SignatureExpired();

  /// @dev Hashes order struct
  function hashOrder(Order calldata order, bytes32 domainSeparator) internal pure returns (bytes32) {
    return MessageHashUtils.toTypedDataHash(domainSeparator, keccak256(encodeOrder(order)));
  }

  function encodeOrder(Order calldata order) internal pure returns (bytes memory) {
    return
      abi.encode(
        ORDER_TYPE,
        order.orderType,
        order.userWallet,
        order.collateralAsset,
        order.collateralAmount,
        order.yusdAmount,
        order.slippageAdjustedAmount,
        order.expiry,
        order.nonce,
        keccak256(order.additionalData)
      );
  }

  /// @dev Verifies validity of signed order
  function verify(
    Order calldata self,
    bytes32 domainSeparator,
    address expectedSigner,
    bytes calldata signature
  ) internal view returns (bytes32 orderHash) {
    orderHash = hashOrder(self, domainSeparator);
    address signer = ECDSA.recover(orderHash, signature);

    if (self.userWallet != msg.sender) revert InvalidSender();
    if (signer != expectedSigner) revert InvalidSignature();
    if (self.collateralAmount == 0) revert InvalidAmount();
    if (self.yusdAmount == 0) revert InvalidAmount();
    if (block.timestamp > self.expiry) revert SignatureExpired();
  }
}
