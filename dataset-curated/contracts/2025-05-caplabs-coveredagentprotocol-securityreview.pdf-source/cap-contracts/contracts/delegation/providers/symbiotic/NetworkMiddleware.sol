// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { Access } from "../../../access/Access.sol";
import { IOracle } from "../../../interfaces/IOracle.sol";
import { IStakerRewards } from "../../../interfaces/IStakerRewards.sol";

import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IBurnerRouter } from "@symbioticfi/burners/src/interfaces/router/IBurnerRouter.sol";

import { IMiddleware } from "../../../interfaces/IMiddleware.sol";

import { INetworkMiddleware } from "../../../interfaces/INetworkMiddleware.sol";
import { NetworkMiddlewareStorageUtils } from "../../../storage/NetworkMiddlewareStorageUtils.sol";
import { Subnetwork } from "@symbioticfi/core/src/contracts/libraries/Subnetwork.sol";
import { IEntity } from "@symbioticfi/core/src/interfaces/common/IEntity.sol";
import { IRegistry } from "@symbioticfi/core/src/interfaces/common/IRegistry.sol";
import { IBaseDelegator } from "@symbioticfi/core/src/interfaces/delegator/IBaseDelegator.sol";
import { ISlasher } from "@symbioticfi/core/src/interfaces/slasher/ISlasher.sol";
import { IVault } from "@symbioticfi/core/src/interfaces/vault/IVault.sol";

/// @title Cap Symbiotic Network Middleware Contract
/// @author Cap Labs
/// @notice This contract manages the symbiotic collateral and slashing.
contract NetworkMiddleware is INetworkMiddleware, UUPSUpgradeable, Access, NetworkMiddlewareStorageUtils {
    using SafeERC20 for IERC20;

    /// @notice Initialize
    /// @param _accessControl Access control address
    /// @param _network Network address
    /// @param _vaultRegistry Vault registry address
    /// @param _oracle Oracle address
    /// @param _requiredEpochDuration Required epoch duration in seconds
    /// @param _feeAllowed Fee allowed to be charged on rewards by restakers
    function initialize(
        address _accessControl,
        address _network,
        address _vaultRegistry,
        address _oracle,
        uint48 _requiredEpochDuration,
        uint256 _feeAllowed
    ) external initializer {
        __Access_init(_accessControl);
        NetworkMiddlewareStorage storage $ = getNetworkMiddlewareStorage();
        $.network = _network;
        $.vaultRegistry = _vaultRegistry;
        $.oracle = _oracle;
        $.requiredEpochDuration = _requiredEpochDuration;
        $.feeAllowed = _feeAllowed;
    }

    /// @notice Register vault to be used as collateral within the CAP system
    /// @param _vault Vault address
    /// @param _agents Agents supported by the vault
    function registerVault(address _vault, address _stakerRewarder, address[] calldata _agents)
        external
        checkAccess(this.registerVault.selector)
    {
        _verifyVault(_vault);
        NetworkMiddlewareStorage storage $ = getNetworkMiddlewareStorage();
        $.stakerRewarders[_vault] = _stakerRewarder;
        for (uint256 i; i < _agents.length; ++i) {
            $.vaults[_agents[i]].push(_vault);
        }
        emit VaultRegistered(_vault);
    }

    /// @notice Set fee allowed
    /// @param _feeAllowed Fee allowed to be charged on rewards by restakers
    function setFeeAllowed(uint256 _feeAllowed) external checkAccess(this.setFeeAllowed.selector) {
        getNetworkMiddlewareStorage().feeAllowed = _feeAllowed;
    }

    /// @notice Slash delegation and send to recipient
    /// @param _agent Agent address
    /// @param _recipient Recipient of the slashed assets
    /// @param _slashShare Percentage of delegation to slash encoded with 18 decimals
    /// @param _timestamp Timestamp to slash at
    function slash(address _agent, address _recipient, uint256 _slashShare, uint48 _timestamp)
        external
        checkAccess(this.slash.selector)
    {
        NetworkMiddlewareStorage storage $ = getNetworkMiddlewareStorage();

        for (uint256 i; i < $.vaults[_agent].length; ++i) {
            IVault vault = IVault($.vaults[_agent][i]);

            (, uint256 totalSlashableCollateral) =
                slashableCollateralByVault($.network, _agent, address(vault), $.oracle, _timestamp);
            if (totalSlashableCollateral == 0) continue;

            // Round up in favor of the liquidator
            uint256 slashShareOfCollateral = (totalSlashableCollateral * _slashShare / 1e18) + 1;

            // If the slash share is greater than the total slashable collateral, set it to the total slashable collateral
            if (slashShareOfCollateral > totalSlashableCollateral) {
                slashShareOfCollateral = totalSlashableCollateral;
            }

            ISlasher(vault.slasher()).slash(
                subnetwork(_agent), _agent, slashShareOfCollateral, _timestamp, new bytes(0)
            );

            // TODO: the burner could be a non routing burner, could add hooks?
            IBurnerRouter(vault.burner()).triggerTransfer(address(this));
            IERC20(vault.collateral()).safeTransfer(_recipient, slashShareOfCollateral);

            emit Slash(_agent, _recipient, slashShareOfCollateral);
        }
    }

    /// @dev Get vault info
    /// @param _network Network address
    /// @param _agent Agent address
    /// @param _vault Vault address
    /// @param _oracle Oracle address
    /// @return burnerRouter The burner router contract
    /// @return decimals The collateral token decimals
    /// @return collateralPrice The collateral token price
    function _getVaultInfo(address _network, address _agent, address _vault, address _oracle)
        private
        view
        returns (IBurnerRouter burnerRouter, uint8 decimals, uint256 collateralPrice)
    {
        burnerRouter = IBurnerRouter(IVault(_vault).burner());

        // Check pending receivers
        (address pendingReceiver,) = burnerRouter.pendingNetworkReceiver(_network);
        if (pendingReceiver != address(0) && pendingReceiver != address(this)) {
            return (IBurnerRouter(address(0)), 0, 0);
        }

        (pendingReceiver,) = burnerRouter.pendingOperatorNetworkReceiver(_network, _agent);
        if (pendingReceiver != address(0) && pendingReceiver != address(this)) {
            return (IBurnerRouter(address(0)), 0, 0);
        }

        address collateralAddress = IVault(_vault).collateral();
        decimals = IERC20Metadata(collateralAddress).decimals();
        (collateralPrice,) = IOracle(_oracle).getPrice(collateralAddress);
    }

    /// @notice Coverage of an agent by a specific vault at a given timestamp
    /// @param _network Network address
    /// @param _agent Agent address
    /// @param _vault Vault address
    /// @param _oracle Oracle address
    /// @param _timestamp Timestamp to check coverage at
    /// @return collateralValue Coverage value in USD (8 decimals)
    /// @return collateral Coverage amount in the vault's collateral token decimals
    function coverageByVault(address _network, address _agent, address _vault, address _oracle, uint48 _timestamp)
        public
        view
        returns (uint256 collateralValue, uint256 collateral)
    {
        (IBurnerRouter burnerRouter, uint8 decimals, uint256 collateralPrice) =
            _getVaultInfo(_network, _agent, _vault, _oracle);

        if (address(burnerRouter) == address(0)) return (0, 0);

        collateral = IBaseDelegator(IVault(_vault).delegator()).stakeAt(subnetwork(_agent), _agent, _timestamp, "");
        collateralValue = collateral * collateralPrice / (10 ** decimals);
    }

    /// @notice Slashable collateral of an agent by a specific vault at a given timestamp
    /// @param _network Network address
    /// @param _agent Agent address
    /// @param _vault Vault address
    /// @param _oracle Oracle address
    /// @param _timestamp Timestamp to check slashable collateral at
    /// @return collateralValue Slashable collateral value in USD (8 decimals)
    function slashableCollateralByVault(
        address _network,
        address _agent,
        address _vault,
        address _oracle,
        uint48 _timestamp
    ) public view returns (uint256 collateralValue, uint256 collateral) {
        (IBurnerRouter burnerRouter, uint8 decimals, uint256 collateralPrice) =
            _getVaultInfo(_network, _agent, _vault, _oracle);

        if (address(burnerRouter) == address(0)) return (0, 0);

        ISlasher slasher = ISlasher(IVault(_vault).slasher());
        collateral = slasher.slashableStake(subnetwork(_agent), _agent, _timestamp, "");
        collateralValue = collateral * collateralPrice / (10 ** decimals);
    }

    /// @notice Coverage of an agent by Symbiotic vaults
    /// @param _agent Agent address
    /// @return delegation Delegation amount in USD (8 decimals)
    function coverage(address _agent) public view returns (uint256 delegation) {
        NetworkMiddlewareStorage storage $ = getNetworkMiddlewareStorage();
        address[] memory _vaults = $.vaults[_agent];
        address _network = $.network;
        address _oracle = $.oracle;
        uint48 _timestamp = uint48(block.timestamp);

        for (uint256 i = 0; i < _vaults.length; i++) {
            (uint256 value,) = coverageByVault(_network, _agent, _vaults[i], _oracle, _timestamp);
            delegation += value;
        }
    }

    /// @notice Slashable collateral of an agent by Symbiotic vaults
    /// @param _agent Agent address
    /// @param _timestamp Timestamp to check slashable collateral at
    /// @return _slashableCollateral Slashable collateral amount in USD (8 decimals)
    function slashableCollateral(address _agent, uint48 _timestamp)
        external
        view
        returns (uint256 _slashableCollateral)
    {
        NetworkMiddlewareStorage storage $ = getNetworkMiddlewareStorage();
        address[] memory _vaults = $.vaults[_agent];
        address _network = $.network;
        address _oracle = $.oracle;

        for (uint256 i = 0; i < _vaults.length; i++) {
            (uint256 value,) = slashableCollateralByVault(_network, _agent, _vaults[i], _oracle, _timestamp);
            _slashableCollateral += value;
        }
    }

    /// @notice Subnetwork id
    /// @dev Creates a collision resistant uint96 identifier by taking keccak256 hash of agent address
    /// and using the first 96 bits of the hash
    /// @param _agent Agent address
    /// @return id Subnetwork identifier (first 96 bits of keccak256 hash of agent address)
    function subnetworkIdentifier(address _agent) public pure returns (uint96 id) {
        bytes32 hash = keccak256(abi.encodePacked(_agent));
        id = uint96(uint256(hash)); // Takes first 96 bits of hash
    }

    /// @notice Subnetwork id concatenated with network address
    /// @return id Subnetwork id
    function subnetwork(address _agent) public view returns (bytes32 id) {
        id = Subnetwork.subnetwork(getNetworkMiddlewareStorage().network, subnetworkIdentifier(_agent));
    }

    /// @notice Registered vaults for an agent
    /// @param _agent Agent address
    /// @return vaultAddresses Vault addresses
    function vaults(address _agent) external view returns (address[] memory vaultAddresses) {
        vaultAddresses = getNetworkMiddlewareStorage().vaults[_agent];
    }

    /// @dev Verify a vault has the required specifications
    /// @param _vault Vault address
    function _verifyVault(address _vault) internal view {
        NetworkMiddlewareStorage storage $ = getNetworkMiddlewareStorage();

        if (!IRegistry($.vaultRegistry).isEntity(_vault)) {
            revert NotVault();
        }

        if (!IVault(_vault).isInitialized()) revert VaultNotInitialized();

        uint48 vaultEpoch = IVault(_vault).epochDuration();
        if (vaultEpoch < $.requiredEpochDuration) revert InvalidEpochDuration($.requiredEpochDuration, vaultEpoch);

        address slasher = IVault(_vault).slasher();
        uint64 slasherType = IEntity(slasher).TYPE();
        if (slasher == address(0)) revert NoSlasher();
        if (slasherType != uint64(INetworkMiddleware.SlasherType.INSTANT)) revert InvalidSlasher();

        address burner = IVault(_vault).burner();
        if (burner == address(0)) revert NoBurner();
        address receiver = IBurnerRouter(burner).networkReceiver($.network);
        if (receiver != address(this)) revert InvalidBurnerRouter();

        address delegator = IVault(_vault).delegator();
        uint64 delegatorType = IEntity(delegator).TYPE();
        if (delegatorType != uint64(INetworkMiddleware.DelegatorType.NETWORK_RESTAKE)) revert InvalidDelegator();
    }

    /// @notice Distribute rewards accumulated by the agent borrowing
    /// @param _agent Agent address
    /// @param _token Token address
    function distributeRewards(address _agent, address _token) external checkAccess(this.distributeRewards.selector) {
        NetworkMiddlewareStorage storage $ = getNetworkMiddlewareStorage();
        uint256 totalCollateralValue = coverage(_agent);
        uint256 _amount = IERC20(_token).balanceOf(address(this));

        // here, distribute proportionally to the collateral value of the vaults
        address[] memory _vaults = $.vaults[_agent];
        for (uint256 i = 0; i < _vaults.length; i++) {
            address vault = _vaults[i];
            (uint256 collateralValue,) = coverageByVault($.network, _agent, vault, $.oracle, uint48(block.timestamp));
            uint256 reward = _amount * collateralValue / totalCollateralValue;
            address stakerRewarder = $.stakerRewarders[vault];
            if (stakerRewarder == address(0)) revert NoStakerRewarder();

            IERC20(_token).forceApprove(address(IStakerRewards(stakerRewarder)), reward);
            IStakerRewards(stakerRewarder).distributeRewards(
                $.network, _token, reward, abi.encode(uint48(block.timestamp - 1), $.feeAllowed, "", "")
            );
        }
    }

    /// @dev Only admin can upgrade
    function _authorizeUpgrade(address) internal override checkAccess(bytes4(0)) { }
}
