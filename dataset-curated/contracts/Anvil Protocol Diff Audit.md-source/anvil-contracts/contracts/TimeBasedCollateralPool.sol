// SPDX-License-Identifier: ISC
pragma solidity 0.8.25;

import "./interfaces/ICollateral.sol";
import "./interfaces/ITimeBasedCollateralPool.sol";
import "./Pricing.sol";
import "./interfaces/ICollateralPool.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @notice Defines a Collateral Pool contract that makes staked tokens available for claim by accounts with the
 * Claimant role. This contract is especially beneficial for claimants who frequently take on risk for some duration
 * during which staked collateral is guaranteed to be available for claim for a certain configurable duration (an epoch).
 *
 * This contract allows stakers to pool their collateral tokens such that they have a proportional amount of the overall
 * pool risk. Stakers are able to withdraw (release) their stake from the pool when their unstake vests at end of the
 * epoch following the one in which they unstake (`releaseEpoch` = `unstakeEpoch + 1`). Tokens are claimable up until
 * the point that they are eligible for release (in `releaseEpoch`).
 *
 * Note: this represents the first version of this contract and replaces the alpha deployed at 0xd042C267758eDDf34B481E1F539d637e41db3e5a.
 *
 * @custom:security-contact security@af.xyz
 */
contract TimeBasedCollateralPool is ITimeBasedCollateralPool, ICollateralPool, ERC165, AccessControl {
    using SafeERC20 for IERC20;

    /******************
     * CONTRACT STATE *
     ******************/

    bytes32 public constant ADMIN_ROLE = 0xa49807205ce4d355092ef5a8a18f56e8913cf4a201fbe287825b095693c21775; // keccak256("ADMIN_ROLE")
    bytes32 public constant CLAIM_ROUTER_ROLE = 0x9642b0ce4086cbdb0258c5d14b2ca081d0f79a110447a9cea56a25db41d615e8; // keccak256("CLAIM_ROUTER_ROLE")
    bytes32 public constant CLAIMANT_ROLE = 0xde60452b7e5ef525564a29469a0bce46dbce1bcfb88f883dcbd957a9cb50ddc6; // keccak256("CLAIMANT_ROLE")
    bytes32 public constant RESETTER_ROLE = 0x007d5786643ee140934c78e29f0883c40e3db9ce7b5c23251d35d01bbe838d47; // keccak256("RESETTER_ROLE")

    ICollateral public collateral;
    bool private initialized;
    uint256 public epochPeriodSeconds;
    uint256 public firstEpochStartTimeSeconds;

    address public defaultClaimDestinationAccount;
    mapping(IERC20 token => address claimDestinationOverride) public tokenClaimDestinationAccountOverrides;

    /// account address => token address => AccountState.
    /// Note: this is public but 3rd parties should not depend on the units fields to be accurate, as vested unstakes
    /// may be present. Use `getAccountPoolUnits(...)` instead if looking for up-to-date information on units.
    mapping(address account => mapping(address token => AccountState accountState)) internal accountTokenState;

    /// token address => ContractState.
    mapping(address token => ContractState contractState) internal tokenContractState;

    /// token address => epoch => ExitBalance. This contains the remaining units & tokens to exit for a specific epoch.
    /// This allows the contract to set an exchange rate from AccountState units to tokens for a specific epoch.
    mapping(address token => mapping(uint256 epoch => ExitBalance exitBalance)) internal tokenEpochExitBalances;

    /// token address => reset nonce => ExitBalance. This contains the remaining units & tokens to exit for a unit reset.
    /// See `resetPool(...)` for more information.
    mapping(address token => mapping(uint256 resetNonce => ExitBalance exitBalance)) internal tokenResetExitBalances;

    /// token address => reset nonce => epoch. This stores the epoch at which each token reset occurred. This is
    /// necessary to process unstakes across pool resets properly.
    mapping(address token => mapping(uint256 resetNonce => uint256 epochAtTimeOfReset)) public tokenResetEpoch;

    /***********
     * STRUCTS *
     ***********/

    struct AccountState {
        uint32 resetNonce;
        uint32 firstPendingUnstakeEpoch;
        uint32 secondPendingUnstakeEpoch;
        uint256 firstPendingUnstakeUnits;
        uint256 secondPendingUnstakeUnits;
        uint256 totalUnits;
    }

    struct ContractState {
        uint32 resetNonce;
        uint96 collateralReservationId;
        uint32 firstPendingUnstakeEpoch;
        uint32 secondPendingUnstakeEpoch;
        uint256 firstPendingUnstakeUnits;
        uint256 secondPendingUnstakeUnits;
        uint256 totalUnits;
    }

    /// ExitBalance is used to store tokens and units that are releasable for an epoch or reset nonce.
    struct ExitBalance {
        uint256 unitsLeft;
        uint256 tokensLeft;
    }

    /// PoolUnits is a breakdown of units, where `pendingUnstake` and `releasable` are mutually exclusive and `total` is
    /// the sum of staked, pending unstake, and releasable. Staked is not included here because it is derivable.
    struct PoolUnits {
        uint256 total;
        uint256 pendingUnstake;
        uint256 releasable;
    }

    /*************
     * MODIFIERS *
     *************/

    /**
     * Modifier to guarantee eligible account tokens are released ahead of an operation. This is required for any
     * operation that may modify account unit/token state to make sure resets are processed.
     * @param _account The account address for which eligible tokens will be released.
     * @param _tokenAddress The address of the ERC-20 token that will be released, if eligible.
     */
    modifier withEligibleAccountTokensReleased(address _account, address _tokenAddress) {
        _releaseEligibleAccountTokens(_account, _tokenAddress);

        _;
    }

    /****************
     * PUBLIC VIEWS *
     ****************/

    /**
     * @notice Calculates what the future ExitBalance would be at this moment, given the token and epoch.
     * @dev This assumes the caller can and will use the tokenEpochExitBalances mapping if an entry exists for the epoch
     * in question, so it operates on contract-level pending unstakes, assuming an entry does not exist.
     * @param _tokenAddress The address of the token for the ExitBalance.
     * @param _epoch The epoch of the ExitBalance.
     * @return _units The units of the ExitBalance, 0 if there is no pending unstake for the epoch in question.
     * @return _tokens The tokens of the ExitBalance, 0 if there is no pending unstake for the epoch in question.
     */
    function calculateEpochExitBalance(
        address _tokenAddress,
        uint256 _epoch
    ) public view returns (uint256 _units, uint256 _tokens) {
        ContractState storage contractState = tokenContractState[_tokenAddress];
        if (contractState.firstPendingUnstakeEpoch == _epoch) {
            _units = contractState.firstPendingUnstakeUnits;
            _tokens = collateral.getCollateralReservation(contractState.collateralReservationId).tokenAmount;
            _tokens = Pricing.calculateProportionOfTotal(_units, contractState.totalUnits, _tokens);
        } else if (contractState.secondPendingUnstakeEpoch == _epoch) {
            uint256 totalTokens = collateral
                .getCollateralReservation(contractState.collateralReservationId)
                .tokenAmount;
            uint256 totalUnits = contractState.totalUnits;

            uint256 firstUnits = contractState.firstPendingUnstakeUnits;
            _tokens = Pricing.calculateProportionOfTotal(firstUnits, totalUnits, totalTokens);

            _units = contractState.secondPendingUnstakeUnits;
            _tokens = Pricing.calculateProportionOfTotal(_units, totalUnits - firstUnits, totalTokens - _tokens);
        }
        // NB: default return (0,0)
    }

    /**
     * @notice Gets the account-level unstake units and tokens for the provided token, epoch, and unstake units.
     * @dev This will fetch the relevant information from the `tokenEpochExitBalances` mapping, and if it has not yet
     * been populated, will calculate what would be in that mapping using `calculateEpochExitBalance(...)` if told to do so.
     * @param _tokenAddress The address of the token of the unstake.
     * @param _epoch The epoch in question.
     * @param _unstakeUnits The units of the pending unstake.
     * @param _processContractUnstakes Whether or not the contract-level pending unstakes need to be calculated.
     * @return _units The units for the unstake in question, 0 if there is no unstake.
     * @return _tokens The tokens for the unstake in question. Note: 0 tokens but positive units is possible.
     */
    function getAccountExitUnitsAndTokens(
        address _tokenAddress,
        uint256 _epoch,
        uint256 _unstakeUnits,
        bool _processContractUnstakes
    ) public view returns (uint256 _units, uint256 _tokens) {
        uint256 exitUnits = tokenEpochExitBalances[_tokenAddress][_epoch].unitsLeft;
        if (exitUnits > 0) {
            _units = _unstakeUnits;
            _tokens = Pricing.calculateProportionOfTotal(
                _unstakeUnits,
                exitUnits,
                tokenEpochExitBalances[_tokenAddress][_epoch].tokensLeft
            );
        } else if (_processContractUnstakes) {
            uint256 exitTokens;
            (exitUnits, exitTokens) = calculateEpochExitBalance(_tokenAddress, _epoch);
            if (exitUnits > 0) {
                _units = _unstakeUnits;
                _tokens = Pricing.calculateProportionOfTotal(_unstakeUnits, exitUnits, exitTokens);
            }
        }
        // NB: default return (0,0)
    }

    /**
     * @inheritdoc ICollateralPool
     */
    function getAccountPoolBalance(
        address _accountAddress,
        address _tokenAddress
    ) external view returns (uint256 _balance) {
        AccountState memory accountState = accountTokenState[_accountAddress][_tokenAddress];

        uint256 accountUnitsLeft = accountState.totalUnits;

        bool accountWasReset = accountState.resetNonce < tokenContractState[_tokenAddress].resetNonce;
        // Calculate balance from processed contract-level unstakes.
        {
            uint256 vestedUnits;
            // NB: If reset, the epoch must be before the epoch of the reset to be stored in an epoch ExitBalance or
            // it could be an ExitBalance from a post-reset stake + unstake with a different unit value.
            uint256 unstakedIfBeforeEpoch = accountWasReset
                ? tokenResetEpoch[_tokenAddress][accountState.resetNonce]
                : getCurrentEpoch();
            uint256 epoch = accountState.firstPendingUnstakeEpoch;
            if (_nonZeroAndLessThan(epoch, unstakedIfBeforeEpoch)) {
                (vestedUnits, _balance) = getAccountExitUnitsAndTokens(
                    _tokenAddress,
                    epoch,
                    accountState.firstPendingUnstakeUnits,
                    false
                );
                epoch = accountState.secondPendingUnstakeEpoch;
                if (_nonZeroAndLessThan(epoch, unstakedIfBeforeEpoch)) {
                    (uint256 units, uint256 tokens) = getAccountExitUnitsAndTokens(
                        _tokenAddress,
                        epoch,
                        accountState.secondPendingUnstakeUnits,
                        false
                    );
                    vestedUnits += units;
                    _balance += tokens;
                }
            }

            accountUnitsLeft -= vestedUnits;
        }

        if (accountWasReset) {
            // The account has a reset to process. Add the account's share of the reset balance to _balance.
            ExitBalance memory exit = tokenResetExitBalances[_tokenAddress][accountState.resetNonce];
            _balance += Pricing.calculateProportionOfTotal(accountUnitsLeft, exit.unitsLeft, exit.tokensLeft);
        } else {
            // Add in balance from staked tokens. This includes vested pending unstakes without tokenEpochExitBalances
            // (not yet processed at the contract level).
            uint256 stakedBalance = collateral
                .getCollateralReservation(tokenContractState[_tokenAddress].collateralReservationId)
                .tokenAmount;
            _balance += Pricing.calculateProportionOfTotal(
                accountUnitsLeft,
                tokenContractState[_tokenAddress].totalUnits,
                stakedBalance
            );
        }
    }

    /**
     * @notice Calculates the total pool units at this point in time for the provided token address.
     * @dev Total units are those that are staked plus those that are releasable but have yet to be released.
     * @param _accountAddress The address of the account for which pool units are being requested.
     * @param _tokenAddress The address of the token for which account pool units are being requested.
     * @return _accountPoolUnits The PoolUnits object detailing total, pending unstake, and releasable units.
     */
    function getAccountPoolUnits(
        address _accountAddress,
        address _tokenAddress
    ) public view returns (PoolUnits memory _accountPoolUnits) {
        AccountState memory accountState = accountTokenState[_accountAddress][_tokenAddress];
        _accountPoolUnits.total = accountState.totalUnits;

        // If a pool reset has happened for this token, all units are releasable.
        if (accountState.resetNonce < tokenContractState[_tokenAddress].resetNonce) {
            _accountPoolUnits.releasable = _accountPoolUnits.total;
            return _accountPoolUnits;
        }

        uint256 currentEpoch = getCurrentEpoch();
        uint256 epoch = accountState.firstPendingUnstakeEpoch;
        if (_nonZeroAndLessThan(epoch, currentEpoch)) {
            (_accountPoolUnits.releasable, ) = getAccountExitUnitsAndTokens(
                _tokenAddress,
                epoch,
                accountState.firstPendingUnstakeUnits,
                true
            );
            epoch = accountState.secondPendingUnstakeEpoch;
            if (_nonZeroAndLessThan(epoch, currentEpoch)) {
                (uint256 units, ) = getAccountExitUnitsAndTokens(
                    _tokenAddress,
                    epoch,
                    accountState.secondPendingUnstakeUnits,
                    true
                );
                _accountPoolUnits.releasable += units;
            }
        }

        _accountPoolUnits.pendingUnstake =
            accountState.firstPendingUnstakeUnits +
            accountState.secondPendingUnstakeUnits -
            _accountPoolUnits.releasable;
    }

    /**
     * @notice Gets the accountTokenState entry for the provided account and token.
     * @param _account The account in question.
     * @param _tokenAddress The address of the token in question.
     * @return The AccountState for the provided account and token.
     */
    function getAccountTokenState(address _account, address _tokenAddress) public view returns (AccountState memory) {
        return accountTokenState[_account][_tokenAddress];
    }

    /**
     * @inheritdoc ITimeBasedCollateralPool
     */
    function getClaimableCollateral(
        IERC20[] calldata _tokens
    ) external view returns (ClaimableCollateral[] memory _claimableCollateral) {
        uint256 currentEpoch = getCurrentEpoch();
        uint256 endOfCurrentEpoch = getEpochEndTimestamp(currentEpoch);
        uint256 endOfNextEpoch = getEpochEndTimestamp(currentEpoch + 1);

        _claimableCollateral = new ClaimableCollateral[](_tokens.length);
        for (uint256 i = 0; i < _tokens.length; ++i) {
            address tokenAddress = address(_tokens[i]);

            _claimableCollateral[i].endOfCurrentEpochTimestampSeconds = endOfCurrentEpoch;
            _claimableCollateral[i].endOfNextEpochTimestampSeconds = endOfNextEpoch;

            ContractState storage contractState = tokenContractState[tokenAddress];
            uint256 totalUnits = contractState.totalUnits;
            if (totalUnits == 0) {
                // Nothing is claimable
                continue;
            }

            ICollateral.CollateralReservation memory reservation = collateral.getCollateralReservation(
                contractState.collateralReservationId
            );

            uint256 unitsUnstaked;
            uint256 secondEpoch = contractState.secondPendingUnstakeEpoch;
            uint256 firstEpoch = contractState.firstPendingUnstakeEpoch;

            for (uint256 epochAdjustment = 0; epochAdjustment < 2; ++epochAdjustment) {
                // claimable this epoch
                if (_nonZeroAndLessThan(secondEpoch, currentEpoch + epochAdjustment)) {
                    unitsUnstaked = contractState.firstPendingUnstakeUnits + contractState.secondPendingUnstakeUnits;
                } else if (_nonZeroAndLessThan(firstEpoch, currentEpoch + epochAdjustment)) {
                    unitsUnstaked = contractState.firstPendingUnstakeUnits;
                }

                uint256 claimable;
                uint256 tokensUnstaked = Pricing.calculateProportionOfTotal(
                    unitsUnstaked,
                    totalUnits,
                    reservation.tokenAmount
                );
                if (tokensUnstaked == 0) {
                    claimable = reservation.claimableTokenAmount;
                } else {
                    // NB: Need to calculate claimable amount from reserved amount because that's how CollateralVault does it.
                    // Otherwise truncation can cause off by one issues in which a higher claimable amount is advertised.
                    uint256 stakedAmountRemaining = reservation.tokenAmount - tokensUnstaked;
                    claimable = Pricing.amountBeforeFee(stakedAmountRemaining, reservation.feeBasisPoints);
                }
                if (epochAdjustment == 0) {
                    _claimableCollateral[i].amountClaimableUntilEndOfCurrentEpoch = claimable;
                } else {
                    _claimableCollateral[i].amountClaimableUntilEndOfNextEpoch = claimable;
                }
            }
        }
    }

    /**
     * @notice Gets the epoch number of the current epoch, according to this block's timestamp.
     * @return The current epoch.
     */
    function getCurrentEpoch() public view returns (uint256) {
        return ((block.timestamp - firstEpochStartTimeSeconds) / epochPeriodSeconds);
    }

    /**
     * @notice Gets the timestamp after which the current epoch ends.
     * @param _epoch The epoch for which the end timestamp is being returned.
     * @return The timestamp after which the current epoch ends.
     */
    function getEpochEndTimestamp(uint256 _epoch) public view returns (uint256) {
        return ((_epoch + 1) * epochPeriodSeconds) + firstEpochStartTimeSeconds - 1;
    }

    /**
     * @notice Calculates the pool units at this point in time for the provided token address.
     * @dev Total units are those that are staked plus those that are releasable but have yet to be released.
     * @param _tokenAddress The address of the token.
     * @return _poolUnits The PoolUnits object detailing total, pending unstake, and releasable units.
     */
    function getPoolUnits(address _tokenAddress) public view returns (PoolUnits memory _poolUnits) {
        ContractState storage contractState = tokenContractState[_tokenAddress];
        _poolUnits.total = contractState.totalUnits;

        uint256 currentEpoch = getCurrentEpoch();
        uint256 epoch = contractState.firstPendingUnstakeEpoch;
        if (_nonZeroAndLessThan(epoch, currentEpoch)) {
            epoch = contractState.secondPendingUnstakeEpoch;
            if (_nonZeroAndLessThan(epoch, currentEpoch)) {
                _poolUnits.releasable =
                    contractState.firstPendingUnstakeUnits +
                    contractState.secondPendingUnstakeUnits;
            } else {
                _poolUnits.releasable = contractState.firstPendingUnstakeUnits;
                if (epoch > 0) {
                    _poolUnits.pendingUnstake = contractState.secondPendingUnstakeUnits;
                }
            }
        } else {
            if (epoch > 0) {
                _poolUnits.pendingUnstake =
                    contractState.firstPendingUnstakeUnits +
                    contractState.secondPendingUnstakeUnits;
            }
        }
    }

    /**
     * @notice Gets the tokenContractState entry for the provided token.
     * @param _tokenAddress The address of the token in question.
     * @return The ContractState for the provided token.
     */
    function getTokenContractState(address _tokenAddress) public view returns (ContractState memory) {
        return tokenContractState[_tokenAddress];
    }

    /**
     * @notice Gets the tokenEpochExitBalances entry for the provided token and epoch.
     * @param _tokenAddress The address of the token in question.
     * @param _epoch The epoch in question.
     * @return _exitBalance The ExitBalance for the provided token and epoch.
     */
    function getTokenEpochExitBalance(address _tokenAddress, uint256 _epoch) public view returns (ExitBalance memory) {
        return tokenEpochExitBalances[_tokenAddress][_epoch];
    }

    /**
     * @notice Gets the tokenResetExitBalances entry for the provided token and reset nonce.
     * @param _tokenAddress The address of the token in question.
     * @param _resetNonce The reset nonce in question.
     * @return The ExitBalance for the provided token and reset nonce.
     */
    function getTokenResetExitBalance(
        address _tokenAddress,
        uint256 _resetNonce
    ) public view returns (ExitBalance memory) {
        return tokenResetExitBalances[_tokenAddress][_resetNonce];
    }

    /**
     * @notice Gets the total number of account-level units pending unstake for the account and token in question.
     * Note: this includes units for which the unstake has vested (releasable units).
     * @param _account The account for which the pending unstake units will be returned.
     * @param _tokenAddress The token for which the pending unstake units will be returned.
     * @return The total units pending unstake.
     */
    function getTotalAccountUnitsPendingUnstake(address _account, address _tokenAddress) public view returns (uint256) {
        uint256 firstUnits = accountTokenState[_account][_tokenAddress].firstPendingUnstakeUnits;
        if (firstUnits == 0) {
            return 0;
        }
        return firstUnits + accountTokenState[_account][_tokenAddress].secondPendingUnstakeUnits;
    }

    /**
     * @notice Gets the total number of contract-level units pending unstake for the token in question.
     * Note: this includes units for which the unstake has vested (releasable units).
     * @param _tokenAddress The token for which the pending unstake units will be returned.
     * @return The total number of units pending unstake.
     */
    function getTotalContractUnitsPendingUnstake(address _tokenAddress) public view returns (uint256) {
        uint256 firstUnits = tokenContractState[_tokenAddress].firstPendingUnstakeUnits;
        if (firstUnits == 0) {
            return 0;
        }
        return firstUnits + tokenContractState[_tokenAddress].secondPendingUnstakeUnits;
    }

    /**
     * Indicates support for IERC165, ICollateralPool, and ITimeBasedCollateralPool.
     * @inheritdoc IERC165
     */
    function supportsInterface(bytes4 interfaceID) public view override(ERC165, AccessControl) returns (bool) {
        return
            interfaceID == type(ICollateralPool).interfaceId ||
            interfaceID == type(ITimeBasedCollateralPool).interfaceId ||
            super.supportsInterface(interfaceID);
    }

    /*****************************
     * STATE-MODIFYING FUNCTIONS *
     *****************************/

    constructor() {
        // Make it so this contract can only be used via delegatecall.
        initialized = true;
    }

    /**
     * @notice Initializes a TimeBasedCollateralPool using the provided configuration parameters.
     * @dev Please take note of:
     *  - _epochPeriodSeconds and its implications for claimable collateral guarantee windows
     *  - RBAC roles defined at the top of this file and the corresponding addresses to be assigned those roles
     *
     * @param _collateral The ICollateral contract to use to access collateral.
     * @param _epochPeriodSeconds The number of seconds in each epoch. This is the minimum amount of time that staked
     * tokens will be claimable if an UnstakeInitiated event has not been observed for them.
     * @param _defaultClaimDestination The address to which tokens will be claimed if no token-based override is set.
     * @param _admin The address that will be granted the ADMIN_ROLE, allowing it to administer RBAC roles.
     * @param _claimant (optional) The address that will be granted the CLAIMANT_ROLE, allowing it to call `claim(...)`.
     * @param _claimRouter (optional) The address that will be granted the CLAIM_ROUTER_ROLE, allowing it to update
     * the defaultClaimDestinationAccount and tokenClaimDestinationAccountOverrides mapping.
     * @param _resetter (optional) The address that will be granted the RESETTER_ROLE, allowing it to call `reset(...)`.
     */
    function initialize(
        ICollateral _collateral,
        uint256 _epochPeriodSeconds,
        address _defaultClaimDestination,
        address _admin,
        address _claimant,
        address _claimRouter,
        address _resetter
    ) public {
        if (initialized) revert AlreadyInitialized();
        initialized = true;

        if (_epochPeriodSeconds == 0) revert InvalidZeroAmount();
        if (_defaultClaimDestination == address(0)) revert InvalidZeroAddress();
        if (_admin == address(0)) revert InvalidZeroAddress();
        // NB: all other parameter addresses may be zero, as admin can set them later.

        firstEpochStartTimeSeconds = block.timestamp;
        collateral = _collateral;
        epochPeriodSeconds = _epochPeriodSeconds;

        defaultClaimDestinationAccount = _defaultClaimDestination;

        _setRoleAdmin(ADMIN_ROLE, ADMIN_ROLE);
        _grantRole(ADMIN_ROLE, _admin);

        _setRoleAdmin(CLAIMANT_ROLE, ADMIN_ROLE);
        if (_claimant != address(0)) {
            _grantRole(CLAIMANT_ROLE, _claimant);
        }

        _setRoleAdmin(CLAIM_ROUTER_ROLE, ADMIN_ROLE);
        if (_claimRouter != address(0)) {
            _grantRole(CLAIM_ROUTER_ROLE, _claimRouter);
        }

        _setRoleAdmin(RESETTER_ROLE, ADMIN_ROLE);
        if (_resetter != address(0)) {
            _grantRole(RESETTER_ROLE, _resetter);
        }
    }

    /**
     * @inheritdoc ITimeBasedCollateralPool
     */
    function claim(IERC20[] calldata _tokens, uint256[] calldata _amounts) external onlyRole(CLAIMANT_ROLE) {
        if (_tokens.length != _amounts.length) revert RelatedArraysLengthMismatch(_tokens.length, _amounts.length);

        for (uint256 i = 0; i < _tokens.length; ++i) {
            uint256 amount = _amounts[i];
            if (amount == 0) {
                // we could revert, but there may be some valid claims.
                continue;
            }
            address tokenAddress = address(_tokens[i]);

            {
                bool poolWasReset = _unlockEligibleTokenContractPendingUnstakes(tokenAddress);
                if (poolWasReset) {
                    revert InsufficientClaimable(amount, 0);
                }
            }

            address destinationAccount = tokenClaimDestinationAccountOverrides[_tokens[i]];
            if (destinationAccount == address(0)) {
                destinationAccount = defaultClaimDestinationAccount;
            }

            (uint256 remainingReserved, ) = collateral.claimCollateral(
                tokenContractState[tokenAddress].collateralReservationId,
                amount,
                destinationAccount,
                false // NB: never intentionally release remainder. It will be released if 0 claimable remains.
            );
            emit CollateralClaimed(IERC20(tokenAddress), amount, destinationAccount);

            // If the whole amount is claimed, units are worthless, so we need to delete them on next account action.
            if (remainingReserved == 0) {
                tokenContractState[tokenAddress].collateralReservationId = 0;
                _resetPool(tokenAddress);
            }
        }
    }

    /**
     * @inheritdoc ITimeBasedCollateralPool
     */
    function depositAndStake(
        IERC20 _token,
        uint256 _amount,
        bytes calldata _collateralizableDepositApprovalSignature
    ) external withEligibleAccountTokensReleased(msg.sender, address(_token)) returns (uint256) {
        try
            collateral.depositFromAccount(
                msg.sender,
                address(_token),
                _amount,
                _collateralizableDepositApprovalSignature
            )
        {} catch (bytes memory reason) {
            if (bytes4(reason) != ICollateral.InvalidSignature.selector) {
                // Revert with the original error message
                assembly ("memory-safe") {
                    revert(add(reason, 0x20), mload(reason))
                }
            }
            // If it reverts for signature reasons, we do not want to let the transaction revert [yet].
        }

        return _stake(_token, _amount);
    }

    /**
     * @inheritdoc ITimeBasedCollateralPool
     */
    function releaseEligibleTokens(address _account, IERC20[] calldata _tokens) external {
        for (uint256 i = 0; i < _tokens.length; ++i) {
            _releaseEligibleAccountTokens(_account, address(_tokens[i]));
        }
    }

    /**
     * @inheritdoc ITimeBasedCollateralPool
     */
    function resetPool(IERC20[] calldata _tokens) external onlyRole(RESETTER_ROLE) {
        for (uint256 i = 0; i < _tokens.length; ++i) {
            _resetPool(address(_tokens[i]));
        }
    }

    /**
     * @inheritdoc ITimeBasedCollateralPool
     */
    function setDefaultClaimDestinationAccount(
        address _defaultClaimDestinationAccount
    ) external onlyRole(CLAIM_ROUTER_ROLE) {
        if (_defaultClaimDestinationAccount == address(0)) revert InvalidZeroAddress();
        address oldAccount = defaultClaimDestinationAccount;
        defaultClaimDestinationAccount = _defaultClaimDestinationAccount;
        emit DefaultClaimDestinationAccountUpdated(oldAccount, _defaultClaimDestinationAccount);
    }

    /**
     * @inheritdoc ITimeBasedCollateralPool
     */
    function setTokenClaimDestinationAccountOverride(
        IERC20 _token,
        address _destinationAccount
    ) external onlyRole(CLAIM_ROUTER_ROLE) {
        address oldAccount = tokenClaimDestinationAccountOverrides[_token];
        tokenClaimDestinationAccountOverrides[_token] = _destinationAccount;
        emit TokenClaimDestinationAccountOverrideUpdated(_token, oldAccount, _destinationAccount);
    }

    /**
     * @inheritdoc ITimeBasedCollateralPool
     */
    function stake(
        IERC20 _token,
        uint256 _amount,
        bytes calldata _collateralizableApprovalSignature
    ) external withEligibleAccountTokensReleased(msg.sender, address(_token)) returns (uint256) {
        if (_collateralizableApprovalSignature.length > 0) {
            _tryModifyCollateralizableAllowanceWithSignature(
                address(_token),
                Pricing.safeCastToInt256(_amount),
                _collateralizableApprovalSignature
            );
        }

        return _stake(_token, _amount);
    }

    /**
     * @inheritdoc ITimeBasedCollateralPool
     */
    function stakeReleasableTokensFrom(
        ITimeBasedCollateralPool _pool,
        IERC20 _token,
        uint256 _amount,
        bytes calldata _collateralizableApprovalSignature
    ) external withEligibleAccountTokensReleased(msg.sender, address(_token)) returns (uint256) {
        if (address(_pool) != address(this)) {
            IERC20[] memory tokens = new IERC20[](1);
            tokens[0] = _token;
            _pool.releaseEligibleTokens(msg.sender, tokens);
        }
        if (_collateralizableApprovalSignature.length > 0) {
            _tryModifyCollateralizableAllowanceWithSignature(
                address(_token),
                Pricing.safeCastToInt256(_amount),
                _collateralizableApprovalSignature
            );
        }

        return _stake(_token, _amount);
    }

    /**
     * @inheritdoc ITimeBasedCollateralPool
     */
    function unstake(IERC20 _token, uint256 _poolUnits) external {
        if (_poolUnits == 0) revert UnstakeAmountZero();

        address tokenAddress = address(_token);

        if (
            accountTokenState[msg.sender][tokenAddress].totalUnits -
                getTotalAccountUnitsPendingUnstake(msg.sender, tokenAddress) <
            _poolUnits
        ) {
            revert InsufficientBalance(
                _poolUnits,
                accountTokenState[msg.sender][tokenAddress].totalUnits -
                    getTotalAccountUnitsPendingUnstake(msg.sender, tokenAddress)
            );
        }

        {
            // Release eligible account tokens. If a reset occurred, there is nothing left to unstake, so return.
            bool accountWasReset = _releaseEligibleAccountTokens(msg.sender, tokenAddress);
            if (accountWasReset) {
                // Do not revert because the user wanted tokens unstaked, and those were unstaked and released.
                return;
            }
        }

        _addToAccountPendingUnstakeNextEpoch(tokenAddress, msg.sender, _poolUnits);
        _addToContractPendingUnstakeNextEpoch(tokenAddress, _poolUnits);

        emit UnstakeInitiated(msg.sender, _token, _poolUnits, getEpochEndTimestamp(getCurrentEpoch() + 1));
    }

    /********************************
     * PRIVATE / INTERNAL FUNCTIONS *
     ********************************/

    /**
     * @dev Finds the entry for the provided token and account that corresponds to the epoch following the current epoch
     * in the `accountTokenState` mapping and adds the provided pool units to it.
     * NOTE: This assumes that vested pending unstakes for the account and token in question were processed within this
     * transaction prior to this call.
     * @param _tokenAddress The address of the ERC-20 token for the pending unstake.
     * @param _account The account address for the pending unstake.
     * @param _unstakeUnitsToAdd The number of units to add to the pending unstake for next epoch.
     */
    function _addToAccountPendingUnstakeNextEpoch(
        address _tokenAddress,
        address _account,
        uint256 _unstakeUnitsToAdd
    ) internal {
        AccountState storage state = accountTokenState[_account][_tokenAddress];

        uint32 epoch = uint32(getCurrentEpoch() + 1);

        uint32 firstUnstakeEpoch = state.firstPendingUnstakeEpoch;
        if (firstUnstakeEpoch == 0) {
            state.firstPendingUnstakeEpoch = epoch;
            state.firstPendingUnstakeUnits = _unstakeUnitsToAdd;
            return;
        }

        if (firstUnstakeEpoch == epoch) {
            state.firstPendingUnstakeUnits += _unstakeUnitsToAdd;
            return;
        }

        if (state.secondPendingUnstakeEpoch == epoch) {
            state.secondPendingUnstakeUnits += _unstakeUnitsToAdd;
        } else {
            state.secondPendingUnstakeEpoch = epoch;
            state.secondPendingUnstakeUnits = _unstakeUnitsToAdd;
        }
    }

    /**
     * @dev Finds the entry for the provided token that corresponds to the epoch following the current epoch in the
     * `tokenContractState` mapping and adds the provided pool units to it.
     * NOTE: This assumes that `_unlockEligibleTokenContractPendingUnstakes(...)` was invoked within this transaction prior to this call.
     * @param _tokenAddress The address of the ERC-20 token for the pending unstake.
     * @param _unstakeUnitsToAdd The number of units to add to the pending unstake for next epoch.
     */
    function _addToContractPendingUnstakeNextEpoch(address _tokenAddress, uint256 _unstakeUnitsToAdd) internal {
        ContractState storage state = tokenContractState[_tokenAddress];

        uint32 epoch = uint32(getCurrentEpoch() + 1);

        uint32 firstUnstakeEpoch = state.firstPendingUnstakeEpoch;
        if (firstUnstakeEpoch == 0) {
            state.firstPendingUnstakeEpoch = epoch;
            state.firstPendingUnstakeUnits = _unstakeUnitsToAdd;
            return;
        }

        if (firstUnstakeEpoch == epoch) {
            state.firstPendingUnstakeUnits += _unstakeUnitsToAdd;
            return;
        }

        if (state.secondPendingUnstakeEpoch == epoch) {
            state.secondPendingUnstakeUnits += _unstakeUnitsToAdd;
        } else {
            state.secondPendingUnstakeEpoch = epoch;
            state.secondPendingUnstakeUnits = _unstakeUnitsToAdd;
        }
    }

    /**
     * Returns true if the provided number is non-zero and less than the number to compare to.
     * @param _numberToCheck The number being evaluated.
     * @param _numberToCompareTo The number that _numberToCheck is evaluated against.
     * @return True if _numberToCheck is non-zero and less than _numberToCompareTo, false otherwise.
     */
    function _nonZeroAndLessThan(uint256 _numberToCheck, uint256 _numberToCompareTo) private pure returns (bool) {
        return _numberToCheck > 0 && _numberToCheck < _numberToCompareTo;
    }

    /**
     * @dev Gets the releasable units and tokens for the provided account and token by processing its pending unstakes.
     * NOTE: THIS FUNCTION UPDATES THE STATE. CALLER MUST RELEASE THE RETURNED UNITS & TOKENS OR REVERT.
     * NOTE: This function assumes that contract-level unstakes have already been processed within this transaction.
     * @param _account The address of the account in question.
     * @param _tokenAddress The address of the token in question.
     * @return _unitsToRelease The number of units to release from processing pending unstakes.
     * @return _tokensToRelease The number of tokens to release from processing pending unstakes.
     */
    function _processAccountTokenUnstakes(
        address _account,
        address _tokenAddress
    ) internal returns (uint256 _unitsToRelease, uint256 _tokensToRelease) {
        AccountState storage accountStateStorage = accountTokenState[_account][_tokenAddress];
        uint256 epoch = accountStateStorage.firstPendingUnstakeEpoch;
        if (epoch == 0) {
            return (0, 0);
        }

        uint256 currentEpoch = getCurrentEpoch();
        if (epoch >= currentEpoch) {
            return (0, 0);
        }

        // NB: contract-level unstakes were already processed, so do not reprocess.
        (_unitsToRelease, _tokensToRelease) = getAccountExitUnitsAndTokens(
            _tokenAddress,
            epoch,
            accountStateStorage.firstPendingUnstakeUnits,
            false
        );

        /** Update epoch-exit state **/
        tokenEpochExitBalances[_tokenAddress][epoch].unitsLeft -= _unitsToRelease;
        tokenEpochExitBalances[_tokenAddress][epoch].tokensLeft -= _tokensToRelease;

        epoch = accountStateStorage.secondPendingUnstakeEpoch;
        if (_nonZeroAndLessThan(epoch, currentEpoch)) {
            // Process 2nd unstake
            (uint256 vestedUnits, uint256 vestedTokens) = getAccountExitUnitsAndTokens(
                _tokenAddress,
                epoch,
                accountStateStorage.secondPendingUnstakeUnits,
                false
            );
            _unitsToRelease += vestedUnits;
            _tokensToRelease += vestedTokens;

            tokenEpochExitBalances[_tokenAddress][epoch].unitsLeft -= vestedUnits;
            tokenEpochExitBalances[_tokenAddress][epoch].tokensLeft -= vestedTokens;

            accountStateStorage.firstPendingUnstakeEpoch = 0;
            accountStateStorage.secondPendingUnstakeEpoch = 0;
            accountStateStorage.firstPendingUnstakeUnits = 0;
            accountStateStorage.secondPendingUnstakeUnits = 0;
        } else if (epoch > 0) {
            // a second unstake exists; it's just not vested.
            accountStateStorage.firstPendingUnstakeEpoch = uint32(epoch);
            accountStateStorage.secondPendingUnstakeEpoch = 0;
            accountStateStorage.firstPendingUnstakeUnits = accountTokenState[_account][_tokenAddress]
                .secondPendingUnstakeUnits;
            accountStateStorage.secondPendingUnstakeUnits = 0;
        } else {
            // there is only 1 unstake.
            accountStateStorage.firstPendingUnstakeEpoch = 0;
            accountStateStorage.firstPendingUnstakeUnits = 0;
        }
        accountStateStorage.totalUnits -= _unitsToRelease;
    }

    /**
     * @dev Releases all vested unstakes from the `accountTokenState` struct for the provided token and account.
     * @param _account The address of the account for which vested unstakes will be released.
     * @param _tokenAddress The address of the ERC-20 token to be released.
     * @return _accountWasReset Whether or not the account was reset as a result of this call.
     */
    function _releaseEligibleAccountTokens(
        address _account,
        address _tokenAddress
    ) internal returns (bool _accountWasReset) {
        _accountWasReset = _unlockEligibleTokenContractPendingUnstakes(_tokenAddress);

        (uint256 totalUnitsToRelease, uint256 totalTokensToRelease) = _resetAccountTokenStateIfApplicable(
            _account,
            _tokenAddress
        );

        if (totalUnitsToRelease == 0) {
            (uint256 units, uint256 tokens) = _processAccountTokenUnstakes(_account, _tokenAddress);
            totalUnitsToRelease += units;
            totalTokensToRelease += tokens;
        } else {
            _accountWasReset = true;
        }

        if (totalUnitsToRelease == 0) {
            return _accountWasReset;
        }

        collateral.transferCollateral(_tokenAddress, totalTokensToRelease, _account);

        emit CollateralReleased(IERC20(_tokenAddress), totalTokensToRelease, totalUnitsToRelease, _account);
    }

    /**
     * @dev Gets the releasable units and tokens for the provided account and token by processing a pool token reset
     * if there is one.
     * NOTE: THIS FUNCTION UPDATES THE STATE. CALLER MUST RELEASE THE RETURNED UNITS & TOKENS OR REVERT.
     * @param _account The address of the account in question.
     * @param _tokenAddress The address of the token in question.
     * @return _unitsToRelease The number of units to release from processing a pool token reset.
     * @return _tokensToRelease The number of tokens to release from processing a pool token reset.
     */
    function _resetAccountTokenStateIfApplicable(
        address _account,
        address _tokenAddress
    ) internal returns (uint256 _unitsToRelease, uint256 _tokensToRelease) {
        uint32 accountResetNonce = accountTokenState[_account][_tokenAddress].resetNonce;
        uint32 contractResetNonce = tokenContractState[_tokenAddress].resetNonce;
        if (accountResetNonce >= contractResetNonce) {
            // There is no account reset to process.
            return (0, 0);
        }

        // If we got here, the pool has been reset for this token and account.
        AccountState storage accountStateStorage = accountTokenState[_account][_tokenAddress];
        // 1. Update account reset nonce so it is up to date.
        accountStateStorage.resetNonce = contractResetNonce;
        emit AccountResetNonceUpdated(_account, accountResetNonce, contractResetNonce);

        _unitsToRelease = accountStateStorage.totalUnits;
        if (_unitsToRelease == 0) {
            return (0, 0);
        }
        // Reset total units.
        accountStateStorage.totalUnits = 0;

        // 2. Process and purge all account pending unstake state. There are two possibilities:
        //      a. A pending unstake is vested or unvested but no vested contract unstake was processed prior to pool
        //         reset. That contract state was purged in _resetPool(...), the account pool units still exist in the
        //         vault, and we can release them via the standard "everything has been unstaked" logic below.
        //      b. A pending unstake was vested and the contract unstake was already processed at the time of pool reset.
        //         In this case, the exchange rate was captured in tokenEpochExitBalances, and it's unsafe to process
        //         this unstake any different than the standard release process.
        uint256 unstakeUnitsToRelease;
        {
            uint256 epoch = accountStateStorage.firstPendingUnstakeEpoch;
            if (epoch > 0) {
                // NB: If reset, the epoch must be before the epoch of the reset to be stored in an epoch ExitBalance or
                // it could be an ExitBalance from a post-reset stake + unstake with a different unit value.
                uint256 epochAtTimeOfReset = tokenResetEpoch[_tokenAddress][accountResetNonce];
                if (epoch < epochAtTimeOfReset) {
                    // NB: This is case b. from above -- do not process contract-level unstakes that have not already been processed.
                    (unstakeUnitsToRelease, _tokensToRelease) = getAccountExitUnitsAndTokens(
                        _tokenAddress,
                        epoch,
                        accountStateStorage.firstPendingUnstakeUnits,
                        false
                    );
                    if (unstakeUnitsToRelease > 0) {
                        ExitBalance storage exitBalance = tokenEpochExitBalances[_tokenAddress][epoch];
                        exitBalance.unitsLeft -= unstakeUnitsToRelease;
                        exitBalance.tokensLeft -= _tokensToRelease;
                    }
                    epoch = accountStateStorage.secondPendingUnstakeEpoch;
                    if (_nonZeroAndLessThan(epoch, epochAtTimeOfReset)) {
                        (uint256 units, uint256 tokens) = getAccountExitUnitsAndTokens(
                            _tokenAddress,
                            epoch,
                            accountStateStorage.secondPendingUnstakeUnits,
                            false
                        );
                        if (units > 0) {
                            ExitBalance storage exitBalance = tokenEpochExitBalances[_tokenAddress][epoch];
                            exitBalance.unitsLeft -= units;
                            exitBalance.tokensLeft -= tokens;
                        }
                        unstakeUnitsToRelease += units;
                        _tokensToRelease += tokens;
                    }
                }

                accountStateStorage.firstPendingUnstakeEpoch = 0;
                accountStateStorage.secondPendingUnstakeEpoch = 0;

                accountStateStorage.firstPendingUnstakeUnits = 0;
                accountStateStorage.secondPendingUnstakeUnits = 0;
            }
        }

        // 3. Process reset exit units.
        if (_unitsToRelease == unstakeUnitsToRelease) {
            // If we got here, it means that all units were handled above.
            return (_unitsToRelease, _tokensToRelease);
        }
        // _unitsToRelease includes pending unstakes above, so we need to remove them to process reset.
        uint256 accountResetUnits = _unitsToRelease - unstakeUnitsToRelease;

        uint256 exitTokensLeft = tokenResetExitBalances[_tokenAddress][accountResetNonce].tokensLeft;
        // If there are no tokens left, we're releasing all account units for zero tokens. No need to do the math.
        if (exitTokensLeft > 0) {
            uint256 exitUnitsLeft = tokenResetExitBalances[_tokenAddress][accountResetNonce].unitsLeft;

            // accountResetTokens / exitTokensLeft = accountResetUnits / exitUnitsLeft
            uint256 accountResetTokens = Pricing.calculateProportionOfTotal(
                accountResetUnits,
                exitUnitsLeft,
                exitTokensLeft
            );
            _tokensToRelease += accountResetTokens;
            if (accountResetTokens == exitTokensLeft) {
                delete tokenResetExitBalances[_tokenAddress][accountResetNonce];
            } else {
                tokenResetExitBalances[_tokenAddress][accountResetNonce].tokensLeft =
                    exitTokensLeft -
                    accountResetTokens;
                tokenResetExitBalances[_tokenAddress][accountResetNonce].unitsLeft = exitUnitsLeft - accountResetUnits;
            }
        }
    }

    /**
     * @notice Exact same as the similarly-named external function except operates on a single token.
     */
    function _resetPool(address _tokenAddress) internal {
        // Note: we are not calling _unlockEligibleTokenContractPendingUnstakes because it can call this function.

        ContractState storage contractStateStorage = tokenContractState[_tokenAddress];

        uint256 unitsToReset = contractStateStorage.totalUnits;
        if (unitsToReset == 0) {
            // This already has the state that a reset would achieve, so it's not required.
            return;
        }

        // NB: must be resetNonce++, NOT ++resetNonce
        uint256 resetNonce = contractStateStorage.resetNonce++;

        uint256 tokensToReset;
        {
            uint96 reservationId = contractStateStorage.collateralReservationId;
            if (reservationId != 0) {
                // Unlock all pool tokens so they are releasable.
                tokensToReset = collateral.releaseAllCollateral(reservationId);
                contractStateStorage.collateralReservationId = 0;
            }
        }

        // Only set an Exit balance if there is one. If all tokens were claimed, then effectively set (0,0).
        if (tokensToReset > 0) {
            // Create the reset ExitBalance so stakers can exit their tokens (see: _resetAccountTokenStateIfApplicable(...))
            tokenResetExitBalances[_tokenAddress][resetNonce] = ExitBalance(unitsToReset, tokensToReset);
        }
        tokenResetEpoch[_tokenAddress][resetNonce] = getCurrentEpoch();

        // Delete all contract-level pending unstake state.
        if (contractStateStorage.firstPendingUnstakeEpoch > 0) {
            contractStateStorage.firstPendingUnstakeEpoch = 0;
            contractStateStorage.firstPendingUnstakeUnits = 0;

            if (contractStateStorage.secondPendingUnstakeEpoch > 0) {
                contractStateStorage.secondPendingUnstakeEpoch = 0;
                contractStateStorage.secondPendingUnstakeUnits = 0;
            }
        }

        contractStateStorage.totalUnits = 0;

        emit PoolReset(IERC20(_tokenAddress), resetNonce + 1, tokensToReset, unitsToReset);
    }

    /**
     * @notice Internal function to pool collateral and stake.
     * @dev Note: that this function requires the collateral has already been received and properly associated with this
     * contract within the ICollateral contract.
     * NOTE: This assumes that all eligible account and contract level unstakes and resets have been processed
     * prior to calling this function.
     * @param _token The ERC-20 token to pool and stake.
     * @param _amount The amount of the ERC-20 token to pool and stake.
     */
    function _stake(IERC20 _token, uint256 _amount) internal returns (uint256 _poolUnitsIssued) {
        if (_amount == 0) revert InvalidZeroAmount();

        collateral.poolCollateral(msg.sender, address(_token), _amount);

        uint96 reservationId = tokenContractState[address(_token)].collateralReservationId;
        uint256 poolTotalUnitsAfter;
        uint256 poolTotalTokensAfter;
        if (reservationId == 0) {
            _poolUnitsIssued = _amount;
            (reservationId, ) = collateral.reserveCollateral(address(this), address(_token), _amount);
            tokenContractState[address(_token)].collateralReservationId = reservationId;
            tokenContractState[address(_token)].totalUnits = _poolUnitsIssued;
            accountTokenState[msg.sender][address(_token)].totalUnits = _poolUnitsIssued;

            poolTotalUnitsAfter = _poolUnitsIssued;
            poolTotalTokensAfter = _amount;
        } else {
            (poolTotalTokensAfter, ) = collateral.modifyCollateralReservation(
                reservationId,
                Pricing.safeCastToInt256(_amount)
            );
            uint256 poolUnits = tokenContractState[address(_token)].totalUnits;
            _poolUnitsIssued = Pricing.calculateProportionOfTotal(_amount, poolTotalTokensAfter - _amount, poolUnits);

            poolTotalUnitsAfter = poolUnits + _poolUnitsIssued;

            tokenContractState[address(_token)].totalUnits = poolTotalUnitsAfter;
            accountTokenState[msg.sender][address(_token)].totalUnits += _poolUnitsIssued;
        }

        {
            uint256 product;
            unchecked {
                product = (poolTotalTokensAfter * poolTotalUnitsAfter) / poolTotalUnitsAfter;
            }
            // This means that the contract will not be able to process withdrawals without overflowing, so must revert.
            // This can happen because the pool is empty, but the number of tokens being deposited is > 2**128 - 1
            // or if pool units have been diluted enough to make the units issued for this deposit very large.
            // If the latter, the pool should be reset.
            if (product != poolTotalTokensAfter) revert DepositTooLarge();
        }

        emit CollateralStaked(msg.sender, _token, _amount, _poolUnitsIssued);
    }

    /**
     * @dev attempts to modify the collateralizable allowance of the msg.sender with the provided signature without
     * reverting if that call fails.
     * @param _collateralTokenAddress The collateral token for which the allowance is being modified.
     * @param _collateralTokenAmount The signed amount by which the allowance should be modified (positive for increase, negative for decrease).
     * @param _collateralizableAllowanceSignature The signature of the msg.sender approving this allowance adjustment.
     */
    function _tryModifyCollateralizableAllowanceWithSignature(
        address _collateralTokenAddress,
        int256 _collateralTokenAmount,
        bytes calldata _collateralizableAllowanceSignature
    ) private {
        try
            collateral.modifyCollateralizableTokenAllowanceWithSignature(
                msg.sender,
                address(this),
                _collateralTokenAddress,
                _collateralTokenAmount,
                _collateralizableAllowanceSignature
            )
        {} catch (bytes memory reason) {
            if (bytes4(reason) != ICollateral.InvalidSignature.selector) {
                // Revert with the original error message
                assembly ("memory-safe") {
                    revert(add(reason, 0x20), mload(reason))
                }
            }
            // If it reverts for signature reasons, we do not want to let the transaction revert [yet].
        }
    }

    /**
     * @dev Removes applicable units and tokens from contract-level unstake state for the provided token address
     * creating entries in the tokenEpochExitBalances mapping as applicable.
     * This may end up resetting the pool for the token in question if processing pending unstakes leaves the associated
     * CollateralReservation in a state in which it has collateral but none is claimable. See try/catch below.
     * @param _tokenAddress The address of the ERC-20 token to be released.
     * @return Whether or not the pool was reset as a result of this call.
     */
    function _unlockEligibleTokenContractPendingUnstakes(address _tokenAddress) internal returns (bool) {
        ContractState storage contractStateStorage = tokenContractState[_tokenAddress];
        uint256 currentEpoch = getCurrentEpoch();
        uint256 firstEpoch = contractStateStorage.firstPendingUnstakeEpoch;
        if (firstEpoch == 0 || firstEpoch >= currentEpoch) {
            return false;
        }

        uint256 totalPoolUnits = contractStateStorage.totalUnits;
        uint256 stakedPoolTokens = collateral
            .getCollateralReservation(tokenContractState[_tokenAddress].collateralReservationId)
            .tokenAmount;

        uint256 firstVestedUnits = contractStateStorage.firstPendingUnstakeUnits;
        uint256 firstVestedTokens = Pricing.calculateProportionOfTotal(
            firstVestedUnits,
            totalPoolUnits,
            stakedPoolTokens
        );

        uint256 secondVestedUnits;
        uint256 secondVestedTokens;
        uint256 secondEpoch = contractStateStorage.secondPendingUnstakeEpoch;
        if (_nonZeroAndLessThan(secondEpoch, currentEpoch)) {
            secondVestedUnits = contractStateStorage.secondPendingUnstakeUnits;
            secondVestedTokens = Pricing.calculateProportionOfTotal(
                secondVestedUnits,
                totalPoolUnits - firstVestedUnits,
                stakedPoolTokens - firstVestedTokens
            );
        }

        if ((firstVestedUnits + secondVestedUnits) == totalPoolUnits) {
            collateral.releaseAllCollateral(contractStateStorage.collateralReservationId);
            contractStateStorage.collateralReservationId = 0;
        } else {
            uint256 tokensToRelease = firstVestedTokens + secondVestedTokens;
            if (tokensToRelease > 0) {
                try
                    collateral.modifyCollateralReservation(
                        contractStateStorage.collateralReservationId,
                        -Pricing.safeCastToInt256(tokensToRelease)
                    )
                {} catch (bytes memory reason) {
                    if (bytes4(reason) == ICollateral.ClaimableAmountZero.selector) {
                        // If we're here, it means that the result of lowering the collateral amount is a reservation with
                        // 0 claimable balance. The only way to get this collateral out is to release less or more. Less
                        // invalidates the unstaking logic, so we choose to release more, resetting the dust that remains.
                        _resetPool(_tokenAddress);
                        return true;
                    } else {
                        assembly {
                            revert(add(reason, 0x20), mload(reason))
                        }
                    }
                }
            }
        }

        /*** Update storage to "process" the vested unstakes ***/

        tokenEpochExitBalances[_tokenAddress][firstEpoch] = ExitBalance(firstVestedUnits, firstVestedTokens);

        contractStateStorage.totalUnits = totalPoolUnits - (firstVestedUnits + secondVestedUnits);

        emit UnstakeProcessed(
            IERC20(_tokenAddress),
            firstVestedUnits + secondVestedUnits,
            firstVestedTokens + secondVestedTokens
        );

        if (secondVestedUnits == 0) {
            if (secondEpoch > 0) {
                contractStateStorage.firstPendingUnstakeEpoch = uint32(secondEpoch);
                contractStateStorage.secondPendingUnstakeEpoch = 0;
                contractStateStorage.firstPendingUnstakeUnits = contractStateStorage.secondPendingUnstakeUnits;
                contractStateStorage.secondPendingUnstakeUnits = 0;
                return false;
            }

            contractStateStorage.firstPendingUnstakeEpoch = 0;
            contractStateStorage.firstPendingUnstakeUnits = 0;
            return false;
        }

        // If we got here, there were 2 vested unstakes.

        tokenEpochExitBalances[_tokenAddress][secondEpoch] = ExitBalance(secondVestedUnits, secondVestedTokens);

        contractStateStorage.firstPendingUnstakeEpoch = 0;
        contractStateStorage.secondPendingUnstakeEpoch = 0;
        contractStateStorage.firstPendingUnstakeUnits = 0;
        contractStateStorage.secondPendingUnstakeUnits = 0;

        return false;
    }
}
