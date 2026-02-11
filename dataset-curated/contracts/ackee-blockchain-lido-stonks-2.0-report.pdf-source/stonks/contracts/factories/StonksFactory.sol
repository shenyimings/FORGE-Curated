// SPDX-FileCopyrightText: 2024 Lido <info@lido.fi>
// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ICoWSwapSettlement} from "../interfaces/ICoWSwapSettlement.sol";

import {Stonks} from "../Stonks.sol";
import {Order} from "../Order.sol";

/**
 * @title StonksFactory
 * @dev Deploys new instances of the Stonks contract.
 */
contract StonksFactory {
    // ==================== Immutables ====================

    /// @notice Address of the Order contract implementation used as a template for cloning.
    address public immutable ORDER_SAMPLE;
    /// @notice Address of the Lido DAO agent.
    address public immutable AGENT;
    /// @notice Address of the OracleRouter contract.
    address public immutable ORACLE_ROUTER;

    // ==================== Events ====================

    event AgentSet(address agent);
    event OrderSampleDeployed(address order);
    event StonksDeployed(
        address indexed stonksAddress,
        address agent,
        address manager,
        address tokenFrom,
        address tokenTo,
        address amountConverter,
        address order,
        address oracleRouter,
        uint256 orderDurationInSeconds,
        uint256 marginInBasisPoints,
        uint256 priceToleranceInBasisPoints,
        uint256 maxImprovementInBasisPoints,
        bool allowPartialFill
    );

    // ==================== Errors ====================

    error InvalidAgentAddress(address agent);
    error InvalidSettlementAddress(address settlement);
    error InvalidRelayerAddress(address relayer);
    error InvalidOracleRouterAddress(address oracleRouter);

    // ==================== Constructor ====================

    /**
     * @param agent_ Address of the Lido DAO agent
     * @param settlement_ Address of the Cow Protocol settlement contract
     * @param relayer_ Address of the Cow Protocol relayer contract
     * @param oracleRouter_ Address of the oracle router contract
     */
    constructor(address agent_, address settlement_, address relayer_, address oracleRouter_) {
        if (agent_ == address(0)) {
            revert InvalidAgentAddress(agent_);
        }

        if (relayer_ == address(0)) {
            revert InvalidRelayerAddress(relayer_);
        }

        if (settlement_ == address(0)) {
            revert InvalidSettlementAddress(settlement_);
        }

        if (oracleRouter_ == address(0)) {
            revert InvalidOracleRouterAddress(oracleRouter_);
        }

        AGENT = agent_;
        ORACLE_ROUTER = oracleRouter_;
        ORDER_SAMPLE = address(
            new Order(agent_, relayer_, ICoWSwapSettlement(settlement_).domainSeparator())
        );

        emit AgentSet(agent_);
        emit OrderSampleDeployed(ORDER_SAMPLE);
    }

    // ==================== External Functions ====================

    /**
     * @notice Deploys a new Stonks contract with specified parameters
     * @param manager_ Address of the manager for the new Stonks contract
     * @param tokenFrom_ Address of the token to be sold
     * @param tokenTo_ Address of the token to be bought
     * @param amountConverter_ Address of the amount converter contract
     * @param orderDurationInSeconds_ Duration of the order in seconds
     * @param marginInBasisPoints_ Margin represented in basis points
     * @param priceToleranceInBasisPoints_ Price tolerance in basis points
     * @param maxImprovementInBasisPoints_ Maximum price improvement allowed in basis points (type(uint256).max = no cap, 0 = strict mode)
     * @param allowPartialFill_ Whether orders should allow partial fills (useful for rebasable tokens)
     * @return stonks The address of the newly deployed Stonks contract
     */
    function deployStonks(
        address manager_,
        address tokenFrom_,
        address tokenTo_,
        address amountConverter_,
        uint256 orderDurationInSeconds_,
        uint256 marginInBasisPoints_,
        uint256 priceToleranceInBasisPoints_,
        uint256 maxImprovementInBasisPoints_,
        bool allowPartialFill_
    ) external returns (address stonks) {
        stonks = address(
            new Stonks(
                Stonks.InitParams(
                    AGENT,
                    manager_,
                    tokenFrom_,
                    tokenTo_,
                    amountConverter_,
                    ORDER_SAMPLE,
                    ORACLE_ROUTER,
                    orderDurationInSeconds_,
                    marginInBasisPoints_,
                    priceToleranceInBasisPoints_,
                    maxImprovementInBasisPoints_,
                    allowPartialFill_
                )
            )
        );

        emit StonksDeployed(
            stonks,
            AGENT,
            manager_,
            tokenFrom_,
            tokenTo_,
            amountConverter_,
            ORDER_SAMPLE,
            ORACLE_ROUTER,
            orderDurationInSeconds_,
            marginInBasisPoints_,
            priceToleranceInBasisPoints_,
            maxImprovementInBasisPoints_,
            allowPartialFill_
        );
    }
}
