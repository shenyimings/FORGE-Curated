// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

/// @title INetworkMiddleware
/// @author kexley, @capLabs
/// @notice Interface for Network Middleware contract
interface INetworkMiddleware {
    /// @custom:storage-location erc7201:cap.storage.NetworkMiddleware
    struct NetworkMiddlewareStorage {
        address network;
        address vaultRegistry;
        address oracle;
        uint48 requiredEpochDuration;
        uint256 feeAllowed;
        mapping(address => address) stakerRewarders; // vault => stakerRewarder
        mapping(address => address[]) vaults; // agent => vault[]
    }

    enum SlasherType {
        INSTANT,
        VETO
    }

    enum DelegatorType {
        NETWORK_RESTAKE,
        FULL_RESTAKE,
        OPERATOR_SPECIFIC,
        OPERATOR_NETWORK_SPECIFIC
    }

    /// @dev Vault registered
    event VaultRegistered(address vault);
    /// @dev Slash event
    event Slash(address indexed agent, address recipient, uint256 amount);

    /// @dev Invalid slasher
    error InvalidSlasher();

    /// @dev Invalid delegator
    error InvalidDelegator();

    /// @dev Not a vault
    error NotVault();

    /// @dev No slasher
    error NoSlasher();

    /// @dev No burner
    error NoBurner();

    /// @dev Invalid burner router
    error InvalidBurnerRouter();

    /// @dev No staker rewarder
    error NoStakerRewarder();

    /// @dev Vault not initialized
    error VaultNotInitialized();

    /// @dev Invalid epoch duration
    error InvalidEpochDuration(uint48 required, uint48 actual);

    /// @dev No slashable collateral
    error NoSlashableCollateral();

    /// @notice Register vault to be used as collateral within the CAP system
    /// @param _vault Vault address
    /// @param _agents Agents supported by the vault
    function registerVault(address _vault, address _stakerRewarder, address[] calldata _agents) external;

    /// @notice Set fee allowed
    /// @param _feeAllowed Fee allowed to be charged on rewards by restakers
    function setFeeAllowed(uint256 _feeAllowed) external;

    /// @notice Slash delegation and send to recipient
    /// @param _agent Agent address
    /// @param _recipient Recipient of the slashed assets
    /// @param _slashShare Percentage of delegation to slash encoded with 18 decimals
    /// @param _timestamp Timestamp to slash at
    function slash(address _agent, address _recipient, uint256 _slashShare, uint48 _timestamp) external;

    /// @notice Coverage of an agent by a specific vault at a given timestamp
    /// @param _network Network address
    /// @param _agent Agent address
    /// @param _vault Vault address
    /// @param _oracle Oracle address
    /// @param _timestamp Timestamp to check coverage at
    /// @return collateralValue Coverage value in USD (8 decimals)
    /// @return collateral Coverage amount in the vault's collateral token decimals
    function coverageByVault(address _network, address _agent, address _vault, address _oracle, uint48 _timestamp)
        external
        view
        returns (uint256 collateralValue, uint256 collateral);

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
    ) external view returns (uint256 collateralValue, uint256 collateral);

    /// @notice Coverage of an agent by Symbiotic vaults
    /// @param _agent Agent address
    /// @return delegation Delegation amount in USD (8 decimals)
    function coverage(address _agent) external view returns (uint256 delegation);

    /// @notice Slashable collateral of an agent by Symbiotic vaults
    /// @param _agent Agent address
    /// @param _timestamp Timestamp to check slashable collateral at
    /// @return _slashableCollateral Slashable collateral amount in USD (8 decimals)
    function slashableCollateral(address _agent, uint48 _timestamp)
        external
        view
        returns (uint256 _slashableCollateral);

    /// @notice Registered vaults for an agent
    /// @param _agent Agent address
    /// @return vaultAddresses Vault addresses
    function vaults(address _agent) external view returns (address[] memory vaultAddresses);

    /// @notice Distribute rewards accumulated by the agent borrowing
    /// @param _agent Agent address
    /// @param _token Token address
    function distributeRewards(address _agent, address _token) external;
}
