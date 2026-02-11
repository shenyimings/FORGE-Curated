// SPDX-License-Identifier: ISC
pragma solidity 0.8.25;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @notice A rewards contract that allows a rewarder account to reward many different accounts efficiently. The rewarder
 * may modify reward amounts at any time to add additional rewards or nullify unclaimed rewards, for instance.
 *
 * @dev Rewards are represented as a Merkle root with claim proofs made available off-chain. A pending rewards root
 * delay may be specified to make it so newly published rewards roots do not take effect for some period of time. This
 * approach enables automated root publishing via a hot wallet, lessening the impact of wallet compromise and/or
 * incorrect root publishing by allowing issues to be detected and addressed before new Merkle roots take effect.
 *
 * @custom:security-contact security@af.xyz
 */
contract Reward is AccessControl {
    using SafeERC20 for IERC20;

    /***************
     * ERROR TYPES *
     ***************/

    error ClaimAmountTooBig(uint256 _requested, uint256 _availableForClaim);
    error InvalidProof();
    error NoClaimableTokens();
    error NoOp();

    /**********
     * EVENTS *
     **********/

    event RewardsClaimed(address indexed byAccount, uint256 amount);
    event PendingRewardsRootUpdated(bytes32 indexed pendingRoot);
    event PendingRewardsDelayUpdated(uint32 oldDelaySeconds, uint32 newDelaySeconds);
    event RewardsRootUpdated(bytes32 indexed oldRoot, bytes32 indexed newRoot);
    event RewardsRootRevoked(bytes32 indexed oldRoot, bytes32 indexed oldPendingRoot);

    /******************
     * CONTRACT STATE *
     ******************/

    /*** Role definitions for RBAC ***/
    /// Admin role able to administer other roles and perform admin functions.
    bytes32 public constant ADMIN_ROLE = 0xa49807205ce4d355092ef5a8a18f56e8913cf4a201fbe287825b095693c21775; // keccak256("ADMIN_ROLE")

    /// Publisher role able to publish new `rewardsRoots`, subject to a time delay.
    bytes32 public constant PUBLISHER_ROLE = 0x0ac90c257048ef1c3e387c26d4a99bde06894efbcbff862dc1885c3a9319308a; // keccak256("PUBLISHER_ROLE")

    /// Revoker role able to revoke pending and/or live `rewardsRoots` immediately.
    bytes32 public constant REVOKER_ROLE = 0xce3f34913921da558f105cefb578d87278debbbd073a8d552b5de0d168deee30; // keccak256("REVOKER_ROLE")

    /// The merkle root of each account's cumulative reward balance since the beginning of time.
    /// Note: No assumptions should be made about this root. The owners of this contract may update it at any time.
    /// NB: leaves in this tree are of the format `abi.encode(address _address, uint256 _balance)`.
    bytes32 public rewardsRoot;

    /// The pending rewards root that will take effect after `pendingRootDelay`, if set.
    bytes32 public pendingRewardsRoot;

    /// The block timestamp at which the `pendingRewardsRoot` was set.
    uint32 public pendingRootSetTimestamp;

    /// The pending rewards root delay dictating how long a new `rewardsRoot` must be pending before taking effect.
    uint32 public pendingRootDelaySeconds;

    /// The token being rewarded via this contract.
    IERC20 public rewardToken;

    /// account address => amount that has been claimed by each account.
    mapping(address => uint256) public totalClaimedRewards;

    /*************
     * MODIFIERS *
     *************/

    /// Processes the `pendingRewardsRoot`, if there is one, turning it into the `rewardsRoot` if enough time has passed.
    modifier withPendingRootProcessed() {
        bytes32 vested = getVestedPendingRewardsRoot();
        if (vested != bytes32(0)) {
            bytes32 previousRoot = rewardsRoot;
            rewardsRoot = vested;
            pendingRewardsRoot = bytes32(0);

            emit RewardsRootUpdated(previousRoot, vested);
        }
        _;
    }

    /****************
     * PUBLIC VIEWS *
     ****************/

    /**
     * @notice Gets the `rewardsRoot`, as it would be set for a claim right now.
     * This is useful because the contract state may contain stale data that will be updated next transaction. For
     * instance, the stored `rewardsRoot` will be replaced before a claim if there is a vested `pendingRewardsRoot`.
     *
     * @return The `rewardsRoot` that would be used if this were a write operation.
     */
    function getEffectiveRewardsRoot() public view returns (bytes32) {
        bytes32 vested = getVestedPendingRewardsRoot();
        return vested != bytes32(0) ? vested : rewardsRoot;
    }

    /**
     * @notice Verifies the provided address has the provided rewards balance according to the provided merkle proof,
     * reverting if it does not.
     * @param _address The address in question.
     * @param _rewardsBalance The rewards balance being proven.
     * @param _forPendingRoot True if the validation should be done against the `pendingRewardsRoot` (default is `rewardsRoot`).
     * @param _proof The merkle proof that the address has the balance.
     */
    function verifyRewardsBalanceOrRevert(
        address _address,
        uint256 _rewardsBalance,
        bool _forPendingRoot,
        bytes32[] calldata _proof
    ) external view {
        _verifyRewardsBalanceOrRevert(_address, _rewardsBalance, _forPendingRoot, _proof);
    }

    /*****************************
     * STATE-MODIFYING FUNCTIONS *
     *****************************/

    /**
     * @notice Constructs an instance of the Rewards contract to make _token claimable by rewarded accounts. Rewarded
     * accounts and amounts are specified in the leaf data of the Merkle Tree specified by `_initialRewardsRoot`.
     *
     * @param _admin The initial admin of this contract, which can add addresses to any role.
     * @param _publisher The initial address that is allowed to publish rewards roots (address(0) means nobody will have this role).
     * @param _revoker The initial address that is allowed to revoke rewards roots (address(0) means nobody will have this role).
     * @param _rewardToken The ERC20 token in which rewards will be granted.
     * @param _initialRewardsRoot The initial Merkle Root specifying rewards balances by account.
     * @param _pendingRootDelaySeconds The number of seconds after a new `rewardsRoot` is published that it takes effect. If 0, it will take effect immediately.
     */
    constructor(
        address _admin,
        address _publisher,
        address _revoker,
        IERC20 _rewardToken,
        bytes32 _initialRewardsRoot,
        uint32 _pendingRootDelaySeconds
    ) {
        if (address(_rewardToken) == address(0)) revert();
        if (_admin == address(0)) revert();

        pendingRootDelaySeconds = _pendingRootDelaySeconds;

        rewardToken = _rewardToken;

        if (_initialRewardsRoot != bytes32(0)) {
            // NB: there is no delay for the initial root because a delay may be
            // enforced by not funding the contract or making Merkle proofs available.
            rewardsRoot = _initialRewardsRoot;
        }

        _setRoleAdmin(ADMIN_ROLE, ADMIN_ROLE);
        _grantRole(ADMIN_ROLE, _admin);

        _setRoleAdmin(PUBLISHER_ROLE, ADMIN_ROLE);
        if (_publisher != address(0)) {
            _grantRole(PUBLISHER_ROLE, _publisher);
        }

        _setRoleAdmin(REVOKER_ROLE, ADMIN_ROLE);
        if (_revoker != address(0)) {
            _grantRole(REVOKER_ROLE, _revoker);
        }
    }

    /**
     * @notice Claims the provided amount to the sender, assuming that address has a sufficient proven claimable amount.
     *
     * Note: If there is a vested pending root, it will be processed ahead of this call.
     *
     * @param _amountToClaim The amount to be sent to the msg.sender. If 0, all claimable rewards will be claimed.
     * @param _amountInProof The total reward amount in the proof that will be validated by the rewardsRoot.
     * @param _proof The merkle proof that proves the rewards balance for the address.
     */
    function claim(
        uint256 _amountToClaim,
        uint256 _amountInProof,
        bytes32[] calldata _proof
    ) external withPendingRootProcessed {
        _verifyRewardsBalanceOrRevert(msg.sender, _amountInProof, false, _proof);

        uint256 alreadyClaimed = totalClaimedRewards[msg.sender];

        if (_amountInProof <= alreadyClaimed) revert NoClaimableTokens();

        uint256 claimableBalance = _amountInProof - alreadyClaimed;
        if (_amountToClaim > claimableBalance) revert ClaimAmountTooBig(_amountToClaim, claimableBalance);

        if (_amountToClaim == 0) {
            _amountToClaim = claimableBalance;
        }

        totalClaimedRewards[msg.sender] = alreadyClaimed + _amountToClaim;

        rewardToken.safeTransfer(msg.sender, _amountToClaim);

        emit RewardsClaimed(msg.sender, _amountToClaim);
    }

    /************************
     * PRIVILEGED FUNCTIONS *
     ************************/

    /**
     * @notice Updates the delay after which the `pendingRewardsRoot` will become the `rewardsRoot`.
     *
     * @dev This may only be called by addresses with the `ADMIN_ROLE`.
     *
     * @param _newDelaySeconds The new delay in seconds.
     */
    function updatePendingRootDelaySeconds(uint32 _newDelaySeconds) external onlyRole(ADMIN_ROLE) {
        uint32 oldDelaySeconds = pendingRootDelaySeconds;
        if (_newDelaySeconds == oldDelaySeconds) revert NoOp();

        pendingRootDelaySeconds = _newDelaySeconds;
        emit PendingRewardsDelayUpdated(oldDelaySeconds, _newDelaySeconds);
    }

    /**
     * @notice Publishes the reward Merkle Root, making new balances available for rewarded accounts after
     * `pendingRootDelaySeconds`, if set, immediately if not.
     *
     * Note: the leaf data in this root is cumulative. If the reward balance for an account was 100, and the owner would
     * like to make an additional 200 claimable, the new leaf for this account should be 300, regardless of whether the
     * account address has claimed the initial 100.
     *
     * Note: this is a completely trusted function. The publisher role may update the root to any value at any time.
     * The owner must also make proofs for this new root available offline, if there are any.
     *
     * Alternatively, the publisher may revoke rewards that have not yet been claimed by decreasing the leaf balance and/or
     * publishing a root of all zeros. There is a race condition with this approach in that the owner does not know
     * whether the rewards will be claimed prior to them submitting the updated root and it taking effect. If claimed,
     * the `claimedRewards` balance for the account will be increased, and future rewards will not be claimable until
     * they exceed the claimed amount. So in the long-run, this decrease will be enforced.
     *
     * @dev Publishing an incorrect root along with incorrect proofs may lead to all tokens held by this contract being
     * withdrawn by accounts with inflated incorrect merkle tree leaf data. Care should be taken in calculating and
     * validating leaf data against the token amount held in this contract and considering and properly setting a
     * `pendingRootDelaySeconds` value.
     *
     * @dev This may only be called by addresses with the `PUBLISHER_ROLE`.
     *
     * @param _newRoot The new rewards Merkle Root that dictates cumulative reward amount by account.
     */
    function publishRewardsRoot(bytes32 _newRoot) external onlyRole(PUBLISHER_ROLE) withPendingRootProcessed {
        bytes32 existingRoot = rewardsRoot;
        if (existingRoot == _newRoot) revert NoOp();

        if (pendingRootDelaySeconds > 0) {
            existingRoot = pendingRewardsRoot;
            if (existingRoot == _newRoot) revert NoOp();

            pendingRootSetTimestamp = uint32(block.timestamp);
            pendingRewardsRoot = _newRoot;

            emit PendingRewardsRootUpdated(_newRoot);
        } else {
            rewardsRoot = _newRoot;
            emit RewardsRootUpdated(existingRoot, _newRoot);
        }
    }

    /**
     * @notice Revokes the existing `rewardsRoot` and `pendingRewardsRoot` if they exist, setting them to bytes32(0).
     *
     * @dev This may only be called by addresses with the `REVOKER_ROLE`.
     */
    function revokeRewardsRoot() external onlyRole(REVOKER_ROLE) {
        bytes32 existingRoot = rewardsRoot;
        if (existingRoot == bytes32(0)) revert NoOp();

        bytes32 existingPendingRoot = pendingRewardsRoot;
        if (existingPendingRoot != bytes32(0)) {
            pendingRewardsRoot = bytes32(0);
        }

        rewardsRoot = bytes32(0);
        emit RewardsRootRevoked(existingRoot, existingPendingRoot);
    }

    /**
     * @notice This function allows admins to withdraw ERC-20 tokens. While this contract should only ever hold the
     * `rewardToken`, other tokens may be sent to it by accident or on purpose. This function allows any ERC-20 token
     * held by this contract to be withdrawn.
     *
     * @dev This may only be called by addresses with the `ADMIN_ROLE`.
     *
     * @param _tokens The array of tokens to be withdrawn. Note: indexes in this array correspond to those in `_amounts`.
     * @param _amounts The array of amounts to be withdrawn. Note: indexes in this array correspond to those in `_tokens`.
     */
    function withdrawTokens(IERC20[] memory _tokens, uint256[] calldata _amounts) external onlyRole(ADMIN_ROLE) {
        address admin = msg.sender;
        for (uint256 i = 0; i < _tokens.length; i++) {
            _tokens[i].safeTransfer(admin, _amounts[i]);
        }
    }

    /********************************
     * PRIVATE / INTERNAL FUNCTIONS *
     ********************************/

    /**
     * @notice Verifies the provided address has the provided rewards balance according to the provided merkle proof,
     * reverting if it does not.
     * @param _address The address in question.
     * @param _rewardsBalance The rewards balance being proven.
     * @param _forPendingRoot True if the validation should be done against the `pendingRewardsRoot` (default is `rewardsRoot`).
     * @param _proof The merkle proof that the address has the balance.
     */
    function _verifyRewardsBalanceOrRevert(
        address _address,
        uint256 _rewardsBalance,
        bool _forPendingRoot,
        bytes32[] calldata _proof
    ) private view {
        if (
            !MerkleProof.verifyCalldata(
                _proof,
                _forPendingRoot ? pendingRewardsRoot : rewardsRoot,
                keccak256(abi.encodePacked(keccak256(abi.encode(_address, _rewardsBalance))))
            )
        ) {
            revert InvalidProof();
        }
    }

    /**
     * @notice Returns the `pendingRewardsRoot` if it is set and has vested for pendingRootDelaySeconds time.
     *
     * @return The vested pending rewards root, if there is one, bytes32(0) otherwise.
     */
    function getVestedPendingRewardsRoot() internal view returns (bytes32) {
        bytes32 root = pendingRewardsRoot;
        return
            root != bytes32(0) && block.timestamp >= pendingRootSetTimestamp + pendingRootDelaySeconds
                ? root
                : bytes32(0);
    }
}
