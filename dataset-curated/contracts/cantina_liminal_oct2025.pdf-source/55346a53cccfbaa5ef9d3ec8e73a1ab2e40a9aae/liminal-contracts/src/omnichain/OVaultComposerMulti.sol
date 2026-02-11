// SPDX-License-Identifier: BUSL-1.1
// Terms: https://liminal.money/xtokens/license
pragma solidity 0.8.28;

import {VaultComposerBase} from "../VaultComposerBase.sol";
import {OFTComposeMsgCodec} from "@layerzerolabs/oft-evm/contracts/libs/OFTComposeMsgCodec.sol";
import {AccessControlUpgradeable} from
    "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IOFT, SendParam, MessagingFee, OFTReceipt} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {IDepositPipe} from "../interfaces/IDepositPipe.sol";
import {IRedemptionPipe} from "../interfaces/IRedemptionPipe.sol";

/**
 * @title OVaultComposerMulti
 * @notice Cross-chain composer for multi-asset vault system
 * @dev Routes deposits to appropriate pipes based on asset type
 */
contract OVaultComposerMulti is
    VaultComposerBase,
    AccessControlUpgradeable,
    PausableUpgradeable
{
    using SafeERC20 for IERC20;
    using OFTComposeMsgCodec for bytes;
    using OFTComposeMsgCodec for bytes32;

    // Compose message types
    uint8 constant ACTION_DEPOSIT_ASSET = 1;
    uint8 constant ACTION_REDEEM_SHARES = 2;

    // Roles
    bytes32 public constant EMERGENCY_MANAGER_ROLE = keccak256("EMERGENCY_MANAGER_ROLE");
    bytes32 public constant RECOVER_ASSETS_MANAGER_ROLE = keccak256("RECOVER_ASSETS_MANAGER_ROLE");

    /// @custom:storage-location erc7201:liminal.storage.OVaultComposerMulti
    struct OVaultComposerMultiStorage {
        /// @notice Timelock controller for critical operations
        address timeLockController;
        // Asset management
        mapping(address => address) depositPipes;
        mapping(address => address) assetOFTs; // Asset to OFT mapping
        // array to handle assets from depositPipes
        address[] supportedAssets;
        // For efficient removal. A mapping to store index of each asset in the array
        mapping(address => uint256) assetIndex;
        address redemptionPipe;
        address underlyingAsset;
        address underlyingAssetOFT;
        mapping(address => bool) approvedOFTs;
        mapping(address => mapping(uint32 => bytes32)) remotePeers;
    }

    // keccak256(abi.encode(uint256(keccak256("liminal.storage.OVaultComposerMulti.v1")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant OVaultComposerMultiStorageLocation =
        0xcad0c23afae839586aab4f80ae20039159400eb78664ff0bdd704907083fac00;

    function _getOVaultComposerMultiStorage()
        private
        pure
        returns (OVaultComposerMultiStorage storage $)
    {
        assembly {
            $.slot := OVaultComposerMultiStorageLocation
        }
    }

    // Events
    event DepositPipeRegistered(address indexed asset, address indexed pipe, address indexed oft);
    event DepositPipeRemoved(address indexed asset);
    event RedemptionPipeUpdated(address indexed oldPipe, address indexed newPipe);
    event UnderlyingAssetUpdated(address indexed oldAsset, address indexed newAsset);
    event OFTApprovalSet(address indexed oft, bool approved);
    event RemotePeerSet(address indexed oft, uint32 indexed srcEid, bytes32 remotePeer);
    event TimelockControllerSet(address indexed oldTimelock, address indexed newTimelock);

    /// @notice Modifier for timelock-protected functions
    modifier onlyTimelock() {
        OVaultComposerMultiStorage storage $ = _getOVaultComposerMultiStorage();
        require(msg.sender == $.timeLockController, "OVaultComposerMulti: only timelock");
        _;
    }

    // Errors
    error NoPipeForAsset(address asset);
    error InvalidPipe();
    error NoOFTForAsset(address asset);
    error OnlySelf(address caller);
    error InvalidAction(uint8 action);
    error InvalidOFT(address oft);
    error SlippageExceedsDustRemoval(uint256 amountAfterDust, uint256 slippageAmount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Constructor
     * @dev Ownership (DEFAULT_ADMIN_ROLE) is granted to deployer
     * @param _shareOFT Share OFT adapter address
     * @param _redemptionPipe Redemption pipe address
     * @param _underlyingAsset Underlying redemption asset
     * @param _underlyingAssetOFT Underlying asset OFT
     * @param _deployer Deployer address (receives DEFAULT_ADMIN_ROLE)
     * @param _timeLockController Timelock controller for critical operations (deployer initially, then set to real timelock)
     */
    function initialize(
        address _shareOFT,
        address _redemptionPipe,
        address _underlyingAsset,
        address _underlyingAssetOFT,
        address _deployer,
        address _emergencyManager,
        address _timeLockController,
        address _recoverAssetsManager
    ) external initializer {
        require(_redemptionPipe != address(0), "OVaultComposerMulti: zero redemption pipe");
        require(_underlyingAsset != address(0), "OVaultComposerMulti: zero underlying");
        require(_underlyingAssetOFT != address(0), "OVaultComposerMulti: zero underlying OFT");
        require(_deployer != address(0), "OVaultComposerMulti: zero deployer");
        require(_emergencyManager != address(0), "OVaultComposerMulti: zero emergency manager");
        require(_recoverAssetsManager != address(0), "OVaultComposerMulti: zero recover assets manager");

        __VaultComposerBase_init(_shareOFT);
        __AccessControl_init();
        __Pausable_init();

        // Grant ownership to deployer
        _grantRole(DEFAULT_ADMIN_ROLE, _deployer);
        _grantRole(EMERGENCY_MANAGER_ROLE, _emergencyManager);
        _grantRole(RECOVER_ASSETS_MANAGER_ROLE, _recoverAssetsManager);

        OVaultComposerMultiStorage storage $ = _getOVaultComposerMultiStorage();
        $.redemptionPipe = _redemptionPipe;
        $.underlyingAsset = _underlyingAsset;
        $.underlyingAssetOFT = _underlyingAssetOFT;
        $.timeLockController = _timeLockController;

        // Approve SHARE_OFT for compose messages
        $.approvedOFTs[_shareOFT] = true;

        // Approve underlying asset OFT for compose messages
        $.approvedOFTs[_underlyingAssetOFT] = true;
    }

    /**
     * @notice Redeem and send assets cross-chain
     * @param _shareAmount Amount of shares to redeem
     * @param _sendParam Cross-chain send parameters
     * @param _refundAddress Address for fee refunds
     */
    function redeemAndSend(
        uint256 _shareAmount,
        SendParam memory _sendParam,
        address _refundAddress
    ) external payable whenNotPaused nonReentrant {
        OVaultComposerMultiStorage storage $ = _getOVaultComposerMultiStorage();

        uint256 assets = IRedemptionPipe($.redemptionPipe).redeem(_shareAmount, address(this), msg.sender);

        _assertSlippage(assets, _sendParam.minAmountLD);
        _sendParam.amountLD = assets;

        // Calculate minimum after dust removal to protect against decimal conversion losses
        _sendParam.minAmountLD = _calculateMinAmountAfterDust(
            $.underlyingAssetOFT,
            assets,
            _sendParam.minAmountLD
        );

        // Quote OFT to get exact amount after dedusting
        (,, OFTReceipt memory receipt) = IOFT($.underlyingAssetOFT).quoteOFT(_sendParam);
        uint256 amountToSend = receipt.amountSentLD;

        // Approve only the exact amount that will be sent
        IERC20($.underlyingAsset).forceApprove($.underlyingAssetOFT, amountToSend);

        // Update sendParam with the exact amount
        _sendParam.amountLD = amountToSend;

        _send($.underlyingAssetOFT, _sendParam, _refundAddress);

        // Refund dust to user
        uint256 dust = assets - amountToSend;
        if (dust > 0) {
            IERC20($.underlyingAsset).safeTransfer(msg.sender, dust);
            emit DustRefunded($.underlyingAsset, msg.sender, dust);
        }
    }

    /**
     * @notice Deposit specific asset and send shares cross-chain
     * @param asset Asset address to deposit
     * @param _assetAmount Amount to deposit
     * @param _sendParam Cross-chain send parameters
     * @param _refundAddress Address for fee refunds
     */
    function depositAssetAndSend(
        address asset,
        uint256 _assetAmount,
        SendParam memory _sendParam,
        address _refundAddress
    ) external payable whenNotPaused nonReentrant {
        OVaultComposerMultiStorage storage $ = _getOVaultComposerMultiStorage();

        address pipe = $.depositPipes[asset];
        if (pipe == address(0)) revert NoPipeForAsset(asset);

        uint256 shares = IDepositPipe(pipe).deposit(_assetAmount, address(this), msg.sender);

        _assertSlippage(shares, _sendParam.minAmountLD);
        _sendParam.amountLD = shares;

        // Quote OFT to get exact amount after dedusting
        (,, OFTReceipt memory receipt) = IOFT(SHARE_OFT).quoteOFT(_sendParam);
        uint256 amountToSend = receipt.amountSentLD;

        // Approve only the exact amount that will be sent
        IERC20(SHARE_ERC20).forceApprove(SHARE_OFT, amountToSend);

        // Update sendParam with the exact amount
        _sendParam.amountLD = amountToSend;

        _send(SHARE_OFT, _sendParam, _refundAddress);
        
        // Determine share recipient: if cross-chain, use sendParam.to, otherwise shares stay with depositor
        address shareRecipient = _sendParam.dstEid != 0 
            ? _sendParam.to.bytes32ToAddress() 
            : msg.sender;
        
        // For direct calls (not via LayerZero), srcEid is the current chain (VAULT_EID)
        emit CrossChainDeposit(asset, msg.sender, shareRecipient, VAULT_EID, _sendParam.dstEid, _assetAmount, shares);

        // Refund dust to user
        uint256 dust = shares - amountToSend;
        if (dust > 0) {
            IERC20(SHARE_ERC20).safeTransfer(msg.sender, dust);
            emit DustRefunded(SHARE_ERC20, msg.sender, dust);
        }
    }

    /**
     * @notice Register a deposit pipe for an asset
     * @param asset Asset address
     * @param pipe Deposit pipe address
     * @param assetOFT Asset's OFT address
     */
    function registerDepositPipe(address asset, address pipe, address assetOFT)
        external
        onlyTimelock
    {
        require(asset != address(0), "OVaultComposerMulti: zero asset");
        require(pipe != address(0), "OVaultComposerMulti: zero pipe");
        require(assetOFT != address(0), "OVaultComposerMulti: zero OFT");

        OVaultComposerMultiStorage storage $ = _getOVaultComposerMultiStorage();
        require($.depositPipes[asset] != pipe, "OVaultComposerMulti: same pipe");

        // Verify pipe accepts this asset
        address pipeAsset = IDepositPipe(pipe).asset();
        if (pipeAsset != asset) revert InvalidPipe();

        _addAsset(asset, pipe); // updates mapping and array
        $.assetOFTs[asset] = assetOFT;

        // Approve the asset OFT for compose messages
        $.approvedOFTs[assetOFT] = true;

        emit DepositPipeRegistered(asset, pipe, assetOFT);
    }

    /**
     * @notice Remove a deposit pipe
     */
    function removeDepositPipe(address asset) external onlyTimelock {
        OVaultComposerMultiStorage storage $ = _getOVaultComposerMultiStorage();

        address pipe = $.depositPipes[asset];
        if (pipe != address(0)) {
            IERC20(asset).forceApprove(pipe, 0);
            address assetOFT = $.assetOFTs[asset];

            // Remove OFT approval
            if (assetOFT != address(0)) {
                $.approvedOFTs[assetOFT] = false;
            }

            _removeAsset(asset); // updates mapping and array
            delete $.assetOFTs[asset];
            emit DepositPipeRemoved(asset);
        }
    }

    /**
     * @notice Update redemption pipe
     * @param _redemptionPipe New redemption pipe address
     */
    function setRedemptionPipe(address _redemptionPipe) external onlyTimelock {
        require(_redemptionPipe != address(0), "OVaultComposerMulti: zero pipe");

        OVaultComposerMultiStorage storage $ = _getOVaultComposerMultiStorage();
        address oldPipe = $.redemptionPipe;
        $.redemptionPipe = _redemptionPipe;
        emit RedemptionPipeUpdated(oldPipe, _redemptionPipe);
    }

    /**
     * @notice Update underlying asset (kept as SAFE_MANAGER for operational flexibility)
     * @param _underlyingAsset New underlying asset address
     */
    function setUnderlyingAsset(address _underlyingAsset) external onlyTimelock {
        require(_underlyingAsset != address(0), "OVaultComposerMulti: zero asset");

        OVaultComposerMultiStorage storage $ = _getOVaultComposerMultiStorage();
        address oldAsset = $.underlyingAsset;
        $.underlyingAsset = _underlyingAsset;
        emit UnderlyingAssetUpdated(oldAsset, _underlyingAsset);
    }

    /**
     * @notice Handle compose operations for multi-asset vault
     */
    function handleCompose(
        address _oftIn,
        bytes32 _composeFrom,
        bytes32 /* _guid */,
        bytes memory _composeMsg,
        uint256 _amount,
        uint32 _srcEid
    ) public payable override whenNotPaused nonReentrant {
        // Only self can call
        if (msg.sender != address(this)) revert OnlySelf(msg.sender);

        // Decode the compose message
        (uint8 action, bytes memory params) = abi.decode(_composeMsg, (uint8, bytes));

        // For redemption actions, ONLY the legitimate SHARE_OFT can trigger them
        // This prevents the attack where an approved asset OFT tries to steal shares
        // sitting in the composer by sending a redemption compose message
        // Note: Deposit actions validate against assetOFTs[targetAsset] in _handleDepositAsset
        if (action == ACTION_REDEEM_SHARES) {
            if (_oftIn != SHARE_OFT) revert InvalidOFT(_oftIn);
        }

        if (action == ACTION_DEPOSIT_ASSET) {
            _handleDepositAsset(_oftIn, _composeFrom, params, _amount, _srcEid);
        } else if (action == ACTION_REDEEM_SHARES) {
            _handleRedeemShares(_composeFrom, params, _amount, _srcEid);
        } else {
            revert InvalidAction(action);
        }
    }

    /**
     * @notice Handle cross-chain asset deposit
     */
    function _handleDepositAsset(
        address _oftIn,
        bytes32 _composeFrom,
        bytes memory _params,
        uint256 _amount,
        uint32 _srcEid
    ) internal {
        (address targetAsset, bytes32 receiver, SendParam memory sendParam, uint256 minMsgValue, bytes32 feeRefundRecipient, ) =
            abi.decode(_params, (address, bytes32, SendParam, uint256, bytes32, uint32));

        // Defense in depth: These validations are also performed by OVaultMsgInspector on the source chain
        // before sending. However, we keep them here as a safety net in case:
        // 1. MsgInspector is disabled/removed on the source OFT
        // 2. Messages arrive from unexpected sources
        // 3. Additional security layer following principle of "never trust external input"
        require(receiver != bytes32(0), "OVaultComposerMulti: zero receiver");
        if (sendParam.dstEid != 0) {
            require(sendParam.to != bytes32(0), "OVaultComposerMulti: zero destination");
        }

        // Validate msg.value
        if (msg.value < minMsgValue) revert InsufficientMsgValue();

        OVaultComposerMultiStorage storage $ = _getOVaultComposerMultiStorage();

        // Get deposit pipe for asset
        address pipe = $.depositPipes[targetAsset];
        if (pipe == address(0)) revert NoPipeForAsset(targetAsset);

        // Verify _oftIn matches the registered OFT for this asset
        if (_oftIn != $.assetOFTs[targetAsset]) revert InvalidOFT(_oftIn);

        // When OFT receives tokens and triggers compose, it mints tokens directly to this composer
        // So tokens should already be in our balance
        uint256 composerBalance = IERC20(targetAsset).balanceOf(address(this));
        require(composerBalance >= _amount, "Insufficient balance in composer");

        // Deposit through pipe
        address depositor = _composeFrom.bytes32ToAddress();

        // If cross-chain send is needed, mint shares to composer first
        // Otherwise mint directly to receiver (convert bytes32 to address for EVM delivery)
        address shareMintRecipient =
            sendParam.dstEid != 0 ? address(this) : receiver.bytes32ToAddress();

        // Approve exact amount for deposit
        IERC20(targetAsset).forceApprove(pipe, _amount);

        uint256 shares = IDepositPipe(pipe).deposit(
            _amount,
            shareMintRecipient, // Mint to composer if cross-chain send, else to receiver
            address(this) // Tokens are in composer, not original depositor
        );

        // Determine share recipient: if cross-chain, use sendParam.to, otherwise use receiver
        address shareRecipient = sendParam.dstEid != 0 
            ? sendParam.to.bytes32ToAddress() 
            : receiver.bytes32ToAddress();

        emit CrossChainDeposit(targetAsset, depositor, shareRecipient, _srcEid, sendParam.dstEid, _amount, shares);

        _assertSlippage(shares, sendParam.minAmountLD);

        // If sendParam is provided, send shares cross-chain
        if (sendParam.dstEid != 0) {
            sendParam.amountLD = shares;

            // Quote OFT to get exact amount after dedusting
            (,, OFTReceipt memory receipt) = IOFT(SHARE_OFT).quoteOFT(sendParam);
            uint256 amountToSend = receipt.amountSentLD;

            // Approve only the exact amount that will be sent
            IERC20(SHARE_ERC20).forceApprove(SHARE_OFT, amountToSend);

            // Update sendParam with the exact amount
            sendParam.amountLD = amountToSend;
            
            // Use feeRefundRecipient if provided, otherwise fallback to depositor
            address refundRecipient = feeRefundRecipient != bytes32(0)
                ? feeRefundRecipient.bytes32ToAddress()
                : depositor;

            _send(SHARE_OFT, sendParam, refundRecipient);

            // Refund dust to depositor
            uint256 dust = shares - amountToSend;
            if (dust > 0) {
                IERC20(SHARE_ERC20).safeTransfer(depositor, dust);
                emit DustRefunded(SHARE_ERC20, depositor, dust);
            }
        }
        // If no cross-chain send, shares are already at receiver address
    }

    /**
     * @notice Handle share redemption
     */
    function _handleRedeemShares(bytes32 _composeFrom, bytes memory _params, uint256 _shareAmount, uint32 _srcEid)
        internal
    {
        (address receiver, SendParam memory sendParam, uint256 minMsgValue, uint256 minAssets, bytes32 feeRefundRecipient, ) =
            abi.decode(_params, (address, SendParam, uint256, uint256, bytes32, uint32));

        // Defense in depth: These validations are also performed by OVaultMsgInspector on the source chain
        // before sending. We keep them here as a safety net (see _handleDepositAsset for rationale)
        require(receiver != address(0), "OVaultComposerMulti: zero receiver");
        if (sendParam.dstEid != 0) {
            require(sendParam.to != bytes32(0), "OVaultComposerMulti: zero destination");
        }

        // Validate msg.value
        if (msg.value < minMsgValue) revert InsufficientMsgValue();

        OVaultComposerMultiStorage storage $ = _getOVaultComposerMultiStorage();

        // Approve exact amount for redemption
        IERC20(SHARE_ERC20).forceApprove($.redemptionPipe, _shareAmount);

        // Redeem shares for underlying asset
        address redeemer = _composeFrom.bytes32ToAddress();

        // If cross-chain send is needed, redeem to composer first, otherwise to receiver
        address assetReceiver = sendParam.dstEid != 0 ? address(this) : receiver;

        // Composer owns the shares (received via LayerZero), so composer is the controller
        uint256 assets = IRedemptionPipe($.redemptionPipe).redeem(_shareAmount, assetReceiver, address(this));

        // Check slippage
        _assertSlippage(assets, minAssets);

        // Determine asset recipient: if cross-chain, use sendParam.to, otherwise use receiver
        address assetRecipient = sendParam.dstEid != 0 
            ? sendParam.to.bytes32ToAddress() 
            : receiver;

        emit CrossChainRedemption(redeemer, assetRecipient, _srcEid, sendParam.dstEid, _shareAmount, assets);

        // If sendParam provided, send assets cross-chain
        if (sendParam.dstEid != 0) {
            sendParam.amountLD = assets;

            // Calculate minimum after dust removal to protect against decimal conversion losses
            sendParam.minAmountLD = _calculateMinAmountAfterDust(
                $.underlyingAssetOFT,
                assets,
                minAssets
            );

            // Quote OFT to get exact amount after dedusting
            (,, OFTReceipt memory receipt) = IOFT($.underlyingAssetOFT).quoteOFT(sendParam);
            uint256 amountToSend = receipt.amountSentLD;

            // Approve only the exact amount that will be sent
            IERC20($.underlyingAsset).forceApprove($.underlyingAssetOFT, amountToSend);

            // Update sendParam with the exact amount
            sendParam.amountLD = amountToSend;
            
            
            // Use feeRefundRecipient if provided, otherwise fallback to redeemer
            address refundRecipient = feeRefundRecipient != bytes32(0)
                ? feeRefundRecipient.bytes32ToAddress()
                : redeemer;

            _send($.underlyingAssetOFT, sendParam, refundRecipient);

            // Refund dust to redeemer
            uint256 dust = assets - amountToSend;
            if (dust > 0) {
                IERC20($.underlyingAsset).safeTransfer(redeemer, dust);
                emit DustRefunded($.underlyingAsset, redeemer, dust);
            }
        }
    }

    /**
     * @notice Check if asset is supported
     */
    function isAssetSupported(address asset) external view returns (bool) {
        OVaultComposerMultiStorage storage $ = _getOVaultComposerMultiStorage();
        return $.depositPipes[asset] != address(0);
    }

    /**
     * @notice Returns the list of all supported asset addresses.
     * @dev uses "parallel" array to track assets in depositPipes mapping
     */
    function getSupportedAssets() external view returns (address[] memory) {
        OVaultComposerMultiStorage storage $ = _getOVaultComposerMultiStorage();
        return $.supportedAssets;
    }

    /**
     * @notice Recover tokens from the contract (timelock-protected)
     * @param token Token address to recover
     * @param to Recipient address
     * @param amount Amount to recover
     */
    function recoverToken(address token, address to, uint256 amount)
        external
        onlyRole(RECOVER_ASSETS_MANAGER_ROLE)
    {
        require(token != address(0), "OVaultComposerMulti: zero token");
        require(to != address(0), "OVaultComposerMulti: zero recipient");
        require(amount > 0, "OVaultComposerMulti: zero amount");
        IERC20(token).safeTransfer(to, amount);
    }

    /**
     * @notice Set the timelock controller
     * @param _timeLockController New timelock controller address
     * @dev Can only be called by the current timelock (with delay enforced by VaultTimelockController)
     */
    function setTimelockController(address _timeLockController) external onlyTimelock {
        require(_timeLockController != address(0), "OVaultComposerMulti: zero timelock");

        OVaultComposerMultiStorage storage $ = _getOVaultComposerMultiStorage();
        address oldTimelock = $.timeLockController;
        $.timeLockController = _timeLockController;

        emit TimelockControllerSet(oldTimelock, _timeLockController);
    }

    // Public getter functions for storage variables
    function timeLockController() external view returns (address) {
        OVaultComposerMultiStorage storage $ = _getOVaultComposerMultiStorage();
        return $.timeLockController;
    }

    function depositPipes(address asset) external view returns (address) {
        OVaultComposerMultiStorage storage $ = _getOVaultComposerMultiStorage();
        return $.depositPipes[asset];
    }

    function assetOFTs(address asset) external view returns (address) {
        OVaultComposerMultiStorage storage $ = _getOVaultComposerMultiStorage();
        return $.assetOFTs[asset];
    }

    function redemptionPipe() external view returns (address) {
        OVaultComposerMultiStorage storage $ = _getOVaultComposerMultiStorage();
        return $.redemptionPipe;
    }

    function underlyingAsset() external view returns (address) {
        OVaultComposerMultiStorage storage $ = _getOVaultComposerMultiStorage();
        return $.underlyingAsset;
    }

    function underlyingAssetOFT() external view returns (address) {
        OVaultComposerMultiStorage storage $ = _getOVaultComposerMultiStorage();
        return $.underlyingAssetOFT;
    }

    function approvedOFTs(address oft) external view returns (bool) {
        OVaultComposerMultiStorage storage $ = _getOVaultComposerMultiStorage();
        return $.approvedOFTs[oft];
    }

    function remotePeers(address oft, uint32 srcEid) external view returns (bytes32) {
        OVaultComposerMultiStorage storage $ = _getOVaultComposerMultiStorage();
        return $.remotePeers[oft][srcEid];
    }

    /**
     * @notice Pause the contract (emergency stop)
     * @dev Can only be called by EMERGENCY_MANAGER_ROLE
     */
    function pause() external onlyRole(EMERGENCY_MANAGER_ROLE) {
        _pause();
    }

    /**
     * @notice Unpause the contract
     * @dev Can only be called by EMERGENCY_MANAGER_ROLE
     */
    function unpause() external onlyRole(EMERGENCY_MANAGER_ROLE) {
        _unpause();
    }

    /**
     * @notice Set OFT approval status for compose messages
     * @param oft OFT address
     * @param approved Approval status
     */
    function setOFTApproval(address oft, bool approved) external onlyTimelock {
        require(oft != address(0), "OVaultComposerMulti: zero OFT");
        OVaultComposerMultiStorage storage $ = _getOVaultComposerMultiStorage();
        $.approvedOFTs[oft] = approved;
        emit OFTApprovalSet(oft, approved);
    }

    /**
     * @notice Set remote peer for an OFT on a specific source chain
     * @param oft The OFT address
     * @param srcEid The source endpoint ID
     * @param remotePeer The expected peer address on the source chain
     */
    function setRemotePeer(address oft, uint32 srcEid, bytes32 remotePeer) external onlyTimelock {
        require(oft != address(0), "OVaultComposerMulti: zero OFT");
        OVaultComposerMultiStorage storage $ = _getOVaultComposerMultiStorage();
        $.remotePeers[oft][srcEid] = remotePeer;
        emit RemotePeerSet(oft, srcEid, remotePeer);
    }

    /**
     * @notice Set remote peer using address (converts to bytes32)
     * @param oft The OFT address
     * @param srcEid The source endpoint ID
     * @param remotePeer The expected peer address on the source chain
     */
    function setRemotePeer(address oft, uint32 srcEid, address remotePeer) external onlyTimelock {
        require(oft != address(0), "OVaultComposerMulti: zero OFT");
        require(remotePeer != address(0), "OVaultComposerMulti: zero peer");
        OVaultComposerMultiStorage storage $ = _getOVaultComposerMultiStorage();
        bytes32 peer = bytes32(uint256(uint160(remotePeer)));
        $.remotePeers[oft][srcEid] = peer;
        emit RemotePeerSet(oft, srcEid, peer);
    }

    /**
     * @notice Calculate minimum amount after accounting for OFT dust removal
     * @dev Ensures slippage protection accounts for decimal conversion rate dust removal
     * @param _oft The OFT address to query for decimal conversion rate
     * @param _actualAmount The actual amount being sent
     * @param _userMinAmount The user's original minimum amount requirement
     * @return minAmountLD The adjusted minimum amount after dust removal
     */
    function _calculateMinAmountAfterDust(
        address _oft,
        uint256 _actualAmount,
        uint256 _userMinAmount
    ) internal view returns (uint256 minAmountLD) {
        // Get the decimal conversion rate from the OFT
        // This is the rate used by LayerZero's _removeDust function
        uint256 conversionRate = _getDecimalConversionRate(_oft);

        // Simulate dust removal: (_actualAmount / conversionRate) * conversionRate
        uint256 amountAfterDust = (_actualAmount / conversionRate) * conversionRate;

        // Apply user's slippage tolerance to the dust-removed amount
        // If user wanted at least X, and dust removal reduces the amount,
        // we need to ensure the final amount meets the slippage requirement
        if (_userMinAmount > 0) {
            // Calculate what percentage of the actual amount the user minimum represents
            // Then apply that percentage to the dust-removed amount
            // This maintains the user's slippage tolerance relative to what they'll actually receive
            uint256 slippageAmount = _actualAmount - _userMinAmount;

            // If dust removal would exceed the user's slippage tolerance, revert
            // This protects users from excessive losses due to decimal conversion
            if (_actualAmount - amountAfterDust > slippageAmount) {
                revert SlippageExceedsDustRemoval(amountAfterDust, slippageAmount);
            }
            if (amountAfterDust <= slippageAmount) {
                minAmountLD = 0;
                return minAmountLD;
            }

            // Calculate minimum as: amountAfterDust - (proportional slippage)
            minAmountLD = amountAfterDust - slippageAmount;
        } else {
            // If user set minAmount to 0, maintain that (accept any amount)
            minAmountLD = 0;
        }
        
        return minAmountLD;
    }

    /**
     * @notice Get the decimal conversion rate from an OFT contract
     * @dev Computes the rate as 10 ** (localDecimals - sharedDecimals)
     * @param _oft The OFT address to query
     * @return conversionRate The decimal conversion rate
     */
    function _getDecimalConversionRate(address _oft) internal view returns (uint256 conversionRate) {
        IOFT oft = IOFT(_oft);

        // Get the underlying token address
        address token = oft.token();

        // Get local decimals from the token
        uint8 localDecimals = IERC20Metadata(token).decimals();

        // Get shared decimals from the OFT
        uint8 sharedDecimals = oft.sharedDecimals();

        // Calculate conversion rate: 10 ** (localDecimals - sharedDecimals)
        conversionRate = 10 ** (localDecimals - sharedDecimals);
    }

    /**
     * @dev Adds a new supported asset.
     * @dev The calling function should ensure that pipe and asset exist, and depositPipes[asset] != pipe
     */
    function _addAsset(address asset, address pipe) internal {
        OVaultComposerMultiStorage storage $ = _getOVaultComposerMultiStorage();

        // Ensure the asset is not already added
        if ($.depositPipes[asset] == address(0)) {
            $.assetIndex[asset] = $.supportedAssets.length;
            $.supportedAssets.push(asset);
        }
        $.depositPipes[asset] = pipe;
    }

    /**
     * @dev Removes a supported asset efficiently using the "swap-and-pop" pattern.
     * This avoids a costly loop to shift all elements in the array.
     * @dev The calling function should ensure that depositPipes[asset] mapping exists
     */
    function _removeAsset(address asset) internal {
        OVaultComposerMultiStorage storage $ = _getOVaultComposerMultiStorage();

        // Get the index of the asset to remove
        uint256 indexToRemove = $.assetIndex[asset];

        // Get the address of the last asset in the array
        address lastAsset = $.supportedAssets[$.supportedAssets.length - 1];

        // Move the last asset to the position of the one being removed
        $.supportedAssets[indexToRemove] = lastAsset;

        // Update the index mapping for the moved asset
        $.assetIndex[lastAsset] = indexToRemove;

        // Remove the last element from the array (which is now a duplicate)
        $.supportedAssets.pop();

        // Delete the original asset from the mappings
        delete $.depositPipes[asset];
        delete $.assetIndex[asset];
    }

    /**
     * @notice Implementation of _isApprovedOFT from VaultComposerBase
     * @param _oft The OFT address to check
     * @return bool True if the OFT is approved
     */
    function _isApprovedOFT(address _oft) internal view override returns (bool) {
        OVaultComposerMultiStorage storage $ = _getOVaultComposerMultiStorage();
        return $.approvedOFTs[_oft];
    }

    /**
     * @notice Implementation of _getRemotePeer from VaultComposerBase
     * @param _oft The OFT address
     * @param _srcEid The source endpoint ID
     * @return bytes32 The expected peer address
     */
    function _getRemotePeer(address _oft, uint32 _srcEid) internal view override returns (bytes32) {
        OVaultComposerMultiStorage storage $ = _getOVaultComposerMultiStorage();
        return $.remotePeers[_oft][_srcEid];
    }
}