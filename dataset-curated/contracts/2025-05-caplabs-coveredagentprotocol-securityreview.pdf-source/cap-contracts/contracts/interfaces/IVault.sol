// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/// @title Vault interface for storing the backing for cTokens
/// @author kexley, @capLabs
/// @notice Interface for the Vault contract which handles supplies, borrows and utilization tracking
interface IVault {
    /// @custom:storage-location erc7201:cap.storage.Vault
    struct VaultStorage {
        EnumerableSet.AddressSet assets;
        mapping(address => uint256) totalSupplies;
        mapping(address => uint256) totalBorrows;
        mapping(address => uint256) utilizationIndex;
        mapping(address => uint256) lastUpdate;
        mapping(address => bool) paused;
        address insuranceFund;
    }

    /// @dev Parameters for minting or burning
    struct MintBurnParams {
        address asset;
        uint256 amountIn;
        uint256 amountOut;
        uint256 minAmountOut;
        address receiver;
        uint256 deadline;
        uint256 fee;
    }

    /// @dev Parameters for redeeming
    struct RedeemParams {
        uint256 amountIn;
        uint256[] amountsOut;
        uint256[] minAmountsOut;
        address receiver;
        uint256 deadline;
        uint256[] fees;
    }

    /// @dev Parameters for borrowing
    struct BorrowParams {
        address asset;
        uint256 amount;
        address receiver;
    }

    /// @dev Parameters for repaying
    struct RepayParams {
        address asset;
        uint256 amount;
    }

    /// @notice Mint the cap token using an asset
    /// @dev This contract must have approval to move asset from msg.sender
    /// @param _asset Whitelisted asset to deposit
    /// @param _amountIn Amount of asset to use in the minting
    /// @param _minAmountOut Minimum amount to mint
    /// @param _receiver Receiver of the minting
    /// @param _deadline Deadline of the tx
    function mint(address _asset, uint256 _amountIn, uint256 _minAmountOut, address _receiver, uint256 _deadline)
        external
        returns (uint256 amountOut);

    /// @notice Burn the cap token for an asset
    /// @dev Asset is withdrawn from the reserve or divested from the underlying vault
    /// @param _asset Asset to withdraw
    /// @param _amountIn Amount of cap token to burn
    /// @param _minAmountOut Minimum amount out to receive
    /// @param _receiver Receiver of the withdrawal
    /// @param _deadline Deadline of the tx
    function burn(address _asset, uint256 _amountIn, uint256 _minAmountOut, address _receiver, uint256 _deadline)
        external
        returns (uint256 amountOut);

    /// @notice Redeem the Cap token for a bundle of assets
    /// @dev Assets are withdrawn from the reserve or divested from the underlying vault
    /// @param _amountIn Amount of Cap token to burn
    /// @param _minAmountsOut Minimum amounts of assets to withdraw
    /// @param _receiver Receiver of the withdrawal
    /// @param _deadline Deadline of the tx
    /// @return amountsOut Amount of assets withdrawn
    function redeem(uint256 _amountIn, uint256[] calldata _minAmountsOut, address _receiver, uint256 _deadline)
        external
        returns (uint256[] memory amountsOut);

    /// @notice Borrow an asset
    /// @dev Whitelisted agents can borrow any amount, LTV is handled by Agent contracts
    /// @param _asset Asset to borrow
    /// @param _amount Amount of asset to borrow
    /// @param _receiver Receiver of the borrow
    function borrow(address _asset, uint256 _amount, address _receiver) external;

    /// @notice Repay an asset
    /// @param _asset Asset to repay
    /// @param _amount Amount of asset to repay
    function repay(address _asset, uint256 _amount) external;

    /// @notice Add an asset to the vault list
    /// @param _asset Asset address
    function addAsset(address _asset) external;

    /// @notice Remove an asset from the vault list
    /// @param _asset Asset address
    function removeAsset(address _asset) external;

    /// @notice Pause an asset
    /// @param _asset Asset address
    function pause(address _asset) external;

    /// @notice Unpause an asset
    /// @param _asset Asset address
    function unpause(address _asset) external;

    /// @notice Rescue an unsupported asset
    /// @param _asset Asset to rescue
    /// @param _receiver Receiver of the rescue
    function rescueERC20(address _asset, address _receiver) external;

    /// @notice Get the list of assets supported by the vault
    /// @return assetList List of assets
    function assets() external view returns (address[] memory assetList);

    /// @notice Get the total supplies of an asset
    /// @param _asset Asset address
    /// @return totalSupply Total supply
    function totalSupplies(address _asset) external view returns (uint256 totalSupply);

    /// @notice Get the total borrows of an asset
    /// @param _asset Asset address
    /// @return totalBorrow Total borrow
    function totalBorrows(address _asset) external view returns (uint256 totalBorrow);

    /// @notice Get the pause state of an asset
    /// @param _asset Asset address
    /// @return isPaused Pause state
    function paused(address _asset) external view returns (bool isPaused);

    /// @notice Available balance to borrow
    /// @param _asset Asset to borrow
    /// @return amount Amount available
    function availableBalance(address _asset) external view returns (uint256 amount);

    /// @notice Utilization rate of an asset
    /// @dev Utilization scaled by 1e27
    /// @param _asset Utilized asset
    /// @return ratio Utilization ratio
    function utilization(address _asset) external view returns (uint256 ratio);

    /// @notice Up to date cumulative utilization index of an asset
    /// @dev Utilization scaled by 1e27
    /// @param _asset Utilized asset
    /// @return index Utilization ratio index
    function currentUtilizationIndex(address _asset) external view returns (uint256 index);

    /// @notice Get the insurance fund
    /// @return insuranceFund Insurance fund
    function insuranceFund() external view returns (address);
}
