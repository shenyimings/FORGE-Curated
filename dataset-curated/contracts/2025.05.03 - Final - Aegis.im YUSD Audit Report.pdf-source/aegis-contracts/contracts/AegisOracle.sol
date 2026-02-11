// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract AegisOracle is Ownable2Step {
  struct YUSDUSDPriceData {
    int256 price;
    uint32 timestamp;
  }

  YUSDUSDPriceData private _priceData;

  mapping(address => bool) private _operators;

  event UpdateYUSDPrice(int256 price, uint32 timestamp);
  event SetOperator(address indexed operator, bool allowed);

  error ZeroAddress();
  error AccessForbidden();

  modifier onlyOperator() {
    if (!_operators[_msgSender()]) {
      revert AccessForbidden();
    }
    _;
  }

  constructor(address[] memory _ops, address _initialOwner) Ownable(_initialOwner) {
    if (_initialOwner == address(0)) revert ZeroAddress();

    for (uint256 i = 0; i < _ops.length; i++) {
      _setOperator(_ops[i], true);
    }
  }

  function decimals() public pure returns (uint8) {
    return 8;
  }

  /// @dev Returns current YUSD/USD price
  function yusdUSDPrice() public view returns (int256) {
    return _priceData.price;
  }

  /// @dev Returns timestamp of last price update
  function lastUpdateTimestamp() public view returns (uint32) {
    return _priceData.timestamp;
  }

  /**
   * @dev Updates YUSD/USD price.
   * @dev Price should have 8 decimals
   */
  function updateYUSDPrice(int256 price) external onlyOperator {
    _priceData.price = price;
    _priceData.timestamp = uint32(block.timestamp);
    emit UpdateYUSDPrice(_priceData.price, _priceData.timestamp);
  }

  /// @dev Adds/removes operator
  function setOperator(address operator, bool allowed) external onlyOwner {
    _setOperator(operator, allowed);
  }

  function _setOperator(address operator, bool allowed) internal {
    _operators[operator] = allowed;
    emit SetOperator(operator, allowed);
  }
}
