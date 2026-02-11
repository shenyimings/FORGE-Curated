// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import { BaseBridgeCoordinator } from "./BaseBridgeCoordinator.sol";
import { BridgeMessageCoordinator, BridgeMessage } from "./BridgeMessageCoordinator.sol";

/**
 * @title PredepositCoordinator
 * @notice Abstract contract that coordinates predeposit operations for bridge transactions
 * @dev This contract extends BaseBridgeCoordinator and BridgeMessageCoordinator to handle
 * predeposit functionality, allowing users to deposit assets before bridge operations
 * are fully operational for the destination chain.
 */
abstract contract PredepositCoordinator is BaseBridgeCoordinator, BridgeMessageCoordinator {
    /**
     * @notice The role that manages predeposit state
     */
    bytes32 public constant PREDEPOSIT_MANAGER_ROLE = keccak256("PREDEPOSIT_MANAGER_ROLE");
    /**
     * @dev keccak256(abi.encode(uint256(keccak256("generic.storage.PredepositCoordinator")) - 1)) &
     * ~bytes32(uint256(0xff))
     */
    bytes32 private constant PREDEPOSIT_COORDINATOR_STORAGE_SLOT =
        0xc21018d819991b3ffe7c98205610e4fd64c7a07a5010749045af9b9d7860c300;

    /**
     * @notice The various states a predeposit can be in
     */
    enum PredepositState {
        DISABLED,
        ENABLED,
        DISPATCHED,
        WITHDRAWN
    }

    /**
     * @notice Struct representing a blockchain configuration for predeposit operations
     * @param state The current state of predeposits for this chain
     * @param chainId The chain ID of the destination chain
     * @param whitelabel The whitelabeled unit token address for this chain, or zero for native unit token
     * @param predeposits Mapping of owner addresses to remote recipient addresses to predeposit amounts
     * @param totalPredeposits The total amount of units predeposited for this chain
     */
    struct PredepositChain {
        PredepositState state;
        uint256 chainId;
        bytes32 whitelabel;
        mapping(address owner => mapping(bytes32 remoteRecipient => uint256 amount)) predeposits;
        uint256 totalPredeposits;
    }

    /**
     * @dev The coordinator is expected to be an upgradeable proxy contract, and any future
     * updates to the storage layout must respect the original storage structure to maintain
     * compatibility and prevent storage collisions. When adding new storage variables,
     * append them to the end of this struct to preserve existing storage slots.
     */
    /// @custom:storage-location erc7201:generic.storage.PredepositCoordinator
    struct PredepositCoordinatorStorage {
        mapping(bytes32 nickname => PredepositChain) chain;
    }

    /**
     * @dev Returns the storage pointer for PredepositCoordinator
     */
    function _getPredepositCoordinatorStorage() private pure returns (PredepositCoordinatorStorage storage $) {
        assembly {
            $.slot := PREDEPOSIT_COORDINATOR_STORAGE_SLOT
        }
    }

    /**
     * @dev Emitted when users predeposit tokens for future bridging
     * @param chainNickname The nickname of the destination chain
     * @param sender The address that initiated the predeposit
     * @param owner The owner of the predeposit on the source chain
     * @param remoteRecipient The recipient address on the destination chain (encoded as bytes32)
     * @param amount The amount of tokens predeposited
     */
    event Predeposited(
        bytes32 indexed chainNickname,
        address sender,
        address indexed owner,
        bytes32 indexed remoteRecipient,
        uint256 amount
    );
    /**
     * @notice Emitted when a predeposit has been successfully bridged out to another chain
     * @param chainNickname The identifier/nickname of the destination chain where the predeposit was bridged
     * @param messageId The unique identifier for the cross-chain bridge message
     */
    event PredepositBridgedOut(bytes32 indexed chainNickname, bytes32 indexed messageId);
    /**
     * @notice Emitted when a predeposit has been withdrawn back by the original owner
     * @param chainNickname The nickname of the chain where the predeposit was committed to
     * @param owner The address on this chain on whose behalf the units are bridged
     * @param remoteRecipient The recipient address on the destination chain (encoded as bytes32)
     * @param recipient The address on this chain to receive the withdrawn tokens
     * @param amount The amount of tokens withdrawn
     */
    event PredepositWithdrawn(
        bytes32 indexed chainNickname,
        address indexed owner,
        bytes32 indexed remoteRecipient,
        address recipient,
        uint256 amount
    );
    /**
     * @notice Emitted when the predeposit state for a chain nickname changes
     * @param chainNickname The nickname of the chain whose predeposit state changed
     * @param newState The new state of predeposits for the chain
     */
    event PredepositStateChanged(bytes32 indexed chainNickname, PredepositState newState);
    /**
     * @notice Emitted when a chain ID is assigned to a chain nickname
     * @param chainNickname The nickname of the chain
     * @param chainId The chain ID assigned to the nickname
     */
    event ChainIdAssignedToNickname(bytes32 indexed chainNickname, uint256 chainId);
    /**
     * @notice Emitted when a whitelabeled unit address is assigned to a nickname for a specific chain
     * @param chainNickname The nickname of the chain
     * @param whitelabel The address of the whitelabeled unit token
     */
    event WhitelabelAssignedToNickname(bytes32 indexed chainNickname, bytes32 indexed whitelabel);

    /**
     * @notice Thrown when predeposits are not enabled for the specified chain nickname
     */
    error Predeposit_NotEnabled();
    /**
     * @notice Thrown when dispatching predeposits is not enabled for the specified chain nickname
     */
    error Predeposit_DispatchNotEnabled();
    /**
     * @notice Thrown when withdrawals are not enabled for the specified chain nickname
     */
    error Predeposit_WithdrawalsNotEnabled();
    /**
     * @notice Thrown when the chain ID for the specified chain nickname is already set
     */
    error Predeposit_ChainIdAlreadySet();
    /**
     * @notice Thrown when the on behalf parameter is zero
     */
    error Predeposit_ZeroOnBehalf();
    /**
     * @notice Thrown when the remote recipient parameter is zero
     */
    error Predeposit_ZeroRemoteRecipient();
    /**
     * @notice Thrown when the recipient address is zero
     */
    error Predeposit_ZeroRecipient();
    /**
     * @notice Thrown when the bridge amount is zero
     */
    error Predeposit_ZeroAmount();
    /**
     * @notice Thrown when the predeposit state transition is invalid
     */
    error Predeposit_InvalidStateTransition();
    /**
     * @notice Thrown when the chain ID for the specified chain nickname is zero
     */
    error Predeposit_ChainIdZero();

    // ========================================
    // PREDEPOSIT LIFECYCLE
    // ========================================

    /**
     * @notice Predeposits units for bridging to another chain
     * @dev Restricts units on this chain to be bridged later via bridgePredeposit
     * @param chainNickname The nickname of the destination chain
     * @param onBehalf The address on behalf of which the predeposit is made
     * @param remoteRecipient The recipient address on the destination chain (encoded as bytes32)
     * @param amount The amount of units to predeposit
     */
    function predeposit(
        bytes32 chainNickname,
        address onBehalf,
        bytes32 remoteRecipient,
        uint256 amount
    )
        external
        nonReentrant
    {
        PredepositChain storage chain = _getPredepositCoordinatorStorage().chain[chainNickname];
        require(chain.state == PredepositState.ENABLED, Predeposit_NotEnabled());
        require(onBehalf != address(0), Predeposit_ZeroOnBehalf());
        require(remoteRecipient != bytes32(0), Predeposit_ZeroRemoteRecipient());
        require(amount > 0, Predeposit_ZeroAmount());

        chain.predeposits[onBehalf][remoteRecipient] += amount;
        chain.totalPredeposits += amount;

        _restrictUnits(address(0), msg.sender, amount);
        emit Predeposited(chainNickname, msg.sender, onBehalf, remoteRecipient, amount);
    }

    /**
     * @notice Bridges predeposited units to another chain using the specified bridge protocol
     * @dev Sends a message to release predeposited units on destination chain
     * @param bridgeType The identifier for the bridge protocol to use (must have registered adapter)
     * @param chainNickname The nickname of the destination chain
     * @param owner The address on this chain on whose behalf the units are bridged
     * @param remoteRecipient The recipient address on the destination chain (encoded as bytes32)
     * @param bridgeParams Protocol-specific parameters required by the bridge adapter
     * @return messageId Unique identifier for tracking the cross-chain message
     */
    function bridgePredeposit(
        uint16 bridgeType,
        bytes32 chainNickname,
        address owner,
        bytes32 remoteRecipient,
        bytes calldata bridgeParams
    )
        external
        payable
        nonReentrant
        returns (bytes32 messageId)
    {
        PredepositChain storage chain = _getPredepositCoordinatorStorage().chain[chainNickname];
        require(chain.state == PredepositState.DISPATCHED, Predeposit_DispatchNotEnabled());
        uint256 chainId = chain.chainId;
        require(chainId != 0, Predeposit_ChainIdZero());
        uint256 amount = chain.predeposits[owner][remoteRecipient];
        require(amount > 0, Predeposit_ZeroAmount());

        delete chain.predeposits[owner][remoteRecipient];
        chain.totalPredeposits -= amount;

        BridgeMessage memory bridgeMessage = BridgeMessage({
            sender: encodeOmnichainAddress(owner),
            recipient: remoteRecipient,
            sourceWhitelabel: encodeOmnichainAddress(address(0)),
            destinationWhitelabel: chain.whitelabel,
            amount: amount
        });
        messageId = _dispatchMessage(bridgeType, chainId, encodeBridgeMessage(bridgeMessage), bridgeParams);

        emit BridgedOut(msg.sender, owner, remoteRecipient, amount, messageId, bridgeMessage);
        emit PredepositBridgedOut(chainNickname, messageId);
    }

    /**
     * @notice Withdraws predeposited units that were not bridged
     * @dev Releases units back to the original sender
     * @param chainNickname The nickname of the chain where the predeposit was made
     * @param remoteRecipient The recipient address on the destination chain (encoded as bytes32)
     * @param recipient The address on this chain to receive the withdrawn units
     * @param whitelabel The whitelabeled unit token address, or zero address for native unit token
     */
    function withdrawPredeposit(
        bytes32 chainNickname,
        bytes32 remoteRecipient,
        address recipient,
        address whitelabel
    )
        external
        nonReentrant
    {
        PredepositChain storage chain = _getPredepositCoordinatorStorage().chain[chainNickname];
        require(chain.state == PredepositState.WITHDRAWN, Predeposit_WithdrawalsNotEnabled());
        require(recipient != address(0), Predeposit_ZeroRecipient());
        uint256 amount = chain.predeposits[msg.sender][remoteRecipient];
        require(amount > 0, Predeposit_ZeroAmount());

        delete chain.predeposits[msg.sender][remoteRecipient];
        chain.totalPredeposits -= amount;

        _releaseUnits(whitelabel, recipient, amount);
        emit PredepositWithdrawn(chainNickname, msg.sender, remoteRecipient, recipient, amount);
    }

    // ========================================
    // CHAIN STATE TRANSITION
    // ========================================

    /**
     * @notice Enables predeposits for the specified chain nickname
     * @param chainNickname The nickname of the chain to enable predeposits for
     */
    function enablePredeposits(bytes32 chainNickname) external onlyRole(PREDEPOSIT_MANAGER_ROLE) {
        PredepositChain storage chain = _getPredepositCoordinatorStorage().chain[chainNickname];
        require(chain.state == PredepositState.DISABLED, Predeposit_InvalidStateTransition());
        chain.state = PredepositState.ENABLED;
        emit PredepositStateChanged(chainNickname, PredepositState.ENABLED);
    }

    /**
     * @notice Enables dispatching predeposits for the specified chain nickname
     * @dev Should be called only after chain adapters are registered in BridgeCoordinator
     * @param chainNickname The nickname of the chain to enable predeposits dispatch for
     * @param chainId The chain ID of the destination chain
     * @param whitelabel The address of the whitelabeled unit token for this chain, zero for unit token
     */
    function enablePredepositsDispatch(
        bytes32 chainNickname,
        uint256 chainId,
        bytes32 whitelabel
    )
        external
        onlyRole(PREDEPOSIT_MANAGER_ROLE)
    {
        PredepositChain storage chain = _getPredepositCoordinatorStorage().chain[chainNickname];
        require(chain.state == PredepositState.ENABLED, Predeposit_InvalidStateTransition());
        require(chain.chainId == 0, Predeposit_ChainIdAlreadySet());
        require(chainId != 0, Predeposit_ChainIdZero());

        chain.state = PredepositState.DISPATCHED;
        chain.chainId = chainId;
        chain.whitelabel = whitelabel;

        emit PredepositStateChanged(chainNickname, PredepositState.DISPATCHED);
        emit ChainIdAssignedToNickname(chainNickname, chainId);
        emit WhitelabelAssignedToNickname(chainNickname, whitelabel);
    }

    /**
     * @notice Enables withdrawals of predeposits for the specified chain nickname
     * @param chainNickname The nickname of the chain to enable predeposits withdrawals for
     */
    function enablePredepositsWithdraw(bytes32 chainNickname) external onlyRole(PREDEPOSIT_MANAGER_ROLE) {
        PredepositChain storage chain = _getPredepositCoordinatorStorage().chain[chainNickname];
        require(chain.state == PredepositState.ENABLED, Predeposit_InvalidStateTransition());
        chain.state = PredepositState.WITHDRAWN;
        emit PredepositStateChanged(chainNickname, PredepositState.WITHDRAWN);
    }

    /**
     * @notice Sets the chain ID for the specified chain nickname
     * @dev Can be used to override chain ID or set it after enabling dispatch
     * @param chainNickname The nickname of the chain to set the ID for
     * @param chainId The chain ID of the destination chain
     */
    function setChainIdToNickname(
        bytes32 chainNickname,
        uint256 chainId
    )
        external
        onlyRole(PREDEPOSIT_MANAGER_ROLE)
    {
        PredepositChain storage chain = _getPredepositCoordinatorStorage().chain[chainNickname];
        require(chain.state == PredepositState.DISPATCHED, Predeposit_DispatchNotEnabled());
        require(chainId != 0, Predeposit_ChainIdZero());
        chain.chainId = chainId;
        emit ChainIdAssignedToNickname(chainNickname, chainId);
    }

    /**
     * @notice Sets the whitelabeled unit address for the specified chain nickname
     * @param chainNickname The nickname of the chain to set the whitelabeled unit address for
     * @param whitelabel The address of the whitelabeled unit token
     */
    function setWhitelabelForNickname(
        bytes32 chainNickname,
        bytes32 whitelabel
    )
        external
        onlyRole(PREDEPOSIT_MANAGER_ROLE)
    {
        PredepositChain storage chain = _getPredepositCoordinatorStorage().chain[chainNickname];
        chain.whitelabel = whitelabel;
        emit WhitelabelAssignedToNickname(chainNickname, whitelabel);
    }

    // ========================================
    // GETTERS
    // ========================================

    /**
     * @notice Gets the predeposit state for the specified chain nickname
     * @param chainNickname The nickname of the chain to get the predeposit state for
     * @return The current PredepositState of the specified chain nickname
     */
    function getChainPredepositState(bytes32 chainNickname) external view returns (PredepositState) {
        PredepositCoordinatorStorage storage $ = _getPredepositCoordinatorStorage();
        return $.chain[chainNickname].state;
    }

    /**
     * @notice Gets the chain ID assigned to the specified chain nickname
     * @param chainNickname The nickname of the chain to get the ID for
     * @return The chain ID assigned to the specified chain nickname, or zero if not set
     */
    function getChainIdForNickname(bytes32 chainNickname) external view returns (uint256) {
        PredepositCoordinatorStorage storage $ = _getPredepositCoordinatorStorage();
        return $.chain[chainNickname].chainId;
    }

    /**
     * @notice Gets the predeposited amount for a given sender and remote recipient on a specified chain nickname
     * @param chainNickname The nickname of the chain to get the predeposit for
     * @param sender The address that initiated the predeposit
     * @param remoteRecipient The recipient address on the destination chain (encoded as bytes32)
     * @return The amount of units predeposited by the sender for the remote recipient
     */
    function getPredeposit(
        bytes32 chainNickname,
        address sender,
        bytes32 remoteRecipient
    )
        external
        view
        returns (uint256)
    {
        PredepositCoordinatorStorage storage $ = _getPredepositCoordinatorStorage();
        return $.chain[chainNickname].predeposits[sender][remoteRecipient];
    }

    /**
     * @notice Gets the total predeposited amount for the specified chain nickname
     * @param chainNickname The nickname of the chain to get the total predeposits for
     * @return The total amount of units predeposited for the specified chain nickname
     */
    function getTotalPredeposits(bytes32 chainNickname) external view returns (uint256) {
        PredepositCoordinatorStorage storage $ = _getPredepositCoordinatorStorage();
        return $.chain[chainNickname].totalPredeposits;
    }

    /**
     * @notice Gets the whitelabeled unit address assigned to the specified chain nickname
     * @param chainNickname The nickname of the chain to get the whitelabeled unit address for
     * @return The whitelabeled unit address assigned to the specified chain nickname
     */
    function getWhitelabelForNickname(bytes32 chainNickname) external view returns (bytes32) {
        PredepositCoordinatorStorage storage $ = _getPredepositCoordinatorStorage();
        return $.chain[chainNickname].whitelabel;
    }
}
