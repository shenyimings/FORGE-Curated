// SPDX-License-Identifier: ISC
pragma solidity 0.8.25;

import "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorCountingSimpleUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorSettingsUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorStorageUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorTimelockControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorVotesUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorVotesQuorumFractionUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/governance/GovernorUpgradeable.sol";
import "@openzeppelin/contracts/governance/utils/IVotes.sol";

/**
 * @title This is version 2 of the Governor contract that is delegated to by `AnvilGovernorDelegator` for the Anvil
 * protocol to implement governance logic.
 *
 * @custom:security-contact security@af.xyz
 */
contract AnvilGovernorDelegate is
    GovernorUpgradeable,
    GovernorSettingsUpgradeable,
    GovernorCountingSimpleUpgradeable,
    GovernorVotesUpgradeable,
    GovernorVotesQuorumFractionUpgradeable,
    GovernorStorageUpgradeable,
    GovernorTimelockControlUpgradeable
{
    /****************
     * PUBLIC VIEWS *
     ****************/

    /// @inheritdoc IGovernor
    function quorum(
        uint256 blockNumber
    ) public view override(GovernorUpgradeable, GovernorVotesQuorumFractionUpgradeable) returns (uint256) {
        return super.quorum(blockNumber);
    }

    /// @inheritdoc IGovernor
    function proposalNeedsQueuing(
        uint256 proposalId
    ) public view virtual override(GovernorUpgradeable, GovernorTimelockControlUpgradeable) returns (bool) {
        return super.proposalNeedsQueuing(proposalId);
    }

    /// @inheritdoc IGovernor
    function proposalThreshold()
        public
        view
        override(GovernorUpgradeable, GovernorSettingsUpgradeable)
        returns (uint256)
    {
        return super.proposalThreshold();
    }

    /// @inheritdoc IGovernor
    function state(
        uint256 proposalId
    ) public view override(GovernorUpgradeable, GovernorTimelockControlUpgradeable) returns (ProposalState) {
        return super.state(proposalId);
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public view override(GovernorUpgradeable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    /// @inheritdoc IGovernor
    function votingDelay() public view override(GovernorUpgradeable, GovernorSettingsUpgradeable) returns (uint256) {
        return super.votingDelay();
    }

    /// @inheritdoc IGovernor
    function votingPeriod() public view override(GovernorUpgradeable, GovernorSettingsUpgradeable) returns (uint256) {
        return super.votingPeriod();
    }

    /*****************************
     * STATE-MODIFYING FUNCTIONS *
     *****************************/

    /**
     * Initializes this delegate so that it may be used, as it operates within the UpgradableProxy pattern, in which
     * logic that would typically be contained within a constructor is moved to `initialize(...)` since the delegate
     * must be deployed before it is used by the contract that delegates to it.
     */
    function initialize(
        TimelockControllerUpgradeable timelock_,
        address governanceToken_,
        uint32 votingPeriod_,
        uint48 votingDelay_,
        uint256 proposalThreshold_
    ) public initializer {
        __Governor_init("AnvilGovernorDelegate");
        __GovernorSettings_init(votingDelay_, votingPeriod_, proposalThreshold_);
        __GovernorCountingSimple_init();
        __GovernorVotes_init(IVotes(governanceToken_));
        // NB: initializes quorum to 5% of total supply
        __GovernorVotesQuorumFraction_init(5);
        __GovernorStorage_init();
        __GovernorTimelockControl_init(timelock_);
    }

    /**
     * Reinitializes the contract, updating the governance token.
     *
     * @dev Can only be called during execution of a governance proposal, and may only be called once due to the nature
     * of the reinitializer modifier.
     *
     * @param newGovernanceToken_ Address of the new governance token.
     */
    function reinitializeGovernanceToken(address newGovernanceToken_) external reinitializer(2) onlyGovernance {
        __GovernorVotes_init(IVotes(newGovernanceToken_));
    }

    /**
     * NB: We do not want to allow for the upgrade of our Timelock, though we must inherit from the `GovernorTimelockControlUpgradeable`
     * due to constraints within Solidity. Thus, we disable upgrade manually by overriding the `updateTimelock` function.
     *
     * @inheritdoc GovernorTimelockControlUpgradeable
     */
    function updateTimelock(
        TimelockControllerUpgradeable
    ) external override(GovernorTimelockControlUpgradeable) onlyGovernance {
        revert("Cannot upgrade the timelock");
    }

    /********************************
     * PRIVATE / INTERNAL FUNCTIONS *
     ********************************/

    /// @inheritdoc GovernorUpgradeable
    function _cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(GovernorUpgradeable, GovernorTimelockControlUpgradeable) returns (uint256) {
        return super._cancel(targets, values, calldatas, descriptionHash);
    }

    /// @inheritdoc GovernorUpgradeable
    function _executor()
        internal
        view
        override(GovernorUpgradeable, GovernorTimelockControlUpgradeable)
        returns (address)
    {
        return super._executor();
    }

    /// @inheritdoc GovernorUpgradeable
    function _executeOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal virtual override(GovernorUpgradeable, GovernorTimelockControlUpgradeable) {
        super._executeOperations(proposalId, targets, values, calldatas, descriptionHash);
    }

    /// @inheritdoc GovernorUpgradeable
    function _propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description,
        address proposer
    ) internal virtual override(GovernorUpgradeable, GovernorStorageUpgradeable) returns (uint256) {
        return super._propose(targets, values, calldatas, description, proposer);
    }

    /// @inheritdoc GovernorUpgradeable
    function _queueOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal virtual override(GovernorUpgradeable, GovernorTimelockControlUpgradeable) returns (uint48) {
        return super._queueOperations(proposalId, targets, values, calldatas, descriptionHash);
    }
}
