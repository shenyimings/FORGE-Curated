// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import { Ownable2Step } from "openzeppelin-contracts/access/Ownable2Step.sol";
import { AggregatorV2V3Interface } from "./AggregatorV3Interface.sol";

contract CapyfiAggregatorV3 is AggregatorV2V3Interface, Ownable2Step {
    
    struct RoundData {
        uint80 roundId;
        int256 answer;
        uint256 startedAt;
        uint256 updatedAt;
        uint80 answeredInRound;
    }

    uint8 private _decimals;
    string private _description;
    uint256 private _version;
    
    uint80 private nextRoundId;
    mapping(uint80 => RoundData) private rounds;
    RoundData private _latestRound;
    
    mapping(address => bool) public authorizedAddresses;

    // Additional events for access control
    event AuthorizedAddressAdded(address indexed addr);
    event AuthorizedAddressRemoved(address indexed addr);

    error UnauthorizedCaller(address caller);
    error InvalidAddress(address addr);
    error InvalidPrice(int256 price);
    error RoundNotFound(uint80 roundId);
    error NoRoundsAvailable();

    modifier onlyAuthorized() {
        if (msg.sender != owner() && !authorizedAddresses[msg.sender]) {
            revert UnauthorizedCaller(msg.sender);
        }
        _;
    }

    /**
     * @notice Deploy the contract with initial parameters
     * @param decimals_ Number of decimals for the price feed
     * @param description_ Description of what this aggregator represents
     * @param version_ Version of the aggregator
     * @param initialPrice Initial price to set (cannot be 0)
     */
    constructor(
        uint8 decimals_,
        string memory description_,
        uint256 version_,
        int256 initialPrice
    ) {
        if (initialPrice <= 0) revert InvalidPrice(initialPrice);
        _decimals = decimals_;
        _description = description_;
        _version = version_;
        nextRoundId = 1;
        
        _updateAnswer(initialPrice);
    }

    /**
     * @notice Add an authorized address that can update prices
     * @param addr Address to authorize
     */
    function addAuthorizedAddress(address addr) external onlyOwner {
        if (addr == address(0)) revert InvalidAddress(addr);
        authorizedAddresses[addr] = true;
        emit AuthorizedAddressAdded(addr);
    }

    /**
     * @notice Remove an authorized address
     * @param addr Address to remove authorization from
     */
    function removeAuthorizedAddress(address addr) external onlyOwner {
        if (!authorizedAddresses[addr]) revert InvalidAddress(addr);
        authorizedAddresses[addr] = false;
        emit AuthorizedAddressRemoved(addr);
    }

    /**
     * @notice Update the price (only owner or authorized addresses)
     * @param newAnswer New price to set
     */
    function updateAnswer(int256 newAnswer) external onlyAuthorized {
        if (newAnswer <= 0) revert InvalidPrice(newAnswer);
        _updateAnswer(newAnswer);
    }

    /**
     * @notice Internal function to update the answer and create a new round
     * @param newAnswer New price to set
     */
    function _updateAnswer(int256 newAnswer) internal {
        uint256 timestamp = block.timestamp;
        
        RoundData memory newRound = RoundData({
            roundId: nextRoundId,
            answer: newAnswer,
            startedAt: timestamp,
            updatedAt: timestamp,
            answeredInRound: nextRoundId
        });
        
        rounds[nextRoundId] = newRound;
        _latestRound = newRound;
        
        emit AnswerUpdated(newAnswer, nextRoundId, timestamp);
        emit NewRound(nextRoundId, msg.sender, timestamp);
        
        nextRoundId++;
    }

    // AggregatorInterface (V2) implementation
    
    /**
     * @notice Get the latest answer without round data
     */
    function latestAnswer() external view override returns (int256) {
        if (_latestRound.roundId == 0) revert NoRoundsAvailable();
        return _latestRound.answer;
    }

    /**
     * @notice Get the timestamp of the latest update
     */
    function latestTimestamp() external view override returns (uint256) {
        if (_latestRound.roundId == 0) revert NoRoundsAvailable();
        return _latestRound.updatedAt;
    }

    /**
     * @notice Get the latest round ID
     */
    function latestRound() external view override returns (uint256) {
        return nextRoundId - 1; // Return current round ID
    }

    /**
     * @notice Get the answer for a specific round
     * @param roundId The round ID to get the answer for
     */
    function getAnswer(uint256 roundId) external view override returns (int256) {
        if (roundId == 0 || roundId >= nextRoundId) revert RoundNotFound(uint80(roundId));
        return rounds[uint80(roundId)].answer;
    }

    /**
     * @notice Get the timestamp for a specific round
     * @param roundId The round ID to get the timestamp for
     */
    function getTimestamp(uint256 roundId) external view override returns (uint256) {
        if (roundId == 0 || roundId >= nextRoundId) revert RoundNotFound(uint80(roundId));
        return rounds[uint80(roundId)].updatedAt;
    }

    // AggregatorV3Interface implementation

    /**
     * @notice Returns the number of decimals
     */
    function decimals() external view override returns (uint8) {
        return _decimals;
    }

    /**
     * @notice Returns the description
     */
    function description() external view override returns (string memory) {
        return _description;
    }

    /**
     * @notice Returns the version
     */
    function version() external view override returns (uint256) {
        return _version;
    }

    /**
     * @notice Get data from a specific round
     * @param roundId The round ID to retrieve data for
     */
    function getRoundData(uint80 roundId) 
        external 
        view 
        override 
        returns (
            uint80,
            int256,
            uint256,
            uint256,
            uint80
        ) 
    {
        if (roundId == 0 || roundId >= nextRoundId) revert RoundNotFound(roundId);
        
        RoundData memory round = rounds[roundId];
        return (
            round.roundId,
            round.answer,
            round.startedAt,
            round.updatedAt,
            round.answeredInRound
        );
    }

    /**
     * @notice Get data from the latest round
     */
    function latestRoundData()
        external
        view
        override
        returns (
            uint80,
            int256,
            uint256,
            uint256,
            uint80
        )
    {
        if (_latestRound.roundId == 0) revert NoRoundsAvailable();
        
        return (
            _latestRound.roundId,
            _latestRound.answer,
            _latestRound.startedAt,
            _latestRound.updatedAt,
            _latestRound.answeredInRound
        );
    }
} 