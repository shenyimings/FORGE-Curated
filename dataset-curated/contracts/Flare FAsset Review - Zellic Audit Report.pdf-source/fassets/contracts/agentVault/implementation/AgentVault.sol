// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuard} from "../../openzeppelin/security/ReentrancyGuard.sol";
import {IIAgentVault} from "../../agentVault/interfaces/IIAgentVault.sol";
import {IAgentVault} from "../../userInterfaces/IAgentVault.sol";
import {IIAssetManager} from "../../assetManager/interfaces/IIAssetManager.sol";
import {ICollateralPool} from "../../userInterfaces/ICollateralPool.sol";


contract AgentVault is ReentrancyGuard, UUPSUpgradeable, IIAgentVault, IERC165 {
    using SafeERC20 for IERC20;

    IIAssetManager public assetManager; // practically immutable

    bool private initialized;

    IERC20[] private __usedTokens; // only storage placeholder
    mapping(IERC20 => uint256) private __tokenUseFlags; // only storage placeholder
    bool private __internalWithdrawal; // only storage placeholder

    bool private destroyed;

    modifier onlyOwner {
        require(isOwner(msg.sender), OnlyOwner());
        _;
    }

    modifier onlyAssetManager {
        require(msg.sender == address(assetManager), OnlyAssetManager());
        _;
    }

    modifier onlyKnownToken(IERC20 _token) {
        _validateToken(_token);
        _;
    }

    // Only used in some tests.
    // The implementation in production will always be deployed with address(0) for _assetManager.
    constructor(IIAssetManager _assetManager) {
        initialize(_assetManager);
    }

    function initialize(IIAssetManager _assetManager) public {
        require(!initialized, AlreadyInitialized());
        initialized = true;
        assetManager = _assetManager;
        initializeReentrancyGuard();
    }

    function buyCollateralPoolTokens()
        external payable
        onlyOwner
    {
        collateralPool().enter{value: msg.value}();
    }

    function withdrawPoolFees(uint256 _amount, address _recipient)
        external
        onlyOwner
    {
        collateralPool().withdrawFeesTo(_amount, _recipient);
    }

    function redeemCollateralPoolTokens(uint256 _amount, address payable _recipient)
        external
        onlyOwner
        nonReentrant
    {
        ICollateralPool pool = collateralPool();
        assetManager.beforeCollateralWithdrawal(pool.poolToken(), _amount);
        pool.exitTo(_amount, _recipient);
    }

    // must call `token.approve(vault, amount)` before for each token in _tokens
    function depositCollateral(IERC20 _token, uint256 _amount)
        external override
        onlyOwner
        onlyKnownToken(_token)
    {
        _token.safeTransferFrom(msg.sender, address(this), _amount);
        assetManager.updateCollateral(address(this), _token);
    }

    // update collateral after `transfer(vault, some amount)` was called (alternative to depositCollateral)
    function updateCollateral(IERC20 _token)
        external override
        onlyOwner
        onlyKnownToken(_token)
    {
        assetManager.updateCollateral(address(this), _token);
    }

    function withdrawCollateral(IERC20 _token, uint256 _amount, address _recipient)
        external override
        onlyOwner
        onlyKnownToken(_token)
        nonReentrant
    {
        // check that enough was announced and reduce announcement (not relevant after destroy)
        if (!destroyed) {
            assetManager.beforeCollateralWithdrawal(_token, _amount);
        }
        // transfer tokens to recipient
        _token.safeTransfer(_recipient, _amount);
    }

    // Allow transferring a token, airdropped to the agent vault, to the owner (management address).
    // Doesn't work for collateral tokens because this would allow withdrawing the locked collateral.
    function transferExternalToken(IERC20 _token, uint256 _amount)
        external override
        onlyOwner
    {
        require(destroyed || !assetManager.isLockedVaultToken(address(this), _token), OnlyNonCollateralTokens());
        address ownerManagementAddress = assetManager.getAgentVaultOwner(address(this));
        _token.safeTransfer(ownerManagementAddress, _amount);
    }

    /**
     * Used by asset manager when destroying agent.
     * Marks agent as destroyed so that funds can be withdrawn by the agent owner.
     * Note: Can only be called by the asset manager.
     */
    function destroy()
        external override
        onlyAssetManager
        nonReentrant
    {
        destroyed = true;
    }

    // Used by asset manager for liquidation and failed redemption.
    // Is nonReentrant to prevent reentrancy in case the token has receive hooks.
    // No need for onlyKnownToken here, because asset manager will always send valid token.
    function payout(IERC20 _token, address _recipient, uint256 _amount)
        external override
        onlyAssetManager
        nonReentrant
    {
        _token.safeTransfer(_recipient, _amount);
    }

    function collateralPool()
        public view
        returns (ICollateralPool)
    {
        return ICollateralPool(assetManager.getCollateralPool(address(this)));
    }

    function isOwner(address _address)
        public view
        returns (bool)
    {
        return assetManager.isAgentVaultOwner(address(this), _address);
    }

    /**
     * Implementation of ERC-165 interface.
     */
    function supportsInterface(bytes4 _interfaceId)
        external pure override
        returns (bool)
    {
        return _interfaceId == type(IERC165).interfaceId
            || _interfaceId == type(IAgentVault).interfaceId
            || _interfaceId == type(IIAgentVault).interfaceId;
    }

    ////////////////////////////////////////////////////////////////////////////////////
    // UUPS proxy upgrade

    function implementation() external view returns (address) {
        return _getImplementation();
    }

    /**
     * Upgrade calls can only arrive through asset manager.
     * See UUPSUpgradeable._authorizeUpgrade.
     */
    function _authorizeUpgrade(address /* _newImplementation */)
        internal virtual override
        onlyAssetManager
    { // solhint-disable-line no-empty-blocks
    }

    // Check if the token is one of known collateral tokens (not necessarily still valid as collateral),
    // to prevent agent owners attacking the system with malicious tokens.
    function _validateToken(IERC20 _token) private view {
        require(assetManager.isVaultCollateralToken(_token), UnknownToken());
    }
}
