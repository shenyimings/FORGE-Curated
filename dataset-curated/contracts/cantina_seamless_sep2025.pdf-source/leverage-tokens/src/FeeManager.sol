// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Dependency imports
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Internal imports
import {ExternalAction} from "src/types/DataTypes.sol";
import {ILeverageToken} from "src/interfaces/ILeverageToken.sol";
import {IFeeManager} from "src/interfaces/IFeeManager.sol";

/**
 * @dev The FeeManager contract is an abstract upgradeable core contract that is responsible for managing the fees for LeverageTokens.
 * There are three types of fees:
 *   - Token action fees: Fees charged that accumulate towards the value of the LeverageToken for current LeverageToken
 *     holders, applied on equity for mints and redeems
 *   - Treasury action fees: Fees charged in shares that are transferred to the configured treasury address, applied on
 *     shares minted for mints and shares burned for redeems
 *   - Management fees: Fees charged in shares that are transferred to the configured treasury address. The management fee
 *     accrues linearly over time and is minted to the treasury when the `chargeManagementFee` function is executed
 * Note: This contract is abstract and meant to be inherited by LeverageManager
 * The maximum fee that can be set for each action is 100_00 (100%).
 *
 * @custom:contact security@seamlessprotocol.com
 */
abstract contract FeeManager is IFeeManager, Initializable, AccessControlUpgradeable {
    bytes32 public constant FEE_MANAGER_ROLE = keccak256("FEE_MANAGER_ROLE");

    uint256 internal constant MAX_BPS = 100_00;

    uint256 internal constant MAX_BPS_SQUARED = MAX_BPS * MAX_BPS;

    uint256 internal constant MAX_ACTION_FEE = MAX_BPS - 1;

    uint256 internal constant MAX_MANAGEMENT_FEE = MAX_BPS;

    uint256 internal constant SECS_PER_YEAR = 31536000;

    /// @dev Struct containing all state for the FeeManager contract
    /// @custom:storage-location erc7201:seamless.contracts.storage.FeeManager
    struct FeeManagerStorage {
        /// @dev Treasury address that receives treasury fees and management fees
        address treasury;
        /// @dev Default annual management fee for LeverageTokens at creation. 100_00 is 100% per year
        uint256 defaultManagementFeeAtCreation;
        /// @dev Annual management fee for each LeverageToken. 100_00 is 100% per year
        mapping(ILeverageToken token => uint256) managementFee;
        /// @dev Timestamp when the management fee was most recently accrued for each LeverageToken
        mapping(ILeverageToken token => uint120) lastManagementFeeAccrualTimestamp;
        /// @dev Treasury action fee for each action. 100_00 is 100%
        mapping(ExternalAction action => uint256) treasuryActionFee;
        /// @dev Token action fee for each action. 100_00 is 100%
        mapping(ILeverageToken token => mapping(ExternalAction action => uint256)) tokenActionFee;
    }

    function _getFeeManagerStorage() internal pure returns (FeeManagerStorage storage $) {
        // slither-disable-next-line assembly
        assembly {
            // keccak256(abi.encode(uint256(keccak256("seamless.contracts.storage.FeeManager")) - 1)) & ~bytes32(uint256(0xff));
            $.slot := 0x6c0d8f7f1305f10aa51c80093531513ff85a99140b414f68890d41ac36949e00
        }
    }

    function __FeeManager_init(address defaultAdmin, address treasury) internal onlyInitializing {
        __AccessControl_init_unchained();
        __FeeManager_init_unchained(defaultAdmin, treasury);
    }

    function __FeeManager_init_unchained(address defaultAdmin, address treasury) internal onlyInitializing {
        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _setTreasury(treasury);
    }

    /// @inheritdoc IFeeManager
    function getDefaultManagementFeeAtCreation() public view returns (uint256) {
        return _getFeeManagerStorage().defaultManagementFeeAtCreation;
    }

    /// @inheritdoc IFeeManager
    function getFeeAdjustedTotalSupply(ILeverageToken token) public view returns (uint256) {
        uint256 totalSupply = token.totalSupply();
        uint256 accruedManagementFee = _getAccruedManagementFee(token, totalSupply);
        return totalSupply + accruedManagementFee;
    }

    /// @inheritdoc IFeeManager
    function getLastManagementFeeAccrualTimestamp(ILeverageToken token) public view returns (uint120) {
        return _getFeeManagerStorage().lastManagementFeeAccrualTimestamp[token];
    }

    /// @inheritdoc IFeeManager
    function getLeverageTokenActionFee(ILeverageToken token, ExternalAction action) public view returns (uint256 fee) {
        return _getFeeManagerStorage().tokenActionFee[token][action];
    }

    /// @inheritdoc IFeeManager
    function getManagementFee(ILeverageToken token) public view returns (uint256 fee) {
        return _getFeeManagerStorage().managementFee[token];
    }

    /// @inheritdoc IFeeManager
    function getTreasury() public view returns (address treasury) {
        return _getFeeManagerStorage().treasury;
    }

    /// @inheritdoc IFeeManager
    function getTreasuryActionFee(ExternalAction action) public view returns (uint256 fee) {
        return _getFeeManagerStorage().treasuryActionFee[action];
    }

    /// @inheritdoc IFeeManager
    function setDefaultManagementFeeAtCreation(uint256 fee) external onlyRole(FEE_MANAGER_ROLE) {
        _validateManagementFee(fee);

        _getFeeManagerStorage().defaultManagementFeeAtCreation = fee;
        emit DefaultManagementFeeAtCreationSet(fee);
    }

    /// @inheritdoc IFeeManager
    function setManagementFee(ILeverageToken token, uint256 fee) external onlyRole(FEE_MANAGER_ROLE) {
        // Charge any accrued management fees before setting the new management fee
        chargeManagementFee(token);

        _validateManagementFee(fee);

        _getFeeManagerStorage().managementFee[token] = fee;
        emit ManagementFeeSet(token, fee);
    }

    /// @inheritdoc IFeeManager
    function setTreasury(address treasury) external onlyRole(FEE_MANAGER_ROLE) {
        _setTreasury(treasury);
    }

    /// @inheritdoc IFeeManager
    function setTreasuryActionFee(ExternalAction action, uint256 fee) external onlyRole(FEE_MANAGER_ROLE) {
        _validateActionFee(fee);
        _getFeeManagerStorage().treasuryActionFee[action] = fee;

        emit TreasuryActionFeeSet(action, fee);
    }

    /// @inheritdoc IFeeManager
    function chargeManagementFee(ILeverageToken token) public {
        // Shares fee must be obtained before the last management fee accrual timestamp is updated
        uint256 sharesFee = _getAccruedManagementFee(token, token.totalSupply());
        _getFeeManagerStorage().lastManagementFeeAccrualTimestamp[token] = uint120(block.timestamp);

        _chargeTreasuryFee(token, sharesFee);
        emit ManagementFeeCharged(token, sharesFee);
    }

    /// @notice Function that mints shares to the treasury, if the treasury is set
    /// @param token LeverageToken to mint shares to treasury for
    /// @param shares Shares to mint
    /// @dev This contract must be authorized to mint shares for the LeverageToken
    function _chargeTreasuryFee(ILeverageToken token, uint256 shares) internal {
        // slither-disable-next-line timestamp
        if (shares != 0) {
            // slither-disable-next-line reentrancy-events
            token.mint(getTreasury(), shares);
        }
    }

    /// @notice Computes the share fees for a given action and share amount
    /// @param token LeverageToken to compute share fees for
    /// @param grossShares Amount of shares to compute share fees for
    /// @param action Action to compute share fees for
    /// @return netShares Amount of shares after fees
    /// @return sharesTokenFee Amount of shares that will be charged for the action that are given to the LeverageToken
    /// @return treasuryFee Amount of shares that will be charged for the action that are given to the treasury
    /// @dev Token action fee is applied first, then treasury action fee is applied on the remaining shares
    function _computeFeesForGrossShares(ILeverageToken token, uint256 grossShares, ExternalAction action)
        internal
        view
        returns (uint256, uint256, uint256)
    {
        uint256 sharesTokenFee =
            Math.mulDiv(grossShares, getLeverageTokenActionFee(token, action), MAX_BPS, Math.Rounding.Ceil);
        uint256 netShares = grossShares - sharesTokenFee;
        uint256 treasuryFee = _computeTreasuryFee(action, netShares);

        netShares = netShares - treasuryFee;

        return (netShares, sharesTokenFee, treasuryFee);
    }

    /// @notice Based on an amount of net shares, compute the gross shares, token fee, and treasury fee
    /// @param token LeverageToken to compute token fee for
    /// @param netShares Net shares to compute token fee for
    /// @param action Action to compute token fee for
    /// @return grossShares Gross shares after token fee and treasury fee
    /// @return sharesTokenFee Token fee amount in shares
    /// @return treasuryFee Treasury fee amount in shares
    /// @dev Token action fee is applied first, then treasury action fee is applied on the remaining shares
    function _computeFeesForNetShares(ILeverageToken token, uint256 netShares, ExternalAction action)
        internal
        view
        returns (uint256 grossShares, uint256 sharesTokenFee, uint256 treasuryFee)
    {
        uint256 tokenActionFeeRate = getLeverageTokenActionFee(token, action);
        uint256 treasuryActionFeeRate = getTreasuryActionFee(action);

        // Mathematical derivation for computing gross shares from net shares:
        //
        // Starting relationship for a single fee:
        //   net = gross * (baseFee - feeRate) / baseFee
        //   where feeRate is the fee percentage and baseFee is the base (100_00 for 100%)
        //
        // Rearranging to solve for gross:
        //   gross = net * baseFee / (baseFee - feeRate)
        //
        // For two sequential fees (token action fee and treasury action fee), we apply this transformation twice:
        //   1) First, apply token action fee: afterTokenFee = gross * (baseFee - tokenActionFeeRate) / baseFee
        //   2) Then, apply treasury action fee: net = afterTokenFee * (baseFee - treasuryActionFeeRate) / baseFee
        //
        // Substituting step 1 into step 2:
        //   net = gross * (baseFee - tokenActionFeeRate) / baseFee * (baseFee - treasuryActionFeeRate) / baseFee
        //   net = gross * (baseFee - tokenActionFeeRate) * (baseFee - treasuryActionFeeRate) / (baseFee * baseFee)
        //   net = gross * (baseFee - tokenActionFeeRate) * (baseFee - treasuryActionFeeRate) / baseFeeSquared
        //
        // Solving for gross:
        //   gross = net * baseFeeSquared / ((baseFee - tokenActionFeeRate) * (baseFee - treasuryActionFeeRate))
        grossShares = Math.mulDiv(
            netShares,
            MAX_BPS_SQUARED,
            (MAX_BPS - tokenActionFeeRate) * (MAX_BPS - treasuryActionFeeRate),
            Math.Rounding.Ceil
        );
        sharesTokenFee =
            Math.min(Math.mulDiv(grossShares, tokenActionFeeRate, MAX_BPS, Math.Rounding.Ceil), grossShares - netShares);
        treasuryFee = grossShares - sharesTokenFee - netShares;

        return (grossShares, sharesTokenFee, treasuryFee);
    }

    /// @notice Computes the treasury action fee for a given action
    /// @param action Action to compute treasury action fee for
    /// @param shares Shares to compute treasury action fee for
    /// @return treasuryFee Treasury action fee amount in shares
    function _computeTreasuryFee(ExternalAction action, uint256 shares) internal view returns (uint256) {
        return Math.mulDiv(shares, getTreasuryActionFee(action), MAX_BPS, Math.Rounding.Ceil);
    }

    /// @notice Function that calculates how many shares to mint for the accrued management fee at the current timestamp
    /// @param token LeverageToken to calculate management fee shares for
    /// @param totalSupply Total supply of the LeverageToken
    /// @return shares Shares to mint
    function _getAccruedManagementFee(ILeverageToken token, uint256 totalSupply) internal view returns (uint256) {
        uint256 managementFee = getManagementFee(token);
        uint120 lastManagementFeeAccrualTimestamp = getLastManagementFeeAccrualTimestamp(token);

        uint256 duration = block.timestamp - lastManagementFeeAccrualTimestamp;

        uint256 sharesFee =
            Math.mulDiv(managementFee * totalSupply, duration, MAX_BPS * SECS_PER_YEAR, Math.Rounding.Ceil);
        return sharesFee;
    }

    /// @notice Sets the LeverageToken fee for a specific action
    /// @param token LeverageToken to set fee for
    /// @param action Action to set fee for
    /// @param fee Fee for action, 100_00 is 100%
    /// @dev If caller tries to set fee above 100% it reverts with FeeTooHigh error
    function _setLeverageTokenActionFee(ILeverageToken token, ExternalAction action, uint256 fee) internal {
        _validateActionFee(fee);

        _getFeeManagerStorage().tokenActionFee[token][action] = fee;
        emit LeverageTokenActionFeeSet(token, action, fee);
    }

    /// @notice Sets the management fee for a new LeverageToken and the last management fee accrual timestamp to the
    /// current timestamp
    /// @param token LeverageToken to set management fee for
    function _setNewLeverageTokenManagementFee(ILeverageToken token) internal {
        uint256 fee = _getFeeManagerStorage().defaultManagementFeeAtCreation;

        _getFeeManagerStorage().managementFee[token] = fee;
        _getFeeManagerStorage().lastManagementFeeAccrualTimestamp[token] = uint120(block.timestamp);
        emit ManagementFeeSet(token, fee);
    }

    /// @notice Sets the treasury address
    /// @param treasury Treasury address to set
    /// @dev Reverts if the treasury address is zero
    function _setTreasury(address treasury) internal {
        if (treasury == address(0)) {
            revert ZeroAddressTreasury();
        }

        _getFeeManagerStorage().treasury = treasury;
        emit TreasurySet(treasury);
    }

    /// @notice Validates that the fee is not higher than 99.99%
    /// @param fee Fee to validate
    function _validateActionFee(uint256 fee) internal pure {
        if (fee > MAX_ACTION_FEE) {
            revert FeeTooHigh(fee, MAX_ACTION_FEE);
        }
    }

    /// @notice Validates that the fee is not higher than 100%
    /// @param fee Fee to validate
    function _validateManagementFee(uint256 fee) internal pure {
        if (fee > MAX_MANAGEMENT_FEE) {
            revert FeeTooHigh(fee, MAX_MANAGEMENT_FEE);
        }
    }
}
