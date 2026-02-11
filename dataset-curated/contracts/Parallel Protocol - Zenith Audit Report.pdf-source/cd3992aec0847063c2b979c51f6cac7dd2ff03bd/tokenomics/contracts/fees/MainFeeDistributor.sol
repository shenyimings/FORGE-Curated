// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { IBridgeableToken } from "contracts/interfaces/IBridgeableToken.sol";

import { FeeCollectorCore, ReentrancyGuard, IERC20, SafeERC20 } from "./FeeCollectorCore.sol";

/// @title MainFeeDistributor
/// @author Cooper Labs
/// @custom:contact security@cooperlabs.xyz
/// @notice Handles the reception and the distribution of fee tokens.

contract MainFeeDistributor is FeeCollectorCore {
    using SafeERC20 for IERC20;

    //-------------------------------------------
    // Storage
    //-------------------------------------------

    /// @notice token bridgeableToken contract
    IERC20 public bridgeableToken;
    /// @notice Total shares of the fee receivers.
    uint256 public totalShares;
    /// @notice Mapping of the shares of the fee receivers.
    mapping(address => uint256) public shares;
    /// @notice Array of the fee receivers.
    address[] public feeReceivers;

    //-------------------------------------------
    // Events
    //-------------------------------------------

    /// @notice Emitted when a new fee receiver is added to the fee distribution.
    /// @param feeReceiver The address of the fee receiver.
    /// @param shares The number of shares assigned to the fee receiver.
    event FeeReceiverAdded(address feeReceiver, uint256 shares);

    /// @notice Emitted when fees are released.
    /// @param feeReceiver The address of the fee receiver.
    /// @param income The amount of income released.
    event FeeReleasedTo(address feeReceiver, uint256 income);

    /// @notice Emitted when the bridgeable token is updated.
    /// @param newBridgeableToken The address of the new bridgeable token.
    event BridgeableTokenUpdated(address newBridgeableToken);

    /// @notice Emitted when lzToken are swapped.
    /// @param amount The amount of lzToken swapped.
    event LzTokenSwapped(uint256 amount);

    //-------------------------------------------
    // Errors
    //-------------------------------------------

    /// @notice Thrown when the fee receiver address is zero.
    error FeeReceiverZeroAddress();
    /// @notice Thrown when the shares are zero.
    error SharesIsZero();
    /// @notice Thrown when the fee receiver is already added.
    error FeeReceiverAlreadyAdded();
    /// @notice Thrown when there is no fee receivers.
    error NoFeeReceivers();
    /// @notice Thrown when the array length mismatch.
    error ArrayLengthMismatch();
    /// @notice Thrown when the maximum swap amount is zero.
    error MaxSwappableAmountIsZero();
    /// @notice Thrown when the lzToken balance is zero.
    error NothingToSwap();
    /// @notice Thrown when the lzToken balance is not zero
    /// during bridgeableToken contract address update.
    error NeedToSwapAllLzTokenFirst();

    //-------------------------------------------
    // Constructor
    //-------------------------------------------

    ///@notice MainFeeDistributor constructor.
    ///@param _bridgeableToken address of the bridgeable token.
    ///@param _accessManager address of the AccessManager contract.
    ///@param _feeToken address of the fee token.
    constructor(
        address _accessManager,
        address _bridgeableToken,
        address _feeToken
    )
        FeeCollectorCore(_accessManager, _feeToken)
    {
        bridgeableToken = IERC20(_bridgeableToken);
    }

    //-------------------------------------------
    // External functions
    //-------------------------------------------

    /// @notice Release the fees to the fee receivers according to their shares.
    function release() external nonReentrant whenNotPaused {
        uint256 income = feeToken.balanceOf(address(this));
        if (income == 0) revert NothingToRelease();
        if (feeReceivers.length == 0) revert NoFeeReceivers();
        for (uint256 i = 0; i < feeReceivers.length; i++) {
            address feeReceiver = feeReceivers[i];
            _release(income, feeReceiver);
        }
    }

    /// @notice swap Lz-Token to Token if limit not reached.
    /// @dev lzToken doesn't need approval to be swapped.
    function swapLzToken() external nonReentrant whenNotPaused {
        uint256 balance = bridgeableToken.balanceOf(address(this));
        if (balance == 0) revert NothingToSwap();

        uint256 maxSwapAmount = IBridgeableToken(address(bridgeableToken)).getMaxCreditableAmount();
        if (maxSwapAmount == 0) revert MaxSwappableAmountIsZero();

        uint256 swapAmount = balance > maxSwapAmount ? maxSwapAmount : balance;

        emit LzTokenSwapped(swapAmount);
        IBridgeableToken(address(bridgeableToken)).swapLzTokenToPrincipalToken(address(this), swapAmount);
    }

    /// @notice Get the addresses that will receive fees.
    function getFeeReceivers() external view returns (address[] memory) {
        return feeReceivers;
    }

    //-------------------------------------------
    // AccessManaged functions
    //-------------------------------------------

    /// @notice Allow to update the fees receivers list and shares.
    /// @dev This function can only be called by the accessManager.
    /// @param _feeReceivers The list of the fee receivers.
    /// @param _shares The list of the shares assigned to the fee receivers.
    function updateFeeReceivers(address[] memory _feeReceivers, uint256[] memory _shares) public restricted {
        if (_feeReceivers.length == 0) revert NoFeeReceivers();
        if (_feeReceivers.length != _shares.length) revert ArrayLengthMismatch();
        delete feeReceivers;

        uint256 _totalShares = 0;
        uint256 i = 0;
        for (; i < _feeReceivers.length; ++i) {
            _totalShares += _addFeeReceiver(_feeReceivers[i], _shares[i]);
        }
        totalShares = _totalShares;
    }

    /// @notice Allow to update the bridgeable token.
    /// @dev This function can only be called by the accessManager.
    /// @param _newBridgeableToken The address of the bridgeable token.
    function updateBridgeableToken(address _newBridgeableToken) external restricted {
        if (bridgeableToken.balanceOf(address(this)) > 0) revert NeedToSwapAllLzTokenFirst();
        bridgeableToken = IERC20(_newBridgeableToken);
        emit BridgeableTokenUpdated(_newBridgeableToken);
    }

    //-------------------------------------------
    // Internal/Private functions
    //-------------------------------------------

    /// @notice Release the fees to the fee receiver.
    /// @param _totalIncomeToDistribute The total amount of income received.
    /// @param _feeReceiver The address of the fee receiver.
    function _release(uint256 _totalIncomeToDistribute, address _feeReceiver) internal {
        uint256 amount = _totalIncomeToDistribute * shares[_feeReceiver] / totalShares;
        emit FeeReleasedTo(_feeReceiver, amount);
        feeToken.safeTransfer(_feeReceiver, amount);
    }

    /// @notice Add a new fee receiver.
    /// @param _feeReceiver The address of the fee receiver.
    /// @param _shares The number of shares assigned to the fee receiver.
    function _addFeeReceiver(address _feeReceiver, uint256 _shares) internal returns (uint256) {
        if (_feeReceiver == address(0)) revert FeeReceiverZeroAddress();
        if (_shares == 0) revert SharesIsZero();

        feeReceivers.push(_feeReceiver);
        shares[_feeReceiver] = _shares;
        emit FeeReceiverAdded(_feeReceiver, _shares);
        return _shares;
    }
}
