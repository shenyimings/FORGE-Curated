// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {BaseSBold} from "./base/BaseSBold.sol";
import {SpLogic} from "./libraries/logic/SpLogic.sol";
import {SwapLogic} from "./libraries/logic/SwapLogic.sol";
import {QuoteLogic} from "./libraries/logic/QuoteLogic.sol";
import {Constants} from "./libraries/helpers/Constants.sol";
import {Decimals} from "./libraries/helpers/Decimals.sol";
import {TransientStorage} from "./libraries/helpers/TransientStorage.sol";

/// @title sBold Protocol
/// @notice The $BOLD ERC4626 yield-bearing token.
contract sBold is BaseSBold {
    using Math for uint256;

    /// @notice Deploys sBold.
    /// @param _asset The address of the $BOLD instance.
    /// @param _name The name of `this` contract.
    /// @param _symbol The symbol of `this` contract.
    /// @param _sps The Stability Pools memory array.
    /// @param _priceOracle The address of the price oracle adapter.
    /// @param _vault The address of the vault for fee transfers.
    constructor(
        address _asset,
        string memory _name,
        string memory _symbol,
        SPConfig[] memory _sps,
        address _priceOracle,
        address _vault
    ) ERC4626(ERC20(_asset)) ERC20(_name, _symbol) BaseSBold(_sps, _priceOracle, _vault) {
        super.deposit(10 ** decimals(), address(this));
    }

    /*//////////////////////////////////////////////////////////////
                                 LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposits $BOLD in SP and mints corresponding $sBOLD.
    /// @param assets The amount of assets to deposit + fee to collect.
    /// @param receiver The address to mint the shares to.
    /// @return The amount of shares.
    function deposit(
        uint256 assets,
        address receiver
    ) public override whenNotPaused nonReentrant execCollateralOps returns (uint256) {
        uint256 maxAssets = _maxDeposit(receiver);
        if (assets > maxAssets) {
            revert ERC4626ExceededMaxDeposit(receiver, assets, maxAssets);
        }

        uint256 fee = _feeOnTotal(assets, feeBps);

        uint256 shares = super.previewDeposit(assets - fee);

        _deposit(_msgSender(), receiver, assets, shares);

        if (fee > 0) SafeERC20.safeTransfer(IERC20(asset()), vault, fee);

        SpLogic.provideToSP(sps, assets - fee);

        return shares;
    }

    /// @notice Mints shares of $sBOLD and provides corresponding $BOLD to SP.
    /// @param shares The amount of shares to mint.
    /// @param receiver The address to send the shares to.
    /// @return The amount of assets.
    function mint(
        uint256 shares,
        address receiver
    ) public override whenNotPaused nonReentrant execCollateralOps returns (uint256) {
        uint256 maxShares = _maxMint(receiver);
        if (shares > maxShares) {
            revert ERC4626ExceededMaxMint(receiver, shares, maxShares);
        }

        uint256 assets = super.previewMint(shares);

        uint256 fee = _feeOnRaw(assets, feeBps);

        _deposit(_msgSender(), receiver, assets + fee, shares);

        if (fee > 0) SafeERC20.safeTransfer(IERC20(asset()), vault, fee);

        SpLogic.provideToSP(sps, assets);

        return assets + fee;
    }

    /// @notice Redeems shares of $sBOLD in $BOLD and burns $sBOLD.
    /// @param shares The amount of shares to redeem.
    /// @param receiver The address to send the assets to.
    /// @param owner The owner of the shares.
    /// @return The amount of assets.
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public override whenNotPaused nonReentrant execCollateralOps returns (uint256) {
        uint256 maxShares = _maxRedeem(owner);
        if (shares > maxShares) {
            revert ERC4626ExceededMaxRedeem(owner, shares, maxShares);
        }

        uint256 assets = super.previewRedeem(shares);

        SpLogic.withdrawFromSP(sps, IERC20(asset()), decimals(), assets, true);

        _withdraw(_msgSender(), receiver, owner, assets, shares);

        return assets;
    }

    /// @notice Withdraws assets $BOLD from the SP and burns $sBOLD.
    /// @param assets The amount of assets to withdraw.
    /// @param receiver The address to send the shares to.
    /// @param owner The owner of the shares.
    /// @return The amount of shares.
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public override whenNotPaused nonReentrant execCollateralOps returns (uint256) {
        uint256 maxAssets = _maxWithdraw(owner);
        if (assets > maxAssets) {
            revert ERC4626ExceededMaxWithdraw(owner, assets, maxAssets);
        }

        uint256 shares = super.previewWithdraw(assets);

        SpLogic.withdrawFromSP(sps, IERC20(asset()), decimals(), assets, true);

        _withdraw(_msgSender(), receiver, owner, assets, shares);

        return shares;
    }

    /// @notice Swaps collateral balances to $BOLD.
    /// @param swapData The swap data.
    /// @param receiver The reward receiver.
    function swap(SwapData[] memory swapData, address receiver) public whenNotPaused nonReentrant {
        address bold = asset();

        // Prepare swap data and claim collateral.
        SwapDataWithColl[] memory swapDataWithColl = SwapLogic.prepareSwap(bold, priceOracle, sps, swapData);
        // Execute swaps for each collateral to $BOLD
        uint256 assets = SwapLogic.swap(bold, swapAdapter, swapDataWithColl, maxSlippage);

        (, uint256 swapFee, uint256 reward) = SwapLogic.applyFees(assets, swapFeeBps, rewardBps);

        IERC20 iBold = IERC20(bold);

        if (swapFee > 0) SafeERC20.safeTransfer(iBold, vault, swapFee);
        if (reward > 0) SafeERC20.safeTransfer(iBold, receiver, reward);

        uint256 assetsInternal = ERC20(bold).balanceOf(address(this));
        uint256 deadShareAmount = 10 ** decimals();

        if (assetsInternal > deadShareAmount) {
            SpLogic.provideToSP(sps, assetsInternal - deadShareAmount);
        }
    }

    /// @notice This function is able to both re-balance in terms of weights and change entirely current SPs.
    /// @param _sps The Stability Pools memory array.
    /// @param _swapData The swap data.
    function rebalanceSPs(SPConfig[] calldata _sps, SwapData[] memory _swapData) external onlyOwner nonReentrant {
        address bold = asset();

        // Prepare swap data and claim collateral.
        SwapDataWithColl[] memory swapDataWithColl = SwapLogic.prepareSwap(bold, priceOracle, sps, _swapData);
        // Execute swaps for each collateral to $BOLD.
        SwapLogic.swap(bold, swapAdapter, swapDataWithColl, maxSlippage);

        _checkCollHealth(true);

        uint256 boldAmount;
        for (uint256 i = 0; i < sps.length; i++) {
            // Add $BOLD compounded deposits from each SP
            boldAmount += SpLogic._getBoldAssetsSP(sps[i].sp);
        }

        // Withdraw all assets from current SPs.
        SpLogic.withdrawFromSP(sps, IERC20(bold), decimals(), boldAmount, false);

        // Sanitize
        delete sps;
        // Set new SPs.
        _setSPs(_sps);

        uint256 assetsInternal = ERC20(bold).balanceOf(address(this));
        uint256 deadShareAmount = 10 ** decimals();

        if (assetsInternal > deadShareAmount) {
            // Provide all assets to new SPs.
            SpLogic.provideToSP(sps, assetsInternal - deadShareAmount);
        }

        emit Rebalance(_sps);
    }

    /*//////////////////////////////////////////////////////////////
                                MAXIMUMS
    //////////////////////////////////////////////////////////////*/

    /// @dev Max deposit function returning result from `_maxDeposit`. See {IERC4626-maxDeposit} and {sBold-_maxDeposit}.
    function maxDeposit(address account) public view virtual override nonReentrantReadOnly returns (uint256) {
        return _maxDeposit(account);
    }

    /// @dev Max deposit function returning result from `_maxMint`. See {IERC4626-maxMint} and {sBold-_maxMint}.
    function maxMint(address account) public view virtual override nonReentrantReadOnly returns (uint256) {
        return _maxMint(account);
    }

    /// @dev Max withdraw function returning result from `_maxWithdraw`. See {IERC4626-maxWithdraw} and {sBold-maxWithdraw}.
    function maxWithdraw(address owner) public view virtual override nonReentrantReadOnly returns (uint256) {
        return _maxWithdraw(owner);
    }

    /// @dev Max redeem function returning result from `_maxRedeem`. See {IERC4626-maxRedeem} and {sBold-_maxRedeem}.
    function maxRedeem(address owner) public view virtual override nonReentrantReadOnly returns (uint256) {
        return _maxRedeem(owner);
    }

    /*//////////////////////////////////////////////////////////////
                               PREVIEWS
    //////////////////////////////////////////////////////////////*/

    /// @dev Preview deducting an entry fee on deposit. See {IERC4626-previewDeposit}.
    function previewDeposit(uint256 assets) public view virtual override nonReentrantReadOnly returns (uint256) {
        uint256 fee = _feeOnTotal(assets, feeBps);

        return super.previewDeposit(assets - fee);
    }

    /// @dev Preview adding an entry fee on mint. See {IERC4626-previewMint}.
    function previewMint(uint256 shares) public view virtual override nonReentrantReadOnly returns (uint256) {
        uint256 assets = super.previewMint(shares);

        return assets + _feeOnRaw(assets, feeBps);
    }

    /// @dev Preview withdraw add readOnly reentrancy check. See {IERC4626-previewWithdraw}.
    function previewWithdraw(uint256 assets) public view virtual override nonReentrantReadOnly returns (uint256) {
        return super.previewWithdraw(assets);
    }

    /// @dev Preview redeem add readOnly reentrancy check. See {IERC4626-previewRedeem}.
    function previewRedeem(uint256 shares) public view virtual override nonReentrantReadOnly returns (uint256) {
        return super.previewRedeem(shares);
    }

    /** @dev See {IERC4626-convertToShares}. */
    function convertToShares(uint256 assets) public view virtual override nonReentrantReadOnly returns (uint256) {
        return _convertToShares(assets, Math.Rounding.Floor);
    }

    /** @dev See {IERC4626-convertToAssets}. */
    function convertToAssets(uint256 shares) public view virtual override nonReentrantReadOnly returns (uint256) {
        return _convertToAssets(shares, Math.Rounding.Floor);
    }

    /// @dev Total underlying assets owned by the sBOLD contract which are utilized in stability pools.
    function totalAssets() public view virtual override nonReentrantReadOnly returns (uint256) {
        (uint256 totalBold, , , ) = _calcFragments();

        return totalBold;
    }

    /*//////////////////////////////////////////////////////////////
                                TRANSIENT
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc BaseSBold
    function _checkAndStoreCollValueInBold() internal virtual override {
        (, uint256 collValue, uint256 collInBold) = _checkCollHealth(true);
        // Transient store for collaterals and flag
        TransientStorage.storeCollValues(collValue, collInBold);
    }

    /*//////////////////////////////////////////////////////////////
                               GETTERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Calculates the $sBOLD:BOLD rate.
    /// @return The $sBOLD:$BOLD rate.
    function getSBoldRate() public view nonReentrantReadOnly returns (uint256) {
        (uint256 totalBold, , , ) = _calcFragments();

        return (totalBold + 1).mulDiv(10 ** decimals(), totalSupply() + 10 ** _decimalsOffset());
    }

    function calcFragments() public view nonReentrantReadOnly returns (uint256, uint256, uint256, uint256) {
        return _calcFragments();
    }

    /// @dev Max deposit returns 0 if collateral is above max, the contract is paused or call to oracle has failed. See {IERC4626-maxDeposit}.
    function _maxDeposit(address account) private view returns (uint256) {
        (bool success, , ) = _checkCollHealth(false);

        if (!success || paused()) return 0;

        return super.maxDeposit(account);
    }

    /// @dev Max mint returns 0 if collateral is above max, the contract is paused or call to oracle has failed. See {IERC4626-maxMint}.
    function _maxMint(address account) private view returns (uint256) {
        (bool success, , ) = _checkCollHealth(false);

        if (!success || paused()) return 0;

        return super.maxMint(account);
    }

    /// @dev Max withdraw returns 0 if collateral is above max. See {IERC4626-maxWithdraw}.
    /// note: Returns an amount up to the one available in $BOLD.
    function _maxWithdraw(address owner) private view returns (uint256) {
        (bool success, , ) = _checkCollHealth(false);

        if (!success || paused()) return 0;

        uint256 maxWithdrawAssets = super.maxWithdraw(owner);

        uint256 boldAmount = SpLogic.getBoldAssets(sps, IERC20(asset()));

        if (maxWithdrawAssets > boldAmount) {
            uint256 deadShareAmount = 10 ** decimals();

            if (boldAmount < deadShareAmount) return 0;

            return boldAmount - deadShareAmount;
        }

        return maxWithdrawAssets;
    }

    /// @dev Max redeem returns 0 if collateral is above max. See {IERC4626-maxRedeem}.
    /// note: Returns an amount up to the one available in $BOLD, converted in shares.
    function _maxRedeem(address owner) private view returns (uint256) {
        (bool success, , ) = _checkCollHealth(false);

        if (!success || paused()) return 0;

        uint256 maxWithdrawAssets = super.maxWithdraw(owner);

        uint256 boldAmount = SpLogic.getBoldAssets(sps, IERC20(asset()));

        if (maxWithdrawAssets > boldAmount) {
            uint256 deadShareAmount = 10 ** decimals();

            if (boldAmount < deadShareAmount) return 0;

            return _convertToShares(boldAmount - deadShareAmount, Math.Rounding.Floor);
        }

        return super.maxRedeem(owner);
    }

    /// @notice Calculates the total value in $BOLD of the assets in the contract.
    /// @return The total value in USD, $BOLD amount and collateral in USD.
    function _calcFragments() private view returns (uint256, uint256, uint256, uint256) {
        address bold = asset();
        // Get compounded $BOLD amount
        uint256 boldAmount = SpLogic.getBoldAssets(sps, IERC20(bold));
        // Get collateral value in USD and $BOLD
        (, uint256 collValue, uint256 collInBold) = _calcCollValue(bold, true);
        // Calculate based on the minimum amount to be received after swap
        uint256 collToBoldMinOut = SwapLogic.calcMinOut(collInBold, maxSlippage);
        // Apply fees after swap
        (uint256 collInBoldNet, , ) = SwapLogic.applyFees(collToBoldMinOut, swapFeeBps, rewardBps);
        // Calculate total $BOLD value
        uint256 totalBold = boldAmount + collInBoldNet;

        return (totalBold, boldAmount, collValue, collInBold);
    }

    /// @notice Converts the $BOLD assets to shares based on $sBOLD exchange rate.
    /// @return The calculated $sBOLD share, based on the total value held.
    function _convertToShares(uint256 assets, Math.Rounding rounding) internal view override returns (uint256) {
        return
            assets.mulDiv(
                10 ** decimals(),
                _getSBoldRateWithRounding(rounding == Math.Rounding.Floor ? Math.Rounding.Ceil : Math.Rounding.Floor),
                rounding
            );
    }

    /// @notice Converts the $sBOLD shares to $BOLD assets based on $sBOLD exchange rate.
    /// @return The calculated $BOLD assets, based on the total value held.
    function _convertToAssets(uint256 shares, Math.Rounding rounding) internal view override returns (uint256) {
        return shares.mulDiv(_getSBoldRateWithRounding(rounding), 10 ** decimals(), rounding);
    }

    /// @notice Calculates the $sBOLD:BOLD rate with input rounding.
    /// @param rounding Type of rounding on math calculations.
    /// @return The $sBOLD:$BOLD rate.
    function _getSBoldRateWithRounding(Math.Rounding rounding) private view returns (uint256) {
        (uint256 totalBold, , , ) = _calcFragments();

        return (totalBold + 1).mulDiv(10 ** decimals(), totalSupply() + 10 ** _decimalsOffset(), rounding);
    }

    /// @dev Calculates the fees that should be added to an amount `assets` that does not already include fees.
    /// Used in {IERC4626-mint} operations.
    function _feeOnRaw(uint256 assets, uint256 feeBasisPoints) internal pure returns (uint256) {
        return assets.mulDiv(feeBasisPoints, Constants.BPS_DENOMINATOR, Math.Rounding.Ceil);
    }

    /// @dev Calculates the fee part of an amount `assets` that already includes fees.
    /// Used in {IERC4626-deposit} operations.
    function _feeOnTotal(uint256 assets, uint256 feeBasisPoints) internal pure returns (uint256) {
        return assets.mulDiv(feeBasisPoints, feeBasisPoints + Constants.BPS_DENOMINATOR, Math.Rounding.Ceil);
    }

    /// @notice Calculates the collateral value in USD and $BOLD from all SPs.
    /// @param _bold Asset contract address.
    /// @param _revert Indication to revert on errors.
    /// @return success Success result from function.
    /// @return collValue The total collateral value.
    /// @return collInBold The collateral value denominated in $BOLD.
    function _calcCollValue(
        address _bold,
        bool _revert
    ) private view returns (bool success, uint256 collValue, uint256 collInBold) {
        // Return values from transient storage
        if (TransientStorage.loadCollsFlag())
            return (true, TransientStorage.loadCollValue(), TransientStorage.loadCollInBold());

        CollBalance[] memory collBalances = SpLogic.getCollBalances(sps, false);

        (success, collValue) = QuoteLogic.getAggregatedQuote(priceOracle, collBalances, _revert);

        if (success)
            try priceOracle.getQuote(10 ** decimals(), _bold) returns (uint256 boldUnitQuote) {
                collInBold = collValue.mulDiv(10 ** Constants.ORACLE_PRICE_PRECISION, boldUnitQuote);
            } catch (bytes memory data) {
                if (_revert) revert(string(data));

                return (false, collValue, 0);
            }
    }

    /*//////////////////////////////////////////////////////////////
                               VALIDATIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Checks if the collateral value in $BOLD is over the maximum allowed.
    function _checkCollHealth(bool _revert) private view returns (bool, uint256, uint256) {
        (bool success, uint256 collValue, uint256 collValueInBold) = _calcCollValue(asset(), _revert);

        if (!success) return (false, 0, 0);

        if (collValueInBold <= maxCollInBold) return (true, collValue, collValueInBold);

        if (_revert) revert CollOverLimit();

        return (false, collValue, collValueInBold);
    }
}
