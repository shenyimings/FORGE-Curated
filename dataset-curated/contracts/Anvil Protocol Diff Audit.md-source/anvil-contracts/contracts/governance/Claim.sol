// SPDX-License-Identifier: ISC
pragma solidity 0.8.25;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "./IClaimable.sol";

/**
 * @notice Contract that supports one-time issuance of a configurable amount of tokens to a configurable number of
 * addresses over a configurable vesting schedule. Instead of tracking token balances at construction-/initialization
 * time, a merkle root is posted to this contract, allowing accounts to prove their balances if they so choose.
 *
 * Note: only the associated token contract is able to call `proveInitialBalance(...)`, so this contract is very tightly-
 * coupled to tokens that resemble the Anvil token, that is to say governance tokens that permit accounts with balances
 * in this Claim contract to be delegated and used in voting.
 *
 * @custom:security-contact security@af.xyz
 */
contract Claim is IClaimable, Ownable2Step {
    /***************
     * ERROR TYPES *
     ***************/

    error Unauthorized();
    error AlreadyInitialized();
    error ClaimAmountTooBig(uint256 _requested, uint256 _availableForClaim);
    error InvalidProof();
    error NoClaimableTokens();
    error OwnerRescueTooSoon();
    error RescueDestinationHasInitialBalance();
    error VestingPeriodNotStarted();
    error InvalidInitialization();

    /***********
     * STRUCTS *
     ***********/

    // NB: Total issuance is 100_000_000_000e18, so uint128 is plenty
    struct Balance {
        uint128 initial;
        uint128 claimed;
    }

    /**********
     * EVENTS *
     **********/

    event TokensClaimed(address indexed byAccount, uint256 amount);
    event InitialBalanceProven(address indexed account, uint256 initialBalance);
    event FundsRescued(address indexed to, uint256 amount);

    /******************
     * CONTRACT STATE *
     ******************/

    /// The merkle root of initial user balances that will be subject to this contract's vesting / claim functionality.
    /// NB: leaves in this tree are of the format `abi.encode(address _address, uint256 _balance)`.
    bytes32 public balanceRoot;

    /// The timestamp at which vesting begins. No tokens will be claimable prior to this date.
    uint32 public vestingStartTimestamp;

    /// The number of seconds after `vestingStartTimestamp` at which point all tokens will be vested.
    uint32 public vestingPeriodSeconds;

    /// The timestamp after which unproven balances may be withdrawn by the owner. See documentation for ownerRescueTokens(...).
    uint32 public ownerRescueTimestamp;

    /// The total amount that has been proven but not claimed. This reduces the amount eligible for rescue after `ownerRescueTimestamp`.
    uint128 public totalProvenUnclaimed;

    /// The token for which this contract manages claims
    IERC20 public token;

    /// account address => Balance (see struct above). Note: this struct is 0 until `proveInitialBalance()` is called.
    mapping(address => Balance) public provenBalances;

    /****************
     * PUBLIC VIEWS *
     ****************/

    /**
     * @notice Returns the proven unclaimed balance for the provided account.
     * @param _forAccount The account for which the proven unclaimed balance will be returned.
     * @return The proven unclaimed balance.
     */
    function getProvenUnclaimedBalance(address _forAccount) public view returns (uint256) {
        Balance storage provenBalanceStorage = provenBalances[_forAccount];
        return uint256(provenBalanceStorage.initial - provenBalanceStorage.claimed);
    }

    /*****************************
     * STATE-MODIFYING FUNCTIONS *
     *****************************/

    /// Note: this contract is mostly useless until it is initialized via `initialize(...)` below.
    constructor() Ownable(msg.sender) {}

    /**
     * @notice Initializes this claim contract, indicating the token that may be claimed, the root of the balances
     * merkle tree and vesting parameters.
     *
     * @dev Leaves of the merkle tree for which the root is provided are of the format `abi.encode(address, uint256)`,
     * where the address is the address of the account and the uint256 is the initial balance of that account.
     *
     * Note: It is assumed, not enforced, that this contract will receive the amount of _token that constitutes the sum
     * of all leaves in the merkle tree for which _balanceRoot is the root. On-chain observers will have no way of
     * knowing that, but off-chain proofs can be made publicly available to provide this assurance.
     * @param _token The ERC-20 token on which this contract operates.
     * @param _balanceRoot The merkle root of the balances.
     * @param _vestingStartDelaySeconds The number of seconds after which claim vesting will start.
     * @param _vestingPeriodSeconds The period over which token vesting will complete.
     * @param _ownerRescueDelaySeconds The number of seconds after initialization when the owner may withdraw all unproven tokens.
     */
    function initialize(
        IERC20 _token,
        bytes32 _balanceRoot,
        uint256 _vestingStartDelaySeconds,
        uint256 _vestingPeriodSeconds,
        uint256 _ownerRescueDelaySeconds
    ) external onlyOwner {
        if (address(token) != address(0)) revert AlreadyInitialized();
        if (address(_token) == address(0)) revert InvalidInitialization();
        if (_balanceRoot == bytes32(0)) revert InvalidInitialization();
        if (_vestingPeriodSeconds == 0) revert InvalidInitialization();
        token = _token;
        balanceRoot = _balanceRoot;
        vestingStartTimestamp = uint32(block.timestamp + _vestingStartDelaySeconds);
        vestingPeriodSeconds = uint32(_vestingPeriodSeconds);
        ownerRescueTimestamp = uint32(block.timestamp + _ownerRescueDelaySeconds);
    }

    /**
     * @notice Claims the provided amount to the sender, assuming that address has a sufficient proven claimable amount.
     * @param _amount The amount to claim.this
     */
    function claim(uint256 _amount) external {
        uint256 vestingStart = vestingStartTimestamp;
        if (block.timestamp <= vestingStart) revert VestingPeriodNotStarted();

        uint256 vestedSeconds = block.timestamp - vestingStartTimestamp;
        uint256 periodSeconds = vestingPeriodSeconds;

        Balance storage provenBalanceStorage = provenBalances[msg.sender];
        uint256 vested = vestedSeconds >= periodSeconds
            ? uint256(provenBalanceStorage.initial)
            : (vestedSeconds * uint256(provenBalanceStorage.initial)) / periodSeconds;

        uint256 claimed = uint256(provenBalanceStorage.claimed);
        uint256 claimableBalance = vested - claimed;

        if (claimableBalance == 0) revert NoClaimableTokens();
        if (_amount > claimableBalance) revert ClaimAmountTooBig(_amount, claimableBalance);

        if (_amount == 0) {
            _amount = claimableBalance;
        }

        provenBalanceStorage.claimed = uint128(claimed + _amount);

        totalProvenUnclaimed -= uint128(_amount);

        // NB: Return value not checked because this was developed for Anvil, and that reverts on failure.
        // If repurposing this contract, update to suit your needs.
        token.transfer(msg.sender, _amount);

        emit TokensClaimed(msg.sender, _amount);
    }

    /**
     * @notice Allows tokens locked in this contract to be rescued by the owner after a sufficiently long period of time
     * allowing intended owners to prove their balances. The idea is that if the intended owner hasn't taken action,
     * they have lost access or do not care to claim.
     * @dev This disables all future proofs and rescues.
     * @param _destination The address to which tokens will be transferred.
     */
    function ownerRescueTokens(address _destination) external onlyOwner {
        if (block.timestamp < ownerRescueTimestamp) revert OwnerRescueTooSoon();
        if (getProvenUnclaimedBalance(_destination) > 0) revert RescueDestinationHasInitialBalance();

        delete balanceRoot;

        uint256 amount = token.balanceOf(address(this)) - totalProvenUnclaimed;
        if (amount == 0) return;

        // NB: Return value not checked because this was developed for Anvil, and that reverts on failure.
        // If repurposing this contract, update to suit your needs.
        token.transfer(_destination, amount);

        emit FundsRescued(_destination, amount);
    }

    /**
     * @inheritdoc IClaimable
     */
    function proveInitialBalance(
        address _address,
        uint256 _initialBalance,
        bytes32[] calldata _proof
    ) external returns (uint256) {
        if (msg.sender != address(token)) revert Unauthorized();

        Balance storage provenBalanceStorage = provenBalances[_address];
        if (provenBalanceStorage.initial != 0) return 0;
        _verifyInitialBalanceOrRevert(_address, _initialBalance, _proof);

        totalProvenUnclaimed += uint128(_initialBalance);

        provenBalanceStorage.initial = uint128(_initialBalance);
        emit InitialBalanceProven(_address, _initialBalance);
        return _initialBalance;
    }

    /**
     * Note: this is overridden to disable it.
     *
     * @inheritdoc Ownable
     */
    function renounceOwnership() public override onlyOwner {
        // Disallow accidental and intentional ownership renunciation.
        revert();
    }

    /********************************
     * PRIVATE / INTERNAL FUNCTIONS *
     ********************************/

    /**
     * @notice Verifies the provided address has the provided initial balance according to the provided merkle proof,
     * reverting if it does not.
     * @param _address The address in question.
     * @param _initialBalance The initial balance being proven.
     * @param _proof The merkle proof that the address has the balance.
     */
    function _verifyInitialBalanceOrRevert(
        address _address,
        uint256 _initialBalance,
        bytes32[] calldata _proof
    ) private view {
        if (
            !MerkleProof.verifyCalldata(
                _proof,
                balanceRoot,
                keccak256(abi.encodePacked(keccak256(abi.encode(_address, _initialBalance))))
            )
        ) {
            revert InvalidProof();
        }
    }
}
