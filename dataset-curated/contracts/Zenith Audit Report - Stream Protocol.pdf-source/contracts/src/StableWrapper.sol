// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IStableWrapper} from "./interfaces/IStableWrapper.sol";
import {OFT} from "@layerzerolabs/oft-evm/contracts/OFT.sol";

/**
 * @title StableWrapper
 * @notice A token wrapper that allows users to obtain tokens needed to deposit into a StreamVault.
 * @notice Users receive a Stream token that maps 1:1 to the asset deposited.
 * @notice Initiated withdrawals can be completed after the epoch has passed.
 */
contract StableWrapper is OFT, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // #############################################
    // STATE
    // #############################################

    /// @notice The asset that the wrapper is wrapping
    address public asset;

    /// @notice The current epoch number
    uint32 public currentEpoch;

    /// @notice Whether the wrapper allows independence.
    /// If false, autostaking is enabled.
    bool public allowIndependence;

    /// @notice The number of decimals for the underlying asset
    /// and the wrapped token
    uint8 public underlyingDecimals;

    /// @notice The address of the keeper
    address public keeper;

    /// @notice Stores the user's pending withdrawals
    mapping(address => WithdrawalReceipt) public withdrawalReceipts;

    /// @notice The amount of assets that have been withdrawn
    uint256 public withdrawalAmountForEpoch;

    /// @notice The amount of assets that have been deposited
    uint256 public depositAmountForEpoch;

    // #############################################
    // STRUCTS
    // #############################################

    /**
     * @notice Struct representing a withdrawal receipt
     * @dev Uses packed storage with uint224 for amount and uint32 for epoch
     * @param amount The amount of tokens requested for withdrawal
     * @param epoch The epoch during which the withdrawal was initiated
     */
    struct WithdrawalReceipt {
        uint224 amount;
        uint32 epoch;
    }

    // #############################################
    // EVENTS
    // #############################################

    event Deposit(address indexed from, address indexed to, uint256 amount);

    event DepositToVault(address indexed user, uint256 amount);

    event WithdrawalInitiated(
        address indexed user,
        uint224 amount,
        uint32 epoch
    );

    event Withdrawn(address indexed user, uint256 amount);

    event WithdrawalsProcessed(uint256 withdrawalAmount, uint256 balance, uint32 epoch);

    event AssetTransferred(address indexed to, uint256 amount);

    event PermissionedMint(address indexed to, uint256 amount);

    event PermissionedBurn(address indexed from, uint256 amount);

    event AllowIndependenceSet(bool allowIndependence);

    event KeeperSet(address keeper);

    // #############################################
    // ERRORS
    // #############################################

    error IndependenceNotAllowed();

    error AmountMustBeGreaterThanZero();

    error AddressMustBeNonZero();

    error InsufficientBalance();

    error NotKeeper();

    error CannotCompleteWithdrawalInSameEpoch();

    // #############################################
    // MODIFIERS
    // #############################################

    /**
     * @dev Throws if called by any account other than the keeper
     */
    modifier onlyKeeper() {
        if (msg.sender != keeper) revert NotKeeper();
        _;
    }

    // #############################################
    // CONSTRUCTOR & INITIALIZATION
    // #############################################

    /**
     * @notice Initializes the contract
     * @param _asset is the address of the asset to wrap
     * @param _name is the name of the wrapped ERC-20
     * @param _symbol is the symbol of the wrapped ERC-20
     * @param _keeper is the address of the keeper
     * @param _lzEndpoint is the address of the LayerZero endpoint
     * @param _delegate is the address of the delegate
     */
    constructor(
        address _asset,
        string memory _name,
        string memory _symbol,
        uint8 _underlyingDecimals,
        address _keeper,
        address _lzEndpoint,
        address _delegate
    ) OFT(_name, _symbol, _lzEndpoint, _delegate) Ownable(msg.sender) {
        if (_asset == address(0)) revert AddressMustBeNonZero();
        if (_keeper == address(0)) revert AddressMustBeNonZero();
        asset = _asset;
        currentEpoch = 1;
        allowIndependence = false;
        keeper = _keeper;
        underlyingDecimals = _underlyingDecimals;
    }

    // #############################################
    // DEPOSIT
    // #############################################

    /**
     * @notice Deposits assets from a specified address and mints equivalent tokens
     * @param to Address to transfer assets to
     * @param amount Amount of assets to deposit
     */
    function deposit(address to, uint256 amount) external nonReentrant {
        if (!allowIndependence) revert IndependenceNotAllowed();
        if (amount == 0) revert AmountMustBeGreaterThanZero();

        _mint(to, amount);

        depositAmountForEpoch += amount;

        emit Deposit(msg.sender, to, amount);

        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
    }

    /**
     * @notice Deposits assets and mints equivalent tokens to the vault
     * @param amount Amount of assets to deposit
     */
    function depositToVault(
        address from,
        uint256 amount
    ) external nonReentrant onlyKeeper {
        if (amount == 0) revert AmountMustBeGreaterThanZero();

        _mint(keeper, amount);

        depositAmountForEpoch += amount;

        emit DepositToVault(from, amount);

        IERC20(asset).safeTransferFrom(from, address(this), amount);
    }

    // #############################################
    // WITHDRAWAL
    // #############################################

    /**
     * @notice Burns tokens and creates withdrawal receipt
     * @param amount Amount of tokens to burn for withdrawal
     */
    function initiateWithdrawal(uint224 amount) external nonReentrant {
        if (!allowIndependence) revert IndependenceNotAllowed();
        if (amount == 0) revert AmountMustBeGreaterThanZero();
        if (balanceOf(msg.sender) < amount) revert InsufficientBalance();

        _burn(msg.sender, amount);

        uint224 currentAmount = withdrawalReceipts[msg.sender].amount;

        withdrawalReceipts[msg.sender] = WithdrawalReceipt({
            amount: currentAmount + amount,
            epoch: currentEpoch
        });

        withdrawalAmountForEpoch += amount;

        emit WithdrawalInitiated(msg.sender, amount, currentEpoch);
    }

    /**
     * @notice Burns tokens and creates withdrawal receipt for a specified address
     * @param from Address to burn tokens from and create withdrawal receipt for
     * @param amount Amount of tokens to burn for withdrawal
     */
    function initiateWithdrawalFromVault(
        address from,
        uint224 amount
    ) external nonReentrant onlyKeeper {
        if (amount == 0) revert AmountMustBeGreaterThanZero();

        _burn(address(this), amount);

        uint224 currentAmount = withdrawalReceipts[from].amount;

        withdrawalReceipts[from] = WithdrawalReceipt({
            amount: currentAmount + amount,
            epoch: currentEpoch
        });

        withdrawalAmountForEpoch += amount;

        emit WithdrawalInitiated(from, amount, currentEpoch);
    }

    /**
     * @notice Complete withdrawal if epoch has passed
     * @param to Address to transfer assets to
     */
    function completeWithdrawal(address to) external nonReentrant {
        WithdrawalReceipt memory receipt = withdrawalReceipts[msg.sender];

        if (receipt.amount == 0) revert AmountMustBeGreaterThanZero();
        if (receipt.epoch >= currentEpoch)
            revert CannotCompleteWithdrawalInSameEpoch();

        delete withdrawalReceipts[msg.sender];

        // Cast uint224 to uint256 explicitly for the transfer
        uint256 amountToTransfer = uint256(receipt.amount);

        emit Withdrawn(to, amountToTransfer);

        IERC20(asset).safeTransfer(to, amountToTransfer);
    }

    // #############################################
    // MINT & BURN
    // #############################################

    /**
     * @notice Allows owner to mint tokens to a specified address
     * @param to Address to mint tokens to
     * @param amount Amount of tokens to mint
     */
    function permissionedMint(address to, uint256 amount) external onlyKeeper {
        _mint(to, amount);
        emit PermissionedMint(to, amount);
    }

    /**
     * @notice Allows owner to burn tokens from a specified address
     * @param from Address to burn tokens from
     * @param amount Amount of tokens to burn
     */
    function permissionedBurn(
        address from,
        uint256 amount
    ) external onlyKeeper {
        _burn(from, amount);
        emit PermissionedBurn(from, amount);
    }

    // #############################################
    // PROTOCOL CONTROL
    // #############################################

    /**
     * @notice Processes the withdrawal for the current epoch
     */
    function processWithdrawals() external onlyOwner nonReentrant {

        if (withdrawalAmountForEpoch > depositAmountForEpoch) {
            IERC20(asset).safeTransferFrom(owner(), address(this), withdrawalAmountForEpoch - depositAmountForEpoch);
        } else if (withdrawalAmountForEpoch < depositAmountForEpoch) {
            IERC20(asset).safeTransfer(owner(), depositAmountForEpoch - withdrawalAmountForEpoch);
        }

        emit WithdrawalsProcessed(withdrawalAmountForEpoch, depositAmountForEpoch, currentEpoch);

        currentEpoch += 1;
        withdrawalAmountForEpoch = 0;
        depositAmountForEpoch = 0;
    }

    /**
     * @notice Allows owner to transfer assets to specified address
     * @param to Address to transfer assets to
     * @param amount Amount of assets to transfer
     * @param _token Address of the token to transfer
     */
    function transferAsset(
        address to,
        uint256 amount,
        address _token
    ) external onlyOwner {
        if (amount == 0) revert AmountMustBeGreaterThanZero();

        emit AssetTransferred(to, amount);

        IERC20(_token).safeTransfer(to, amount);
    }

    // #############################################
    // SETTERS
    // #############################################

    /**
     * @notice Allows keeper to set the keeper address
     * @param _keeper New keeper address
     */
    function setKeeper(address _keeper) external onlyOwner {
        if (_keeper == address(0)) revert AddressMustBeNonZero();
        keeper = _keeper;
        emit KeeperSet(_keeper);
    }

    /**
     * @notice Allows owner to set allowIndependence
     * @param _allowIndependence New allowIndependence value
     */
    function setAllowIndependence(bool _allowIndependence) external onlyOwner {
        allowIndependence = _allowIndependence;
        emit AllowIndependenceSet(_allowIndependence);
    }

    /**
     * @notice Allows keeper to set the asset address
     * @param _asset New asset address
     */
    function setAsset(address _asset) external onlyOwner {
        if (_asset == address(0)) revert AddressMustBeNonZero();
        asset = _asset;
    }

    // #############################################
    // GETTERS
    // #############################################

    /**
     * @notice modify the token decimals
     */
    function setDecimals(uint8 _newDecimals) public onlyOwner {
        underlyingDecimals = _newDecimals;
    }

    /**
     * @notice Returns the token decimals
     */
    function decimals() public view virtual override returns (uint8) {
        return underlyingDecimals;
    }

    /**
     * @notice Returns the shared token decimals for OFT
     */
    function sharedDecimals() public view virtual override returns (uint8) {
        return decimals();
    }
}
