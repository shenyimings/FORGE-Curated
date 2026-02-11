// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

contract BaseDecoderAndSanitizer {
  error BaseDecoderAndSanitizer__FunctionSelectorNotSupported();

  //============================== FALLBACK ===============================
  /**
   * @notice The purpose of this function is to revert with a known error,
   *         so that during merkle tree creation we can verify that a
   *         leafs decoder and sanitizer implements the required function
   *         selector.
   */
  fallback() external {
    revert BaseDecoderAndSanitizer__FunctionSelectorNotSupported();
  }
}
