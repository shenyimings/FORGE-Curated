// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {
    AccessControlEnumerableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {StvStETHPool} from "src/StvStETHPool.sol";
import {WithdrawalQueue} from "src/WithdrawalQueue.sol";
import {IStrategyCallForwarder} from "src/interfaces/IStrategyCallForwarder.sol";
import {IBoringOnChainQueue} from "src/interfaces/ggv/IBoringOnChainQueue.sol";
import {ITellerWithMultiAssetSupport} from "src/interfaces/ggv/ITellerWithMultiAssetSupport.sol";
import {StrategyCallForwarderRegistry} from "src/strategy/StrategyCallForwarderRegistry.sol";
import {FeaturePausable} from "src/utils/FeaturePausable.sol";

import {IStrategy} from "src/interfaces/IStrategy.sol";
import {IWstETH} from "src/interfaces/core/IWstETH.sol";

contract GGVStrategy is IStrategy, AccessControlEnumerableUpgradeable, FeaturePausable, StrategyCallForwarderRegistry {
    using SafeCast for uint256;

    StvStETHPool private immutable POOL_;
    IWstETH public immutable WSTETH;

    ITellerWithMultiAssetSupport public immutable TELLER;
    IBoringOnChainQueue public immutable BORING_QUEUE;

    // ACL
    bytes32 public constant SUPPLY_FEATURE = keccak256("SUPPLY_FEATURE");
    bytes32 public constant SUPPLY_PAUSE_ROLE = keccak256("SUPPLY_PAUSE_ROLE");
    bytes32 public constant SUPPLY_RESUME_ROLE = keccak256("SUPPLY_RESUME_ROLE");

    struct GGVParamsSupply {
        uint256 minimumMint;
    }

    struct GGVParamsRequestExit {
        uint16 discount;
        uint24 secondsToDeadline;
    }

    event GGVDeposited(
        address indexed recipient,
        uint256 wstethAmount,
        uint256 ggvShares,
        address indexed referralAddress,
        bytes paramsSupply
    );
    event GGVWithdrawalRequested(
        address indexed recipient, bytes32 requestId, uint256 ggvShares, bytes paramsRequestExit
    );

    error ZeroArgument(string name);
    error InvalidSender();
    error InvalidWstethAmount();
    error InsufficientWsteth();
    error NotImplemented();

    constructor(
        bytes32 _strategyId,
        address _strategyCallForwarderImpl,
        address _pool,
        address _teller,
        address _boringQueue
    ) StrategyCallForwarderRegistry(_strategyId, _strategyCallForwarderImpl) {
        POOL_ = StvStETHPool(payable(_pool));
        WSTETH = IWstETH(POOL_.WSTETH());

        TELLER = ITellerWithMultiAssetSupport(_teller);
        BORING_QUEUE = IBoringOnChainQueue(_boringQueue);

        _disableInitializers();
        _pauseFeature(SUPPLY_FEATURE);
    }

    /**
     * @notice Initialize the contract storage explicitly
     * @param _admin Admin address that can change every role
     * @param _supplyPauser Address that can pause supply (zero for none)
     * @dev Reverts if `_admin` equals to `address(0)`
     */
    function initialize(address _admin, address _supplyPauser) external initializer {
        if (_admin == address(0)) revert ZeroArgument("_admin");

        __AccessControlEnumerable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        if (address(0) != _supplyPauser) {
            _grantRole(SUPPLY_PAUSE_ROLE, _supplyPauser);
        }
    }

    /**
     * @inheritdoc IStrategy
     */
    function POOL() external view returns (address) {
        return address(POOL_);
    }

    // =================================================================================
    // PAUSE / RESUME
    // =================================================================================

    /**
     * @notice Pause supply
     */
    function pauseSupply() external {
        _checkRole(SUPPLY_PAUSE_ROLE, msg.sender);
        _pauseFeature(SUPPLY_FEATURE);
    }

    /**
     * @notice Resume supply
     */
    function resumeSupply() external {
        _checkRole(SUPPLY_RESUME_ROLE, msg.sender);
        _resumeFeature(SUPPLY_FEATURE);
    }

    // =================================================================================
    // SUPPLY
    // =================================================================================

    /**
     * @inheritdoc IStrategy
     */
    function supply(address _referral, uint256 _wstethToMint, bytes calldata _params)
        external
        payable
        returns (uint256 stv)
    {
        _checkFeatureNotPaused(SUPPLY_FEATURE);

        IStrategyCallForwarder callForwarder = _getOrCreateCallForwarder(msg.sender);

        if (msg.value > 0) {
            stv = POOL_.depositETH{value: msg.value}(address(callForwarder), _referral);
        }

        callForwarder.doCall(address(POOL_), abi.encodeWithSelector(POOL_.mintWsteth.selector, _wstethToMint));
        callForwarder.doCall(
            address(WSTETH), abi.encodeWithSelector(WSTETH.approve.selector, TELLER.vault(), _wstethToMint)
        );

        GGVParamsSupply memory params = abi.decode(_params, (GGVParamsSupply));

        bytes memory data = callForwarder.doCall(
            address(TELLER),
            abi.encodeWithSelector(
                TELLER.deposit.selector, address(WSTETH), _wstethToMint, params.minimumMint, _referral
            )
        );
        uint256 ggvShares = abi.decode(data, (uint256));

        emit StrategySupplied(msg.sender, _referral, msg.value, stv, _wstethToMint, _params);
        emit GGVDeposited(msg.sender, _wstethToMint, ggvShares, _referral, _params);
    }

    // =================================================================================
    // REQUEST EXIT FROM STRATEGY
    // =================================================================================

    /**
     * @notice Previews the amount of wstETH that can be withdrawn by a given amount of GGV shares
     * @param _ggvShares The amount of GGV shares to preview the amount of wstETH for
     * @param _params The parameters for the withdrawal
     * @return wsteth The amount of wstETH that can be withdrawn
     */
    function previewWstethByGGV(uint256 _ggvShares, bytes calldata _params) public view returns (uint256 wsteth) {
        GGVParamsRequestExit memory params = abi.decode(_params, (GGVParamsRequestExit));
        wsteth = BORING_QUEUE.previewAssetsOut(address(WSTETH), _ggvShares.toUint128(), params.discount);
    }

    /**
     * @inheritdoc IStrategy
     */
    function requestExitByWsteth(uint256 _wsteth, bytes calldata _params) external returns (bytes32 requestId) {
        if (_wsteth == 0) revert ZeroArgument("_wsteth");

        GGVParamsRequestExit memory params = abi.decode(_params, (GGVParamsRequestExit));

        IStrategyCallForwarder callForwarder = _getOrCreateCallForwarder(msg.sender);
        IERC20 boringVault = IERC20(TELLER.vault());

        // Calculate how much wsteth we'll get from total GGV shares
        uint256 totalGGV = boringVault.balanceOf(address(callForwarder));
        uint256 totalWstethFromGGV = previewWstethByGGV(totalGGV, _params);
        if (totalWstethFromGGV == 0) revert InvalidWstethAmount();
        if (_wsteth > totalWstethFromGGV) revert InsufficientWsteth();

        // Approve GGV shares
        uint256 ggvShares = Math.mulDiv(totalGGV, _wsteth, totalWstethFromGGV, Math.Rounding.Ceil);
        callForwarder.doCall(
            address(boringVault), abi.encodeWithSelector(boringVault.approve.selector, address(BORING_QUEUE), ggvShares)
        );

        // Withdrawal request from GGV
        bytes memory data = callForwarder.doCall(
            address(BORING_QUEUE),
            abi.encodeWithSelector(
                BORING_QUEUE.requestOnChainWithdraw.selector,
                address(WSTETH),
                ggvShares.toUint128(),
                params.discount,
                params.secondsToDeadline
            )
        );
        requestId = abi.decode(data, (bytes32));

        emit StrategyExitRequested(msg.sender, requestId, _wsteth, _params);
        emit GGVWithdrawalRequested(msg.sender, requestId, ggvShares, _params);
    }

    /**
     * @inheritdoc IStrategy
     */
    function finalizeRequestExit(
        bytes32 /*_requestId*/
    )
        external
        pure
    {
        // GGV does not provide a way to check request status, so we cannot verify if the request
        // was actually finalized in GGV Queue. Additionally, GGV allows multiple withdrawal requests,
        // so it's possible to have request->finalize->request sequence where 2 unfinalised requests
        // exist in GGV at the same time.
        revert NotImplemented();
    }

    // =================================================================================
    // CANCEL / REPLACE GGV REQUEST
    // =================================================================================

    /**
     * @notice Cancels a GGV withdrawal request
     * @param _request The request to cancel
     */
    function cancelGGVOnChainWithdraw(IBoringOnChainQueue.OnChainWithdraw memory _request) external {
        IStrategyCallForwarder callForwarder = _getOrCreateCallForwarder(msg.sender);
        if (address(callForwarder) != _request.user) revert InvalidSender();

        callForwarder.doCall(
            address(BORING_QUEUE), abi.encodeWithSelector(BORING_QUEUE.cancelOnChainWithdraw.selector, _request)
        );
    }

    /**
     * @notice Replaces a withdrawal request
     * @param request The request to replace
     * @param discount The discount to use
     * @param secondsToDeadline The deadline to use
     * @return oldRequestId The old request id
     * @return newRequestId The new request id
     */
    function replaceGGVOnChainWithdraw(
        IBoringOnChainQueue.OnChainWithdraw memory request,
        uint16 discount,
        uint24 secondsToDeadline
    ) external returns (bytes32 oldRequestId, bytes32 newRequestId) {
        IStrategyCallForwarder callForwarder = _getOrCreateCallForwarder(msg.sender);
        if (address(callForwarder) != request.user) revert InvalidSender();

        bytes memory data = callForwarder.doCall(
            address(BORING_QUEUE),
            abi.encodeWithSelector(BORING_QUEUE.replaceOnChainWithdraw.selector, request, discount, secondsToDeadline)
        );
        (oldRequestId, newRequestId) = abi.decode(data, (bytes32, bytes32));
    }

    // =================================================================================
    // HELPERS
    // =================================================================================

    /**
     * @inheritdoc IStrategy
     */
    function mintedStethSharesOf(address _user) external view returns (uint256 mintedStethShares) {
        IStrategyCallForwarder callForwarder = getStrategyCallForwarderAddress(_user);
        mintedStethShares = POOL_.mintedStethSharesOf(address(callForwarder));
    }

    /**
     * @inheritdoc IStrategy
     */
    function remainingMintingCapacitySharesOf(address _user, uint256 _ethToFund)
        external
        view
        returns (uint256 stethShares)
    {
        IStrategyCallForwarder callForwarder = getStrategyCallForwarderAddress(_user);
        stethShares = POOL_.remainingMintingCapacitySharesOf(address(callForwarder), _ethToFund);
    }

    /**
     * @inheritdoc IStrategy
     */
    function wstethOf(address _user) external view returns (uint256 wsteth) {
        IStrategyCallForwarder callForwarder = getStrategyCallForwarderAddress(_user);
        wsteth = WSTETH.balanceOf(address(callForwarder));
    }

    /**
     * @inheritdoc IStrategy
     */
    function stvOf(address _user) external view returns (uint256 stv) {
        IStrategyCallForwarder callForwarder = getStrategyCallForwarderAddress(_user);
        stv = POOL_.balanceOf(address(callForwarder));
    }

    /**
     * @notice Returns the amount of GGV shares of a user
     * @param _user The user to get the GGV shares for
     * @return ggvShares The amount of GGV shares
     */
    function ggvOf(address _user) external view returns (uint256 ggvShares) {
        IStrategyCallForwarder callForwarder = getStrategyCallForwarderAddress(_user);
        ggvShares = IERC20(TELLER.vault()).balanceOf(address(callForwarder));
    }

    // =================================================================================
    // REQUEST WITHDRAWAL FROM POOL
    // =================================================================================

    /**
     * @inheritdoc IStrategy
     */
    function requestWithdrawalFromPool(address _recipient, uint256 _stvToWithdraw, uint256 _stethSharesToRebalance)
        external
        returns (uint256 requestId)
    {
        IStrategyCallForwarder callForwarder = _getOrCreateCallForwarder(msg.sender);

        // request withdrawal from pool
        bytes memory withdrawalData = callForwarder.doCall(
            address(POOL_.WITHDRAWAL_QUEUE()),
            abi.encodeWithSelector(
                WithdrawalQueue.requestWithdrawal.selector, _recipient, _stvToWithdraw, _stethSharesToRebalance
            )
        );
        requestId = abi.decode(withdrawalData, (uint256));
    }

    /**
     * @notice Burns wstETH to reduce the user's minted stETH obligation
     * @param _wstethToBurn The amount of wstETH to burn
     */
    function burnWsteth(uint256 _wstethToBurn) external {
        IStrategyCallForwarder callForwarder = _getOrCreateCallForwarder(msg.sender);
        callForwarder.doCall(
            address(WSTETH), abi.encodeWithSelector(WSTETH.approve.selector, address(POOL_), _wstethToBurn)
        );
        callForwarder.doCall(address(POOL_), abi.encodeWithSelector(StvStETHPool.burnWsteth.selector, _wstethToBurn));
    }

    /**
     * @notice Transfers ERC20 tokens from the call forwarder
     * @param _token The token to recover
     * @param _recipient The recipient of the tokens
     * @param _amount The amount of tokens to recover
     */
    function safeTransferERC20(address _token, address _recipient, uint256 _amount) external {
        if (_token == address(0)) revert ZeroArgument("_token");
        if (_recipient == address(0)) revert ZeroArgument("_recipient");
        if (_amount == 0) revert ZeroArgument("_amount");

        IStrategyCallForwarder callForwarder = _getOrCreateCallForwarder(msg.sender);
        callForwarder.safeTransferERC20(_token, _recipient, _amount);
    }
}
