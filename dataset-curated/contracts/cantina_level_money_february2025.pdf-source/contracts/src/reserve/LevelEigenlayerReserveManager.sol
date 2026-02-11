// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19;

import "./LevelBaseReserveManager.sol";
import "../interfaces/eigenlayer/IDelegationManager.sol";
import "../interfaces/eigenlayer/IStrategyManager.sol";
import "../interfaces/eigenlayer/ISignatureUtils.sol";
import "../interfaces/eigenlayer/IRewardsCoordinator.sol";

/**
 * @title Level Reserve Manager
 */
contract EigenlayerReserveManager is LevelBaseReserveManager {
    using SafeERC20 for IERC20;

    address public delegationManager;
    address public strategyManager;
    address public rewardsCoordinator;
    string public operatorName;

    error StrategiesAndSharesMustBeSameLength();
    error StrategiesAndTokensMustBeSameLength();
    error StrategiesSharesAndTokensMustBeSameLength();

    event Undelegated();
    event DelegatedToOperator(address operator);

    /* --------------- CONSTRUCTOR --------------- */

    constructor(
        IlvlUSD _lvlusd,
        address _delegationManager,
        address _strategyManager,
        address _rewardsCoordinator,
        IStakedlvlUSD _stakedlvlUSD,
        address _admin,
        address _allowlister,
        string memory _operatorName
    ) LevelBaseReserveManager(_lvlusd, _stakedlvlUSD, _admin, _allowlister) {
        delegationManager = _delegationManager;
        strategyManager = _strategyManager;
        rewardsCoordinator = _rewardsCoordinator;
        operatorName = _operatorName;
    }

    /* --------------- EXTERNAL --------------- */

    function delegateTo(
        address operator,
        bytes memory signature,
        uint256 expiry,
        bytes32 approverSalt
    ) external onlyRole(MANAGER_AGENT_ROLE) whenNotPaused {
        ISignatureUtils.SignatureWithExpiry
            memory approverSignatureAndExpiry = ISignatureUtils
                .SignatureWithExpiry({signature: signature, expiry: expiry});
        IDelegationManager(delegationManager).delegateTo(
            operator,
            approverSignatureAndExpiry,
            approverSalt
        );
        emit DelegatedToOperator(operator);
    }

    function undelegate() external onlyRole(MANAGER_AGENT_ROLE) whenNotPaused {
        IDelegationManager(delegationManager).undelegate(address(this));
        emit Undelegated();
    }

    function depositIntoStrategy(
        address strategy,
        address token,
        uint256 amount
    ) external onlyRole(MANAGER_AGENT_ROLE) whenNotPaused {
        IERC20 tokenContract = IERC20(token);

        // Approve the StrategyManager to spend the tokens
        tokenContract.forceApprove(address(strategyManager), amount);

        // Deposit into the strategy
        IStrategyManager(strategyManager).depositIntoStrategy(
            IStrategy(strategy),
            tokenContract,
            amount
        );
    }

    function depositAllTokensIntoStrategy(
        address[] calldata tokens,
        IStrategy[] calldata strategies
    ) external onlyRole(MANAGER_AGENT_ROLE) whenNotPaused {
        if (tokens.length != strategies.length) {
            revert StrategiesAndTokensMustBeSameLength();
        }

        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20 token = IERC20(tokens[i]);
            uint256 balance = token.balanceOf(address(this));

            if (balance == 0) continue;

            token.forceApprove(address(strategyManager), balance);

            IStrategyManager(strategyManager).depositIntoStrategy(
                strategies[i],
                token,
                balance
            );
        }
    }

    function queueWithdrawals(
        IStrategy[] memory strategies,
        uint256[] memory shares
    )
        external
        onlyRole(MANAGER_AGENT_ROLE)
        whenNotPaused
        returns (bytes32[] memory)
    {
        if (strategies.length != shares.length) {
            revert StrategiesAndSharesMustBeSameLength();
        }
        IDelegationManager.QueuedWithdrawalParams
            memory withdrawalParam = IDelegationManager.QueuedWithdrawalParams({
                strategies: strategies, // Array of strategies that the QueuedWithdrawal contains
                shares: shares, // Array containing the amount of shares in each Strategy in the `strategies` array
                withdrawer: address(this) // The address of the withdrawer
            });
        IDelegationManager.QueuedWithdrawalParams[]
            memory withdrawalParams = new IDelegationManager.QueuedWithdrawalParams[](
                1
            );
        withdrawalParams[0] = withdrawalParam;
        return
            IDelegationManager(delegationManager).queueWithdrawals(
                withdrawalParams
            );
    }

    // The arguments to the functions (specifically nonce and startBlock)
    // can be found by fetching the relevant event emitted by queueWithdrawal or undelegate:
    //
    // - WithdrawalQueued(bytes32 withdrawalRoot, Withdrawal withdrawal)
    //
    // For reference, the Withdrawal struct looks like:
    //
    //  struct Withdrawal {
    //    address staker;
    //    address delegatedTo;
    //    address withdrawer;
    //    uint256 nonce;
    //    uint32 startBlock;
    //    IStrategy[] strategies;
    //    uint256[] shares;
    //   }
    //
    // Note that multiple withdraw requests can be queued at once.
    function completeQueuedWithdrawal(
        uint nonce,
        address operator,
        uint32 startBlock, // startBlock is the block at which the withdrawal was queued
        IERC20[] calldata tokens,
        IStrategy[] memory strategies,
        uint256[] memory shares
    ) external onlyRole(MANAGER_AGENT_ROLE) whenNotPaused {
        if (
            tokens.length != strategies.length ||
            tokens.length != shares.length ||
            strategies.length != shares.length
        ) {
            revert StrategiesSharesAndTokensMustBeSameLength();
        }
        IDelegationManager.Withdrawal memory withdrawal = IDelegationManager
            .Withdrawal({
                staker: address(this),
                delegatedTo: operator,
                withdrawer: address(this),
                nonce: nonce,
                startBlock: startBlock,
                strategies: strategies,
                shares: shares
            });
        IDelegationManager(delegationManager).completeQueuedWithdrawal(
            withdrawal,
            tokens,
            0 /* middleware index is currently a no-op */,
            true /* receive as tokens*/
        );
    }

    // sets the rewards claimer for this contract to be `claimer`
    function setRewardsClaimer(
        address claimer
    ) external onlyRole(MANAGER_AGENT_ROLE) whenNotPaused {
        IRewardsCoordinator(rewardsCoordinator).setClaimerFor(claimer);
    }

    // ============================== SETTERS ==============================

    function setDelegationManager(
        address _delegationManager
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        delegationManager = _delegationManager;
    }

    function setStrategyManager(
        address _strategyManager
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        strategyManager = _strategyManager;
    }

    function setRewardsCoordinator(
        address _rewardsCoordinator
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        rewardsCoordinator = _rewardsCoordinator;
    }

    function setOperatorName(
        string calldata _operatorName
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        operatorName = _operatorName;
    }
}
