// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import "../common/IErrors.sol";
import {IFactory} from "../factory/IFactory.sol";
import {IAllowList} from "../allowList/IAllowList.sol";

/**
 * @title Pool Factory
 * @dev creates the pools in an automated and permissioned fashion
 * @author  @oscarsernarosero @mpetersoCode55 @cirsteve
 */

abstract contract FactoryBase is Ownable2Step, IFactory {
    string public constant VERSION = "v0.2.0";
    uint16 public constant MAX_PROTOCOL_FEE = 20;

    address yTokenAllowList;
    address deployerAllowList;
    address public protocolFeeCollector;
    address public proposedProtocolFeeCollector;
    uint16 public protocolFee;

    constructor() Ownable(_msgSender()) {}

    modifier onlyAllowedDeployers() {
        if (!IAllowList(deployerAllowList).isAllowed(_msgSender())) revert NotAnAllowedDeployer();
        _;
    }

    modifier onlyAllowedYTokens(address _yToken) {
        if (!IAllowList(yTokenAllowList).isAllowed(_yToken)) revert YTokenNotAllowed();
        _;
    }

    modifier onlyProposedProtocolFeeCollector() {
        if (_msgSender() != proposedProtocolFeeCollector) revert NotProposedProtocolFeeCollector();
        _;
    }

    /**
     * @dev sets the y token allow list
     * @param _address of the allow list contract
     */
    function setYTokenAllowList(address _address) external onlyOwner {
        if (_address == address(0)) revert ZeroAddress();
        yTokenAllowList = _address;
        emit SetYTokenAllowList(_address);
    }

    /**
     * @dev gets the y token allow list
     * @return _address of the current allow list contract
     */
    function getYTokenAllowList() external view returns (address) {
        return yTokenAllowList;
    }

    /**
     * @dev sets the deployer allow list
     * @param _address of the allow list contract
     * @notice Only the owner can set the deployer allow list
     */
    function setDeployerAllowList(address _address) external onlyOwner {
        if (_address == address(0)) revert ZeroAddress();
        deployerAllowList = _address;
        emit SetDeployerAllowList(_address);
    }

    /**
     * @dev gets the deployer allow list
     * @return _address of the current allow list contract
     */
    function getDeployerAllowList() external view returns (address) {
        return deployerAllowList;
    }

    /**
     * @dev This is the function to update the protocol fees per trade.
     * @param _protocolFee percentage of the transaction that will get collected as fees (in percentage basis points:
     * 10000 -> 100.00%; 500 -> 5.00%; 1 -> 0.01%)
     * @notice Only the owner can set the protocol fee
     */
    function setProtocolFee(uint16 _protocolFee) public onlyOwner {
        if (_protocolFee > MAX_PROTOCOL_FEE) revert ProtocolFeeAboveMax({proposedFee: _protocolFee, maxFee: MAX_PROTOCOL_FEE});
        protocolFee = _protocolFee;
        emit ProtocolFeeSet(_protocolFee);
    }

    /**
     * @dev function to propose a new protocol fee collector
     * @param _protocolFeeCollector the new fee collector
     * @notice that only the current fee collector address can call this function
     */
    function proposeProtocolFeeCollector(address _protocolFeeCollector) external onlyOwner {
        // slither-disable-start missing-zero-check // unnecessary
        proposedProtocolFeeCollector = _protocolFeeCollector;
        // slither-disable-end missing-zero-check
        emit ProtocolFeeCollectorProposed(_protocolFeeCollector);
    }

    /**
     * @dev function to confirm a new protocol fee collector
     * @notice that only the already proposed fee collector can call this function
     */
    function confirmProtocolFeeCollector() external onlyProposedProtocolFeeCollector {
        delete proposedProtocolFeeCollector;
        protocolFeeCollector = _msgSender();
        emit ProtocolFeeCollectorConfirmed(_msgSender());
    }
}
