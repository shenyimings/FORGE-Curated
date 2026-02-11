// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { Access } from "../access/Access.sol";

import { IVault } from "../interfaces/IVault.sol";
import { VaultStorageUtils } from "../storage/VaultStorageUtils.sol";
import { FractionalReserve } from "./FractionalReserve.sol";
import { Minter } from "./Minter.sol";
import { VaultLogic } from "./libraries/VaultLogic.sol";
import { ERC20PermitUpgradeable } from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/// @title Vault for storing the backing for cTokens
/// @author kexley, @capLabs
/// @notice Tokens are supplied by cToken minters and borrowed by covered agents
/// @dev Supplies, borrows and utilization rates are tracked. Interest rates should be computed and
/// charged on the external contracts, only the principle amount is counted on this contract.
abstract contract Vault is IVault, ERC20PermitUpgradeable, Access, Minter, FractionalReserve, VaultStorageUtils {
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @dev Initialize the assets
    /// @param _name Name of the cap token
    /// @param _symbol Symbol of the cap token
    /// @param _accessControl Access control address
    /// @param _feeAuction Fee auction address
    /// @param _oracle Oracle address
    /// @param _assets Asset addresses
    /// @param _insuranceFund Insurance fund
    function __Vault_init(
        string memory _name,
        string memory _symbol,
        address _accessControl,
        address _feeAuction,
        address _oracle,
        address[] calldata _assets,
        address _insuranceFund
    ) internal onlyInitializing {
        __ERC20_init(_name, _symbol);
        __ERC20Permit_init(_name);
        __Access_init(_accessControl);
        __FractionalReserve_init(_feeAuction);
        __Minter_init(_oracle);
        __Vault_init_unchained(_assets, _insuranceFund);
    }

    /// @dev Initialize unchained
    /// @param _assets Asset addresses
    /// @param _insuranceFund Insurance fund
    function __Vault_init_unchained(address[] calldata _assets, address _insuranceFund) internal onlyInitializing {
        VaultStorage storage $ = getVaultStorage();
        uint256 length = _assets.length;
        for (uint256 i; i < length; ++i) {
            $.assets.add(_assets[i]);
        }
        $.insuranceFund = _insuranceFund;
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
        returns (uint256 amountOut)
    {
        uint256 fee;
        (amountOut, fee) = getMintAmount(_asset, _amountIn);
        VaultLogic.mint(
            getVaultStorage(),
            MintBurnParams({
                asset: _asset,
                amountIn: _amountIn,
                amountOut: amountOut,
                minAmountOut: _minAmountOut,
                receiver: _receiver,
                deadline: _deadline,
                fee: fee
            })
        );
        _mint(_receiver, amountOut);
        _mint(getVaultStorage().insuranceFund, fee);
    }

    /// @notice Burn the cap token for an asset
    /// @dev Asset is withdrawn from the reserve or divested from the underlying vault
    /// @param _asset Asset to withdraw
    /// @param _amountIn Amount of cap token to burn
    /// @param _minAmountOut Minimum amount out to receive
    /// @param _receiver Receiver of the withdrawal
    /// @param _deadline Deadline of the tx
    function burn(address _asset, uint256 _amountIn, uint256 _minAmountOut, address _receiver, uint256 _deadline)
        external
        returns (uint256 amountOut)
    {
        uint256 fee;
        (amountOut, fee) = getBurnAmount(_asset, _amountIn);
        divest(_asset, amountOut);
        VaultLogic.burn(
            getVaultStorage(),
            MintBurnParams({
                asset: _asset,
                amountIn: _amountIn,
                amountOut: amountOut,
                minAmountOut: _minAmountOut,
                receiver: _receiver,
                deadline: _deadline,
                fee: fee
            })
        );
        _burn(msg.sender, _amountIn);
    }

    /// @notice Redeem the Cap token for a bundle of assets
    /// @dev Assets are withdrawn from the reserve or divested from the underlying vault
    /// @param _amountIn Amount of Cap token to burn
    /// @param _minAmountsOut Minimum amounts of assets to withdraw
    /// @param _receiver Receiver of the withdrawal
    /// @param _deadline Deadline of the tx
    /// @return amountsOut Amount of assets withdrawn
    function redeem(uint256 _amountIn, uint256[] calldata _minAmountsOut, address _receiver, uint256 _deadline)
        external
        returns (uint256[] memory amountsOut)
    {
        uint256[] memory fees;
        (amountsOut, fees) = getRedeemAmount(_amountIn);
        divestMany(assets(), amountsOut);
        VaultLogic.redeem(
            getVaultStorage(),
            RedeemParams({
                amountIn: _amountIn,
                amountsOut: amountsOut,
                minAmountsOut: _minAmountsOut,
                receiver: _receiver,
                deadline: _deadline,
                fees: fees
            })
        );
        _burn(msg.sender, _amountIn);
    }

    /// @notice Borrow an asset
    /// @dev Whitelisted agents can borrow any amount, LTV is handled by Agent contracts
    /// @param _asset Asset to borrow
    /// @param _amount Amount of asset to borrow
    /// @param _receiver Receiver of the borrow
    function borrow(address _asset, uint256 _amount, address _receiver) external checkAccess(this.borrow.selector) {
        divest(_asset, _amount);
        VaultLogic.borrow(getVaultStorage(), BorrowParams({ asset: _asset, amount: _amount, receiver: _receiver }));
    }

    /// @notice Repay an asset
    /// @param _asset Asset to repay
    /// @param _amount Amount of asset to repay
    function repay(address _asset, uint256 _amount) external checkAccess(this.repay.selector) {
        VaultLogic.repay(getVaultStorage(), RepayParams({ asset: _asset, amount: _amount }));
    }

    /// @notice Add an asset to the vault list
    /// @param _asset Asset address
    function addAsset(address _asset) external checkAccess(this.addAsset.selector) {
        VaultLogic.addAsset(getVaultStorage(), _asset);
    }

    /// @notice Remove an asset from the vault list
    /// @param _asset Asset address
    function removeAsset(address _asset) external checkAccess(this.removeAsset.selector) {
        VaultLogic.removeAsset(getVaultStorage(), _asset);
    }

    /// @notice Pause an asset
    /// @param _asset Asset address
    function pause(address _asset) external checkAccess(this.pause.selector) {
        VaultLogic.pause(getVaultStorage(), _asset);
    }

    /// @notice Unpause an asset
    /// @param _asset Asset address
    function unpause(address _asset) external checkAccess(this.unpause.selector) {
        VaultLogic.unpause(getVaultStorage(), _asset);
    }

    /// @notice Rescue an unsupported asset
    /// @param _asset Asset to rescue
    /// @param _receiver Receiver of the rescue
    function rescueERC20(address _asset, address _receiver) external checkAccess(this.rescueERC20.selector) {
        VaultLogic.rescueERC20(getVaultStorage(), _asset, _receiver);
    }

    /// @notice Get the list of assets supported by the vault
    /// @return assetList List of assets
    function assets() public view returns (address[] memory assetList) {
        assetList = getVaultStorage().assets.values();
    }

    /// @notice Get the total supplies of an asset
    /// @param _asset Asset address
    /// @return totalSupply Total supply
    function totalSupplies(address _asset) external view returns (uint256 totalSupply) {
        totalSupply = getVaultStorage().totalSupplies[_asset];
    }

    /// @notice Get the total borrows of an asset
    /// @param _asset Asset address
    /// @return totalBorrow Total borrow
    function totalBorrows(address _asset) external view returns (uint256 totalBorrow) {
        totalBorrow = getVaultStorage().totalBorrows[_asset];
    }

    /// @notice Get the pause state of an asset
    /// @param _asset Asset address
    /// @return isPaused Pause state
    function paused(address _asset) external view returns (bool isPaused) {
        isPaused = getVaultStorage().paused[_asset];
    }

    /// @notice Available balance to borrow
    /// @param _asset Asset to borrow
    /// @return amount Amount available
    function availableBalance(address _asset) external view returns (uint256 amount) {
        amount = VaultLogic.availableBalance(getVaultStorage(), _asset);
    }

    /// @notice Utilization rate of an asset
    /// @dev Utilization scaled by 1e27
    /// @param _asset Utilized asset
    /// @return ratio Utilization ratio
    function utilization(address _asset) external view returns (uint256 ratio) {
        ratio = VaultLogic.utilization(getVaultStorage(), _asset);
    }

    /// @notice Up to date cumulative utilization index of an asset
    /// @dev Utilization scaled by 1e27
    /// @param _asset Utilized asset
    /// @return index Utilization ratio index
    function currentUtilizationIndex(address _asset) external view returns (uint256 index) {
        index = VaultLogic.currentUtilizationIndex(getVaultStorage(), _asset);
    }

    /// @notice Get the insurance fund
    /// @return insuranceFund Insurance fund
    function insuranceFund() external view returns (address) {
        return getVaultStorage().insuranceFund;
    }
}
