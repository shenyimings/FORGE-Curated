// SPDX-License-Identifier: BSL-1.1
pragma solidity =0.8.28;

contract OracleMock {
    uint256 public price;
    uint256 public underlyingPrice;
    address public admin;
    mapping(address => uint8) public registeredDecimals;

    error OracleMock_NotAuthorized();

    constructor(address _admin) {
        admin = _admin;
    }

    function setDecimals(address token, uint8 dec) external {
        require(msg.sender == admin, OracleMock_NotAuthorized());
        registeredDecimals[token] = dec;
    }

    function decimals() external pure returns (uint8) {
        return 8;
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        roundId = 1;
        answer = int256(price);
        startedAt = block.timestamp;
        updatedAt = block.timestamp;
        answeredInRound = 1;
    }

    function latestAnswer() external view returns (int256) {
        return int256(price);
    }

    function latestTimestamp() external view returns (uint256) {
        return block.timestamp;
    }

    function setPrice(uint256 _price) external {
        require(msg.sender == admin, OracleMock_NotAuthorized());
        price = _price;
    }

    function setUnderlyingPrice(uint256 _price) external {
        require(msg.sender == admin, OracleMock_NotAuthorized());
        underlyingPrice = _price;
    }

    function getPrice(address) external view returns (uint256) {
        return price;
    }

    function getUnderlyingPrice(address) external view returns (uint256) {
        return underlyingPrice;
    }
}
