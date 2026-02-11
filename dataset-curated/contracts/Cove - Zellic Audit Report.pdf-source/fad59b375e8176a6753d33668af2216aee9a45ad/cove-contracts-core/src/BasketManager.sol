// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { AccessControlEnumerable } from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { ReentrancyGuardTransient } from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import { EulerRouter } from "euler-price-oracle/src/EulerRouter.sol";

import { AssetRegistry } from "src/AssetRegistry.sol";
import { BasketToken } from "src/BasketToken.sol";
import { FeeCollector } from "src/FeeCollector.sol";
import { BasketManagerUtils } from "src/libraries/BasketManagerUtils.sol";
import { Errors } from "src/libraries/Errors.sol";
import { StrategyRegistry } from "src/strategies/StrategyRegistry.sol";
import { WeightStrategy } from "src/strategies/WeightStrategy.sol";
import { TokenSwapAdapter } from "src/swap_adapters/TokenSwapAdapter.sol";
import { BasketManagerStorage, RebalanceStatus, Status } from "src/types/BasketManagerStorage.sol";
import { ExternalTrade, InternalTrade } from "src/types/Trades.sol";

/// @title BasketManager
/// @notice Contract responsible for managing baskets and their tokens. The accounting for assets per basket is done
/// in the BasketManagerUtils contract.
contract BasketManager is ReentrancyGuardTransient, AccessControlEnumerable, Pausable {
    /// LIBRARIES ///
    using BasketManagerUtils for BasketManagerStorage;
    using SafeERC20 for IERC20;

    /// CONSTANTS ///
    /// @notice Manager role. Managers can create new baskets.
    bytes32 private constant _MANAGER_ROLE = keccak256("MANAGER_ROLE");
    /// @notice Pauser role.
    bytes32 private constant _PAUSER_ROLE = keccak256("PAUSER_ROLE");
    /// @notice Rebalance Proposer role. Rebalance proposers can propose a new rebalance.
    bytes32 private constant _REBALANCE_PROPOSER_ROLE = keccak256("REBALANCE_PROPOSER_ROLE");
    /// @notice TokenSwap Proposer role. Token swap proposers can propose a new token swap.
    bytes32 private constant _TOKENSWAP_PROPOSER_ROLE = keccak256("TOKENSWAP_PROPOSER_ROLE");
    /// @notice TokenSwap Executor role. Token swap executors can execute a token swap.
    bytes32 private constant _TOKENSWAP_EXECUTOR_ROLE = keccak256("TOKENSWAP_EXECUTOR_ROLE");
    /// @notice Basket token role. Given to the basket token contracts when they are created.
    bytes32 private constant _BASKET_TOKEN_ROLE = keccak256("BASKET_TOKEN_ROLE");
    /// @notice Role given to a timelock contract that can set critical parameters.
    bytes32 private constant _TIMELOCK_ROLE = keccak256("TIMELOCK_ROLE");
    /// @notice Maximum management fee (30%) in BPS denominated in 1e4.
    uint16 private constant _MAX_MANAGEMENT_FEE = 3000;
    /// @notice Maximum swap fee (5%) in BPS denominated in 1e4.
    uint16 private constant _MAX_SWAP_FEE = 500;

    /// STATE VARIABLES ///
    /// @notice Struct containing the BasketManagerUtils contract and other necessary data.
    BasketManagerStorage private _bmStorage;
    /// @notice Mapping of order hashes to their validity status.
    mapping(bytes32 => bool) public isOrderValid;

    /// EVENTS ///
    /// @notice Emitted when the swap fee is set.
    event SwapFeeSet(uint16 oldFee, uint16 newFee);
    /// @notice Emitted when the management fee is set.
    event ManagementFeeSet(address indexed basket, uint16 oldFee, uint16 newFee);
    /// @notice Emitted when the TokenSwapAdapter contract is set.
    event TokenSwapAdapterSet(address oldAdapter, address newAdapter);
    /// @notice Emitted when a new basket is created.
    event BasketCreated(
        address indexed basket, string basketName, string symbol, address baseAsset, uint256 bitFlag, address strategy
    );
    /// @notice Emitted when the bitFlag of a basket is updated.
    event BasketBitFlagUpdated(
        address indexed basket, uint256 oldBitFlag, uint256 newBitFlag, bytes32 oldId, bytes32 newId
    );
    /// @notice Emitted when a token swap is proposed during a rebalance.
    event TokenSwapProposed(uint40 indexed epoch, InternalTrade[] internalTrades, ExternalTrade[] externalTrades);
    /// @notice Emitted when a token swap is executed during a rebalance.
    event TokenSwapExecuted(uint40 indexed epoch);

    /// ERRORS ///
    /// @notice Thrown when attempting to execute a token swap without first proposing it.
    error TokenSwapNotProposed();
    /// @notice Thrown when the call to `TokenSwapAdapter.executeTokenSwap` fails.
    error ExecuteTokenSwapFailed();
    /// @notice Thrown when the provided hash does not match the expected hash.
    /// @dev This error is used to validate the integrity of data passed between functions.
    error InvalidHash();
    /// @notice Thrown when the provided external trades do not match the hash stored during the token swap proposal.
    /// @dev This error prevents executing a token swap with different parameters than originally proposed.
    error ExternalTradesHashMismatch();
    /// @notice Thrown when attempting to perform an action that requires no active rebalance.
    /// @dev Certain actions, like setting the token swap adapter, are disallowed during an active rebalance.
    error MustWaitForRebalanceToComplete();
    /// @notice Thrown when a caller attempts to access a function without proper authorization.
    /// @dev This error is thrown when a caller lacks the required role to perform an action.
    error Unauthorized();
    /// @notice Thrown when attempting to set an invalid management fee.
    /// @dev The management fee must not exceed `_MAX_MANAGEMENT_FEE`.
    error InvalidManagementFee();
    /// @notice Thrown when attempting to set an invalid swap fee.
    /// @dev The swap fee must not exceed `_MAX_SWAP_FEE`.
    error InvalidSwapFee();
    /// @notice Thrown when attempting to perform an action on a non-existent basket token.
    /// @dev This error is thrown when the provided basket token is not in the `basketTokenToIndexPlusOne` mapping.
    error BasketTokenNotFound();
    error BitFlagMustBeDifferent();
    error BitFlagMustIncludeCurrent();
    error BitFlagUnsupportedByStrategy();
    error BasketIdAlreadyExists();

    /// @notice Initializes the contract with the given parameters.
    /// @param basketTokenImplementation Address of the basket token implementation.
    /// @param eulerRouter_ Address of the oracle registry.
    /// @param strategyRegistry_ Address of the strategy registry.
    /// @param assetRegistry_ Address of the asset registry.
    /// @param admin Address of the admin.
    /// @param feeCollector_ Address of the fee collector.
    constructor(
        address basketTokenImplementation,
        address eulerRouter_,
        address strategyRegistry_,
        address assetRegistry_,
        address admin,
        address feeCollector_
    )
        payable
    {
        // Checks
        if (basketTokenImplementation == address(0)) revert Errors.ZeroAddress();
        if (eulerRouter_ == address(0)) revert Errors.ZeroAddress();
        if (strategyRegistry_ == address(0)) revert Errors.ZeroAddress();
        if (admin == address(0)) revert Errors.ZeroAddress();
        if (feeCollector_ == address(0)) revert Errors.ZeroAddress();
        if (assetRegistry_ == address(0)) revert Errors.ZeroAddress();

        // Effects
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        // Initialize the BasketManagerUtils struct
        _bmStorage.strategyRegistry = StrategyRegistry(strategyRegistry_);
        _bmStorage.eulerRouter = EulerRouter(eulerRouter_);
        _bmStorage.assetRegistry = assetRegistry_;
        _bmStorage.basketTokenImplementation = basketTokenImplementation;
        _bmStorage.feeCollector = feeCollector_;
    }

    /// PUBLIC FUNCTIONS ///

    /// @notice Returns the index of the basket token in the basketTokens array.
    /// @dev Reverts if the basket token does not exist.
    /// @param basketToken Address of the basket token.
    /// @return index Index of the basket token.
    function basketTokenToIndex(address basketToken) public view returns (uint256 index) {
        index = _bmStorage.basketTokenToIndex(basketToken);
    }

    /// @notice Returns the index of the basket asset in the basketAssets array.
    /// @dev Reverts if the basket asset does not exist.
    /// @param basketToken Address of the basket token.
    /// @param asset Address of the asset.
    /// @return index Index of the basket asset.
    function basketTokenToRebalanceAssetToIndex(
        address basketToken,
        address asset
    )
        public
        view
        returns (uint256 index)
    {
        index = _bmStorage.basketTokenToRebalanceAssetToIndex(basketToken, asset);
    }

    /// @notice Returns the number of basket tokens.
    /// @return Number of basket tokens.
    function numOfBasketTokens() public view returns (uint256) {
        return _bmStorage.basketTokens.length;
    }

    /// @notice Returns all basket token addresses.
    /// @return Array of basket token addresses.
    function basketTokens() external view returns (address[] memory) {
        return _bmStorage.basketTokens;
    }

    /// @notice Returns the basket token address with the given basketId.
    /// @dev The basketId is the keccak256 hash of the bitFlag and strategy address.
    /// @param basketId Basket ID.
    function basketIdToAddress(bytes32 basketId) external view returns (address) {
        return _bmStorage.basketIdToAddress[basketId];
    }

    /// @notice Returns the balance of the given asset in the given basket.
    /// @param basketToken Address of the basket token.
    /// @param asset Address of the asset.
    /// @return Balance of the asset in the basket.
    function basketBalanceOf(address basketToken, address asset) external view returns (uint256) {
        return _bmStorage.basketBalanceOf[basketToken][asset];
    }

    /// @notice Returns the current rebalance status.
    /// @return Rebalance status struct with the following fields:
    ///   - basketHash: Hash of the baskets proposed for rebalance.
    ///   - timestamp: Timestamp of the last action.
    ///   - status: Status enum of the rebalance.
    function rebalanceStatus() external view returns (RebalanceStatus memory) {
        return _bmStorage.rebalanceStatus;
    }

    /// @notice Returns the hash of the external trades stored during proposeTokenSwap
    /// @return Hash of the external trades
    function externalTradesHash() external view returns (bytes32) {
        return _bmStorage.externalTradesHash;
    }

    /// @notice Returns the address of the basket token implementation.
    /// @return Address of the basket token implementation.
    function eulerRouter() external view returns (address) {
        return address(_bmStorage.eulerRouter);
    }

    /// @notice Returns the address of the feeCollector contract.
    /// @return Address of the feeCollector.
    function feeCollector() external view returns (address) {
        return address(_bmStorage.feeCollector);
    }

    /// @notice Returns the management fee of a basket in BPS denominated in 1e4.
    /// @param basket Address of the basket.
    /// @return Management fee.
    function managementFee(address basket) external view returns (uint16) {
        return _bmStorage.managementFees[basket];
    }

    /// @notice Returns the swap fee in BPS denominated in 1e4.
    /// @return Swap fee.
    function swapFee() external view returns (uint16) {
        return _bmStorage.swapFee;
    }

    /// @notice Returns the address of the strategy registry.
    /// @return Address of the strategy registry.
    function strategyRegistry() external view returns (address) {
        return address(_bmStorage.strategyRegistry);
    }

    /// @notice Returns the address of the token swap adapter.
    /// @return Address of the token swap adapter.
    function tokenSwapAdapter() external view returns (address) {
        return _bmStorage.tokenSwapAdapter;
    }

    /// @notice Returns the retry count for the current rebalance epoch.
    /// @return Retry count.
    function retryCount() external view returns (uint8) {
        return _bmStorage.retryCount;
    }

    /// @notice Returns the addresses of all assets in the given basket.
    /// @param basket Address of the basket.
    /// @return Array of asset addresses.
    function basketAssets(address basket) external view returns (address[] memory) {
        return _bmStorage.basketAssets[basket];
    }

    /// @notice Creates a new basket token with the given parameters.
    /// @param basketName Name of the basket.
    /// @param symbol Symbol of the basket.
    /// @param bitFlag Asset selection bitFlag for the basket.
    /// @param strategy Address of the strategy contract for the basket.
    function createNewBasket(
        string calldata basketName,
        string calldata symbol,
        address baseAsset,
        uint256 bitFlag,
        address strategy
    )
        external
        payable
        whenNotPaused
        onlyRole(_MANAGER_ROLE)
        returns (address basket)
    {
        basket = _bmStorage.createNewBasket(basketName, symbol, baseAsset, bitFlag, strategy);
        _grantRole(_BASKET_TOKEN_ROLE, basket);
        emit BasketCreated(basket, basketName, symbol, baseAsset, bitFlag, strategy);
    }

    /// @notice Proposes a rebalance for the given baskets. The rebalance is proposed if the difference between the
    /// target balance and the current balance of any asset in the basket is more than 500 USD.
    /// @param basketsToRebalance Array of basket addresses to rebalance.
    function proposeRebalance(address[] calldata basketsToRebalance)
        external
        onlyRole(_REBALANCE_PROPOSER_ROLE)
        nonReentrant
        whenNotPaused
    {
        _bmStorage.proposeRebalance(basketsToRebalance);
    }

    /// @notice Proposes a set of internal trades and external trades to rebalance the given baskets.
    /// If the proposed token swap results are not close to the target balances, this function will revert.
    /// @dev This function can only be called after proposeRebalance.
    /// @param internalTrades Array of internal trades to execute.
    /// @param externalTrades Array of external trades to execute.
    /// @param basketsToRebalance Array of basket addresses currently being rebalanced.
    /// @param targetWeights Array of target weights for the baskets.
    function proposeTokenSwap(
        InternalTrade[] calldata internalTrades,
        ExternalTrade[] calldata externalTrades,
        address[] calldata basketsToRebalance,
        uint64[][] calldata targetWeights
    )
        external
        onlyRole(_TOKENSWAP_PROPOSER_ROLE)
        nonReentrant
        whenNotPaused
    {
        _bmStorage.proposeTokenSwap(internalTrades, externalTrades, basketsToRebalance, targetWeights);
        emit TokenSwapProposed(_bmStorage.rebalanceStatus.epoch, internalTrades, externalTrades);
    }

    /// @notice Executes the token swaps proposed in proposeTokenSwap and updates the basket balances.
    /// @param externalTrades Array of external trades to execute.
    /// @param data Encoded data for the token swap.
    /// @dev This function can only be called after proposeTokenSwap.
    // slither-disable-next-line controlled-delegatecall
    function executeTokenSwap(
        ExternalTrade[] calldata externalTrades,
        bytes calldata data
    )
        external
        onlyRole(_TOKENSWAP_EXECUTOR_ROLE)
        nonReentrant
        whenNotPaused
    {
        if (_bmStorage.rebalanceStatus.status != Status.TOKEN_SWAP_PROPOSED) {
            revert TokenSwapNotProposed();
        }
        address swapAdapter = _bmStorage.tokenSwapAdapter;
        if (swapAdapter == address(0)) {
            revert Errors.ZeroAddress();
        }
        // Check if the external trades match the hash from proposeTokenSwap
        if (keccak256(abi.encode(externalTrades)) != _bmStorage.externalTradesHash) {
            revert ExternalTradesHashMismatch();
        }
        _bmStorage.rebalanceStatus.status = Status.TOKEN_SWAP_EXECUTED;
        _bmStorage.rebalanceStatus.timestamp = uint40(block.timestamp);

        // solhint-disable avoid-low-level-calls
        // slither-disable-next-line low-level-calls
        (bool success,) =
            swapAdapter.delegatecall(abi.encodeCall(TokenSwapAdapter.executeTokenSwap, (externalTrades, data)));
        // solhint-enable avoid-low-level-calls
        if (!success) {
            revert ExecuteTokenSwapFailed();
        }

        emit TokenSwapExecuted(_bmStorage.rebalanceStatus.epoch);
    }

    /// @notice Sets the address of the TokenSwapAdapter contract used to execute token swaps.
    /// @param tokenSwapAdapter_ Address of the TokenSwapAdapter contract.
    /// @dev Only callable by the timelock.
    function setTokenSwapAdapter(address tokenSwapAdapter_) external onlyRole(_TIMELOCK_ROLE) {
        if (tokenSwapAdapter_ == address(0)) {
            revert Errors.ZeroAddress();
        }
        if (_bmStorage.rebalanceStatus.status != Status.NOT_STARTED) {
            revert MustWaitForRebalanceToComplete();
        }
        emit TokenSwapAdapterSet(_bmStorage.tokenSwapAdapter, tokenSwapAdapter_);
        _bmStorage.tokenSwapAdapter = tokenSwapAdapter_;
    }

    /// @notice Completes the rebalance for the given baskets. The rebalance can be completed if it has been more than
    /// 15 minutes since the last action.
    /// @param basketsToRebalance Array of basket addresses proposed for rebalance.
    /// @param targetWeights Array of target weights for the baskets.
    function completeRebalance(
        ExternalTrade[] calldata externalTrades,
        address[] calldata basketsToRebalance,
        uint64[][] calldata targetWeights
    )
        external
        nonReentrant
        whenNotPaused
    {
        _bmStorage.completeRebalance(externalTrades, basketsToRebalance, targetWeights);
    }

    /// FALLBACK REDEEM LOGIC ///

    /// @notice Fallback redeem function to redeem shares when the rebalance is not in progress. Redeems the shares for
    /// each underlying asset in the basket pro-rata to the amount of shares redeemed.
    /// @param totalSupplyBefore Total supply of the basket token before the shares were burned.
    /// @param burnedShares Amount of shares burned.
    /// @param to Address to send the redeemed assets to.
    function proRataRedeem(
        uint256 totalSupplyBefore,
        uint256 burnedShares,
        address to
    )
        public
        nonReentrant
        whenNotPaused
        onlyRole(_BASKET_TOKEN_ROLE)
    {
        _bmStorage.proRataRedeem(totalSupplyBefore, burnedShares, to);
    }

    /// FEE FUNCTIONS ///

    /// @notice Set the management fee to be given to the treausry on rebalance.
    /// @param basket Address of the basket token.
    /// @param managementFee_ Management fee in BPS denominated in 1e4.
    /// @dev Only callable by the timelock.
    /// @dev Setting the management fee of the 0 address will set the default management fee for newly created baskets.
    function setManagementFee(address basket, uint16 managementFee_) external onlyRole(_TIMELOCK_ROLE) {
        if (managementFee_ > _MAX_MANAGEMENT_FEE) {
            revert InvalidManagementFee();
        }

        // Check if the basket is currently rebalancing
        if (basket != address(0)) {
            uint256 indexPlusOne = _bmStorage.basketTokenToIndexPlusOne[basket];
            if (indexPlusOne == 0) {
                revert BasketTokenNotFound();
            }
            if ((_bmStorage.rebalanceStatus.basketMask & (1 << indexPlusOne - 1)) != 0) {
                revert MustWaitForRebalanceToComplete();
            }
        }
        emit ManagementFeeSet(basket, _bmStorage.managementFees[basket], managementFee_);
        _bmStorage.managementFees[basket] = managementFee_;
    }

    /// @notice Set the swap fee to be given to the treasury on rebalance.
    /// @param swapFee_ Swap fee in BPS denominated in 1e4.
    /// @dev Only callable by the timelock.
    function setSwapFee(uint16 swapFee_) external onlyRole(_TIMELOCK_ROLE) {
        if (swapFee_ > _MAX_SWAP_FEE) {
            revert InvalidSwapFee();
        }
        if (_bmStorage.rebalanceStatus.status != Status.NOT_STARTED) {
            revert MustWaitForRebalanceToComplete();
        }
        emit SwapFeeSet(_bmStorage.swapFee, swapFee_);
        _bmStorage.swapFee = swapFee_;
    }

    /// @notice Claims the swap fee for the given asset and sends it to protocol treasury defined in the FeeCollector.
    /// @param asset Address of the asset to collect the swap fee for.
    function collectSwapFee(address asset) external onlyRole(_MANAGER_ROLE) returns (uint256 collectedFees) {
        collectedFees = _bmStorage.collectedSwapFees[asset];
        if (collectedFees != 0) {
            _bmStorage.collectedSwapFees[asset] = 0;
            IERC20(asset).safeTransfer(FeeCollector(_bmStorage.feeCollector).protocolTreasury(), collectedFees);
        }
    }

    /// @notice Updates the bitFlag for the given basket.
    /// @param basket Address of the basket.
    /// @param bitFlag New bitFlag. It must be inclusive of the current bitFlag.
    function updateBitFlag(address basket, uint256 bitFlag) external onlyRole(_TIMELOCK_ROLE) {
        // Checks
        // Check if basket exists
        uint256 indexPlusOne = _bmStorage.basketTokenToIndexPlusOne[basket];
        if (indexPlusOne == 0) {
            revert BasketTokenNotFound();
        }
        uint256 currentBitFlag = BasketToken(basket).bitFlag();
        if (currentBitFlag == bitFlag) {
            revert BitFlagMustBeDifferent();
        }
        // Check if the new bitFlag is inclusive of the current bitFlag
        if ((currentBitFlag & bitFlag) != currentBitFlag) {
            revert BitFlagMustIncludeCurrent();
        }
        address strategy = BasketToken(basket).strategy();
        if (!WeightStrategy(strategy).supportsBitFlag(bitFlag)) {
            revert BitFlagUnsupportedByStrategy();
        }
        bytes32 newId = keccak256(abi.encodePacked(bitFlag, strategy));
        if (_bmStorage.basketIdToAddress[newId] != address(0)) {
            revert BasketIdAlreadyExists();
        }
        // Remove the old bitFlag mapping and add the new bitFlag mapping
        bytes32 oldId = keccak256(abi.encodePacked(currentBitFlag, strategy));
        _bmStorage.basketIdToAddress[oldId] = address(0);
        _bmStorage.basketIdToAddress[newId] = basket;
        _bmStorage.basketAssets[basket] = AssetRegistry(_bmStorage.assetRegistry).getAssets(bitFlag);
        emit BasketBitFlagUpdated(basket, currentBitFlag, bitFlag, oldId, newId);
        // Update the bitFlag in the BasketToken contract
        BasketToken(basket).setBitFlag(bitFlag);
    }

    /// PAUSING FUNCTIONS ///

    /// @notice Pauses the contract. Callable by DEFAULT_ADMIN_ROLE or PAUSER_ROLE.
    function pause() external {
        if (!(hasRole(_PAUSER_ROLE, msg.sender) || hasRole(DEFAULT_ADMIN_ROLE, msg.sender))) {
            revert Unauthorized();
        }
        _pause();
    }

    /// @notice Unpauses the contract. Only callable by DEFAULT_ADMIN_ROLE.
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }
}
