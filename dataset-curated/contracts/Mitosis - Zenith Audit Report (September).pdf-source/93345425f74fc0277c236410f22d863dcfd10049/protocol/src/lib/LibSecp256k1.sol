// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { EllipticCurve } from '@elliptic-curve-solidity/contracts/EllipticCurve.sol';

import { StdError } from './StdError.sol';

library LibSecp256k1 {
  uint256 constant AA = 0;
  uint256 constant BB = 7;
  uint256 constant PP = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F;

  /**
   * @notice Verifies that the given key is a compressed 33-byte secp256k1 public key on the curve.
   * @param cmpPubkey The key to be verified if it is a valid compressed 33-byte public key
   */
  function verifyCmpPubkey(bytes memory cmpPubkey) internal pure {
    verifyUncmpPubkey(uncompressPubkey(cmpPubkey));
  }

  /**
   * @notice Verifies that the given key is a uncompressed 65-byte secp256k1 public key on the curve.
   * @param uncmpPubkey The key to be verified if it is a valid uncompressed 65-byte public key
   */
  function verifyUncmpPubkey(bytes memory uncmpPubkey) internal pure {
    require(uncmpPubkey.length == 65, StdError.InvalidParameter('uncmpPubkey.length'));
    require(uncmpPubkey[0] == 0x04, StdError.InvalidParameter('uncmpPubkey[0]'));

    uint256 x;
    uint256 y;
    assembly {
      x := mload(add(uncmpPubkey, 0x21))
      y := mload(add(uncmpPubkey, 0x41))
    }

    bool isOnCurve = EllipticCurve.isOnCurve(x, y, AA, BB, PP);
    require(isOnCurve, StdError.InvalidParameter('uncmpPubkey: not on curve'));
  }

  /**
   * @notice Verifies that the given public key is a compressed 33-byte secp256k1 public key on the curve and corresponds to the expected address.
   * @param cmpPubkey The key to be verified if it is a valid compressed 33-byte public key
   * @param expectedAddress The expected address to be compared with the derived address from the compressed public key
   */
  function verifyCmpPubkeyWithAddress(bytes memory cmpPubkey, address expectedAddress) internal pure {
    bytes memory uncmpPubkey = uncompressPubkey(cmpPubkey);
    verifyUncmpPubkey(uncmpPubkey);
    require(
      deriveAddressFromUncmpPubkey(uncmpPubkey) == expectedAddress,
      StdError.InvalidParameter('uncmpPubkey: the derived address is not expected')
    );
  }

  /**
   * @notice Verifies that the given public key is a uncompressed 65-byte secp256k1 public key on the curve and corresponds to the expected address.
   * @param uncmpPubkey The key to be verified if it is a valid uncompressed 65-byte public key
   * @param expectedAddress The expected address to be compared with the derived address from the uncompressed public key
   */
  function verifyUncmpPubkeyWithAddress(bytes memory uncmpPubkey, address expectedAddress) internal pure {
    verifyUncmpPubkey(uncmpPubkey);
    require(
      deriveAddressFromUncmpPubkey(uncmpPubkey) == expectedAddress,
      StdError.InvalidParameter('uncmpPubkey: the derived address is not expected')
    );
  }

  /**
   * @notice Uncompresses a compressed 33-byte secp256k1 public key.
   * @param cmpPubkey The compressed 33-byte public key
   * @return uncmpPubkey The uncompressed 65-byte public key
   */
  function uncompressPubkey(bytes memory cmpPubkey) internal pure returns (bytes memory uncmpPubkey) {
    require(cmpPubkey.length == 33, StdError.InvalidParameter('cmpPubKey.length'));
    require(cmpPubkey[0] == 0x02 || cmpPubkey[0] == 0x03, StdError.InvalidParameter('cmpPubKey[0]'));

    uint8 prefix = uint8(cmpPubkey[0]);
    uint256 x;
    assembly {
      x := mload(add(cmpPubkey, 0x21))
    }
    uint256 y = EllipticCurve.deriveY(prefix, x, AA, BB, PP);

    uncmpPubkey = new bytes(65);
    uncmpPubkey[0] = 0x04;
    assembly {
      mstore(add(uncmpPubkey, 0x21), x)
      mstore(add(uncmpPubkey, 0x41), y)
    }
    return uncmpPubkey;
  }

  /**
   * @notice Compresses an uncompressed 65-byte secp256k1 public key.
   * @param uncmpPubkey The uncompressed 65-byte public key
   * @return cmpPubkey The compressed 33-byte public key
   */
  function compressPubkey(bytes memory uncmpPubkey) internal pure returns (bytes memory cmpPubkey) {
    require(uncmpPubkey.length == 65, StdError.InvalidParameter('uncmpPubkey.length'));
    require(uncmpPubkey[0] == 0x04, StdError.InvalidParameter('uncmpPubkey[0]'));

    uint256 x;
    uint256 y;
    assembly {
      x := mload(add(uncmpPubkey, 0x21))
      y := mload(add(uncmpPubkey, 0x41))
    }

    cmpPubkey = new bytes(33);
    cmpPubkey[0] = bytes1(uint8(y % 2 == 0 ? 0x02 : 0x03));
    assembly {
      mstore(add(cmpPubkey, 0x21), x)
    }
    return cmpPubkey;
  }

  /**
   * @notice Derives an EVM address from an uncompressed 65-byte secp256k1 public key.
   * @dev It assumes that the given public key is a valid uncompressed 65-byte secp256k1 public key.
   * @param uncmpPubkey The uncompressed 65-byte public key
   */
  function deriveAddressFromUncmpPubkey(bytes memory uncmpPubkey) internal pure returns (address) {
    bytes memory noPrefix = new bytes(64);

    assembly {
      // Get the source pointer (uncmpPubkey data start: skip prefix 0x04 and length)
      let src := add(uncmpPubkey, 0x21)
      // Get the destination pointer (noPrefix data start: skip length)
      let dest := add(noPrefix, 0x20)

      // Copy the first 32 bytes
      mstore(dest, mload(src))
      // Copy the next 32 bytes (offset by 32)
      mstore(add(dest, 0x20), mload(add(src, 0x20)))
    }

    return address(uint160(uint256(keccak256(noPrefix))));
  }

  /**
   * @notice Derives an EVM address from a compressed 33-byte secp256k1 public key.
   * @dev It assumes that the given public key is a valid compressed 33-byte secp256k1 public key.
   * @param cmpPubkey The compressed 33-byte public key
   */
  function deriveAddressFromCmpPubkey(bytes memory cmpPubkey) internal pure returns (address) {
    return deriveAddressFromUncmpPubkey(uncompressPubkey(cmpPubkey));
  }
}
