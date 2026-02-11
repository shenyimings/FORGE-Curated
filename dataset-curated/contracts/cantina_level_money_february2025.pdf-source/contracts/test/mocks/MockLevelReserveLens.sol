// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19;

contract MockLevelReserveLens {
    uint256 public _mockPrice;
    bool public shouldRevert;
    bool public shouldDecimalsRevert;

    constructor() {
        _mockPrice = 1e18;
        shouldRevert = false;
        shouldDecimalsRevert = false;
    }

    function setMockPrice(uint256 price) external {
        _mockPrice = price;
    }

    function setShouldRevert(bool _shouldRevert) external {
        shouldRevert = _shouldRevert;
    }

    function setShouldDecimalsRevert(bool _shouldDecimalsRevert) external {
        shouldDecimalsRevert = _shouldDecimalsRevert;
    }

    function getReservePrice() public view returns (uint256) {
        require(!shouldRevert, "MockLens: Forced revert");

        return _mockPrice;
    }

    function getReservePriceDecimals() public view returns (uint8) {
        require(!shouldDecimalsRevert, "MockLens: Forced revert");

        return 18;
    }
}
