// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
/*                          INTERFACES                        */
/*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

/**
 * @dev Interface for the fatBERA vault. The function withdrawPrincipal sends the underlying asset
 * (expected to be the wrapped BERA token) to the designated receiver.
 */
interface IFatBera {
    function withdrawPrincipal(uint256 assets, address receiver) external;
    function depositPrincipal() external view returns (uint256);
}

/**
 * @dev Interface for the wrapped BERA token (e.g. WBERA) following an IWETH pattern.
 * Calling withdraw converts wrapped tokens to native BERA.
 */
interface IWETH {
    function withdraw(uint256 amount) external;
}

/**
 * @dev Interface for the beacon deposit contract. The deposit function accepts validator parameters
 * and receives native BERA via msg.value.
 */
interface IBeaconDeposit {
    function deposit(
        bytes calldata pubkey,
        bytes calldata withdrawalCredentials,
        bytes calldata signature,
        address operator
    ) external payable;
}

/**
 * @title AutomatedStake by THJ
 * @notice This contract is designed to be the only admin (aside from a multisig) for the fatBERA vault.
 * It implements a single function, executeWithdrawUnwrapAndStake, which atomically:
 *   1. Withdraws principal from fatBERA (which sends WBERA to this contract),
 *   2. Unwraps WBERA to native BERA,
 *   3. Deposits the native BERA to the beacon deposit contract (staking to the validator).
 */
contract AutomatedStake is Initializable, AccessControlUpgradeable, ReentrancyGuardUpgradeable, UUPSUpgradeable {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           ERRORS                             */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    error ZeroAmount();
    error InvalidAddress();
    error InsufficientBalance();
    error NoFundsToRescue();
    error TransferFailed();
    error InsufficientStakeAmount(uint256 amount, uint256 minimum);
    error InvalidValidatorIndex(uint256 index, uint256 maxIndex);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           EVENTS                             */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    event WithdrawUnwrapAndStakeExecuted(uint256 indexed amount, uint256 indexed validatorIndex, bytes indexed pubkey);
    event ValidatorAdded(uint256 indexed index, bytes pubkey, address operator);
    event ValidatorPubkeyUpdated(uint256 indexed index, bytes newPubkey);
    event WithdrawalCredentialsUpdated(uint256 indexed index, bytes newWithdrawalCredentials);
    event ValidatorSignatureUpdated(uint256 indexed index, bytes newSignature);
    event ValidatorOperatorUpdated(uint256 indexed index, address newOperator);
    event FundsRescued(address recipient, uint256 amount);
    event TokensRescued(address token, address recipient, uint256 amount);
    event MinimumStakeAmountUpdated(uint256 newAmount);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STORAGE                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    bytes32 public constant STAKER_ROLE = keccak256("STAKER_ROLE");

    // Addresses of the external contracts we interact with.
    address public fatBera;
    address public wBera;
    address public beaconDeposit;

    // Validator struct to store all parameters for a single validator
    struct Validator {
        bytes pubkey;
        bytes withdrawalCredentials;
        bytes signature;
        address operator;
    }

    // Array to store multiple validators
    Validator[] public validators;

    // Minimum amount required for staking (initially 15,000 WBERA)
    uint256 public minimumStakeAmount;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     CONSTRUCTOR & INITIALIZER              */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializer function (replaces constructor for upgradeable contracts)
     * @param _fatBera The address of the fatBERA contract.
     * @param _wBera The address of the wrapped BERA token contract.
     * @param _beaconDeposit The address of the beacon deposit contract.
     * @param initialValidators Array of initial validator parameters (up to 3)
     * @param operatorAdmin The multisig address that will be granted admin AND staker roles.
     * @param staker The address that will be granted staker role to execute the staking process.
     */
    function initialize(
        address _fatBera,
        address _wBera,
        address _beaconDeposit,
        Validator[] memory initialValidators,
        address operatorAdmin,
        address staker
    ) external initializer {
        if (
            _fatBera == address(0) || _wBera == address(0) || _beaconDeposit == address(0)
                || operatorAdmin == address(0) || staker == address(0)
        ) {
            revert InvalidAddress();
        }

        __AccessControl_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        fatBera = _fatBera;
        wBera = _wBera;
        beaconDeposit = _beaconDeposit;

        // Add initial validators
        for (uint256 i = 0; i < initialValidators.length; i++) {
            validators.push(initialValidators[i]);
            emit ValidatorAdded(i, initialValidators[i].pubkey, initialValidators[i].operator);
        }

        // Set initial minimum stake amount to 15,000 WBERA (15,000 * 10^18)
        minimumStakeAmount = 15_000 ether;

        // Set up roles - DEFAULT_ADMIN_ROLE for multisig, STAKER_ROLE for automated staker
        _grantRole(DEFAULT_ADMIN_ROLE, operatorAdmin);
        _grantRole(STAKER_ROLE, operatorAdmin);
        _grantRole(STAKER_ROLE, staker);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      EXTERNAL FUNCTIONS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @notice Executes the process to withdraw principal from fatBERA, unwrap WBERA to native BERA,
     * and deposit it to the beacon deposit contract.
     * @dev This function is protected by the STAKER_ROLE and reentrancy guard.
     * @param amount The exact amount to withdraw and stake. Must be >= minimumStakeAmount and <= current deposit principal
     * @param validatorIndex The index of the validator to stake to (0, 1, or 2)
     */
    function executeWithdrawUnwrapAndStake(uint256 amount, uint256 validatorIndex)
        external
        onlyRole(STAKER_ROLE)
        nonReentrant
    {
        if (amount == 0) revert ZeroAmount();
        if (amount < minimumStakeAmount) {
            revert InsufficientStakeAmount(amount, minimumStakeAmount);
        }
        if (validatorIndex >= validators.length) {
            revert InvalidValidatorIndex(validatorIndex, validators.length - 1);
        }

        // Get the validator data
        Validator memory validator = validators[validatorIndex];

        // Step 1: Withdraw principal from fatBERA.
        IFatBera(fatBera).withdrawPrincipal(amount, address(this));

        // Step 2: Unwrap WBERA to native BERA.
        IWETH(wBera).withdraw(amount);

        // Step 3: Stake to the validator via the beacon deposit contract.
        IBeaconDeposit(beaconDeposit).deposit{value: amount}(
            validator.pubkey, validator.withdrawalCredentials, validator.signature, validator.operator
        );

        emit WithdrawUnwrapAndStakeExecuted(amount, validatorIndex, validator.pubkey);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      ADMIN FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @notice Admin function to add a new validator.
     * @param pubkey Validator public key
     * @param withdrawalCredentials Withdrawal credentials
     * @param signature Validator signature
     * @param operator Validator operator address
     * @dev This function can only be called by the admin (multisig)
     */
    function addValidator(
        bytes calldata pubkey,
        bytes calldata withdrawalCredentials,
        bytes calldata signature,
        address operator
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 index = validators.length;
        validators.push(
            Validator({
                pubkey: pubkey,
                withdrawalCredentials: withdrawalCredentials,
                signature: signature,
                operator: operator
            })
        );

        emit ValidatorAdded(index, pubkey, operator);
    }

    /**
     * @notice Admin function to update the validator public key.
     * @param validatorIndex Index of the validator to update
     * @param newPubkey New validator public key
     * @dev This is the most commonly updated parameter when adding new validators
     */
    function setValidatorPubkey(uint256 validatorIndex, bytes calldata newPubkey)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (validatorIndex >= validators.length) {
            revert InvalidValidatorIndex(validatorIndex, validators.length - 1);
        }

        validators[validatorIndex].pubkey = newPubkey;
        emit ValidatorPubkeyUpdated(validatorIndex, newPubkey);
    }

    /**
     * @notice Admin function to update the withdrawal credentials.
     * @param validatorIndex Index of the validator to update
     * @param newWithdrawalCredentials New withdrawal credentials
     * @dev This should rarely need to be updated as it's typically the same for all validators
     */
    function setWithdrawalCredentials(uint256 validatorIndex, bytes calldata newWithdrawalCredentials)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (validatorIndex >= validators.length) {
            revert InvalidValidatorIndex(validatorIndex, validators.length - 1);
        }

        validators[validatorIndex].withdrawalCredentials = newWithdrawalCredentials;
        emit WithdrawalCredentialsUpdated(validatorIndex, newWithdrawalCredentials);
    }

    /**
     * @notice Admin function to update the validator signature.
     * @param validatorIndex Index of the validator to update
     * @param newSignature New validator signature
     */
    function setValidatorSignature(uint256 validatorIndex, bytes calldata newSignature)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (validatorIndex >= validators.length) {
            revert InvalidValidatorIndex(validatorIndex, validators.length - 1);
        }

        validators[validatorIndex].signature = newSignature;
        emit ValidatorSignatureUpdated(validatorIndex, newSignature);
    }

    /**
     * @notice Admin function to update the validator operator address.
     * @param validatorIndex Index of the validator to update
     * @param newOperator New validator operator address
     */
    function setValidatorOperator(uint256 validatorIndex, address newOperator) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (validatorIndex >= validators.length) {
            revert InvalidValidatorIndex(validatorIndex, validators.length - 1);
        }

        validators[validatorIndex].operator = newOperator;
        emit ValidatorOperatorUpdated(validatorIndex, newOperator);
    }

    /**
     * @notice Admin function to update the minimum stake amount.
     * @param newAmount The new minimum amount required for staking
     * @dev This function can only be called by the admin (multisig)
     */
    function setMinimumStakeAmount(uint256 newAmount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newAmount == 0) revert ZeroAmount();
        minimumStakeAmount = newAmount;
        emit MinimumStakeAmountUpdated(newAmount);
    }

    /**
     * @notice Admin function to rescue any accidentally sent native funds.
     * @param recipient The address to forward the rescued funds.
     * @dev This function should only be used in emergency situations.
     */
    function rescueFunds(address payable recipient) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (recipient == address(0)) revert InvalidAddress();

        uint256 balance = address(this).balance;
        if (balance == 0) revert NoFundsToRescue();

        (bool success,) = recipient.call{value: balance}("");
        if (!success) revert TransferFailed();

        emit FundsRescued(recipient, balance);
    }

    /**
     * @notice Admin function to rescue any ERC20 tokens (including WBERA) that are stuck in the contract.
     * @param token The address of the token to rescue
     * @param recipient The address to receive the tokens
     * @param amount The amount of tokens to rescue
     * @dev This function should only be used in emergency situations.
     */
    function rescueTokens(address token, address recipient, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (token == address(0) || recipient == address(0)) revert InvalidAddress();
        if (amount == 0) revert ZeroAmount();

        bool success = IERC20(token).transfer(recipient, amount);
        if (!success) revert TransferFailed();

        emit TokensRescued(token, recipient, amount);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      INTERNAL FUNCTIONS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      RECEIVE & FALLBACK                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @notice Allow the contract to receive native BERA.
     */
    receive() external payable {}

    /**
     * @notice Allow the contract to receive native BERA (fallback).
     */
    fallback() external payable {}
}
