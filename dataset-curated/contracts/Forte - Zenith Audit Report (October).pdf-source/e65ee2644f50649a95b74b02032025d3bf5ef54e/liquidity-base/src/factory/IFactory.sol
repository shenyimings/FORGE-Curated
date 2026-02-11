// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {IFactoryEvents} from "../common/IEvents.sol";

/**
 * @title Pool Factory Interface
 * @author  @oscarsernarosero @mpetersoCode55 @cirsteve
 * @dev function signatures of a Pool Factory
 */

interface IFactory is IFactoryEvents {
    /**
     * @dev version of the pool factory
     * @return the version of the pool factory
     */
    function VERSION() external view returns (string memory);

    /**
     * @dev sets the y token allow list
     * @param _address of the allow list contract
     */
    function setYTokenAllowList(address _address) external;

    /**
     * @dev gets the y token allow list
     * @return _address of the current allow list contract
     */
    function getYTokenAllowList() external returns (address _address);

    /**
     * @dev sets the deployer allow list
     * @param _address of the allow list contract
     */
    function setDeployerAllowList(address _address) external;

    /**
     * @dev gets the deployer allow list
     * @return _address of the current allow list contract
     */
    function getDeployerAllowList() external returns (address _address);

    /**
     * @dev fee percentage for swaps for the protocol
     * @return the percentage for swaps in basis points that will go towards the protocol
     */
    function protocolFee() external returns (uint16);

    /**
     * @dev protocol-fee collector address
     * @return the current protocolFeeCollector address
     */
    function protocolFeeCollector() external returns (address);

    /**
     * @dev proposed protocol-fee collector address
     * @return the current proposedProtocolFeeCollector address
     */
    function proposedProtocolFeeCollector() external returns (address);

    /**
     * @dev This is the function to update the protocol fees per trading.
     * @param _protocolFee percentage of the transaction that will get collected as fees (in percentage basis points:
     * 10000 -> 100.00%; 500 -> 5.00%; 1 -> 0.01%)
     */
    function setProtocolFee(uint16 _protocolFee) external;

    /**
     * @dev function to propose a new protocol fee collector
     * @param _protocolFeeCollector the new fee collector
     * @notice that only the current fee collector address can call this function
     */
    function proposeProtocolFeeCollector(address _protocolFeeCollector) external;

    /**
     * @dev function to confirm a new protocol fee collector
     * @notice that only the already proposed fee collector can call this function
     */
    function confirmProtocolFeeCollector() external;

    /**
     * @dev confirm the factory address
     * @notice Used for the LPToken facotry role. Only the owner is allowed to accept the factory role
     */
    function acceptLPTokenRole() external;

    /**
     * @dev set the LPToken address
     * @param LPTokenAddress the address of the LPToken contract
     * @notice Only the owner can set the LPToken address
     * @notice This function is used to set the LPToken address for the factory
     */
    function setLPTokenAddress(address LPTokenAddress) external;
}
