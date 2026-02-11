// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {IStabilityPool} from "../external/IStabilityPool.sol";
import {IPriceOracle} from "../interfaces/IPriceOracle.sol";
import {ISBold} from "../interfaces/ISBold.sol";
import {ICommon} from "../interfaces/ICommon.sol";
import {Constants} from "../libraries/helpers/Constants.sol";
import {Common} from "../libraries/Common.sol";
import {TransientStorage} from "../libraries/helpers/TransientStorage.sol";

/// @title sBold Protocol
/// @notice The $sBOLD represents an ERC4626 yield-bearing token.
abstract contract BaseSBold is ISBold, ICommon, ERC4626, ReentrancyGuardTransient, Pausable, Ownable {
    /// @notice Data for stability pools.
    SP[] public sps;
    /// @notice The fee in basis points.
    uint256 public feeBps;
    /// @notice The fee applied over the swap in basis points.
    uint256 public swapFeeBps;
    /// @notice The reward for the `caller` applied over the swap in basis points.
    uint256 public rewardBps;
    /// @notice The maximum slippage tolerance on swap in basis points.
    uint256 public maxSlippage;
    /// @notice The maximum Coll value aggregated and owned.
    uint256 public maxCollInBold;
    /// @notice Price oracle instance.
    IPriceOracle public priceOracle;
    /// @notice Swap adapter instance.
    address public swapAdapter;
    /// @notice An address to which a fee amount in $BOLD is transferred.
    address public vault;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Deploys sBold.
    /// @param _sps The Stability Pools memory array.
    /// @param _priceOracle The address of the price oracle adapter.
    /// @param _vault The address of the vault for fee transfers.
    constructor(SPConfig[] memory _sps, address _priceOracle, address _vault) Ownable(_msgSender()) {
        _setSPs(_sps);
        priceOracle = IPriceOracle(_priceOracle);
        vault = _vault;
    }

    /// @dev Stores and loads collateral in $BOLD value in transient storage.
    /// Operates with three values, the collateral in USD, in $BOLD and a flag.
    modifier execCollateralOps() {
        _checkAndStoreCollValueInBold();
        _;
        TransientStorage.switchOffCollInBoldFlag();
    }

    /// @dev Check for reentrancy on read functions.
    modifier nonReentrantReadOnly() {
        if (_reentrancyGuardEntered()) {
            revert ReentrancyGuardReentrantCall();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                               SETTERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Sets `priceOracle` address which will be used for price derivation.
    /// @param _priceOracle The address of the price oracle.
    function setPriceOracle(address _priceOracle) external onlyOwner {
        Common.revertZeroAddress(_priceOracle);

        priceOracle = IPriceOracle(_priceOracle);

        emit PriceOracleSet(_priceOracle);
    }

    /// @notice Sets `vault` address to which fees will be transferred.
    /// @param _vault The address of the vault.
    function setVault(address _vault) external onlyOwner {
        Common.revertZeroAddress(_vault);
        if (_vault == asset() || _vault == address(this)) revert InvalidAddress();

        vault = _vault;

        emit VaultSet(_vault);
    }

    /// @notice Sets the fee in BPS.
    /// @param _feeBps The fee in BPS.
    /// @param _swapFeeBps The swap fee in BPS.
    function setFees(uint256 _feeBps, uint256 _swapFeeBps) external onlyOwner {
        if (_feeBps > Constants.BPS_MAX_FEE || _swapFeeBps > Constants.BPS_MAX_FEE) revert InvalidConfiguration();

        feeBps = _feeBps;
        swapFeeBps = _swapFeeBps;

        emit FeesSet(_feeBps, _swapFeeBps);
    }

    /// @notice Sets the reward in BPS.
    /// @param _rewardBps The reward in BPS.
    function setReward(uint256 _rewardBps) external onlyOwner {
        if (_rewardBps < Constants.BPS_MIN_REWARD || _rewardBps > Constants.BPS_MAX_REWARD)
            revert InvalidConfiguration();

        rewardBps = _rewardBps;

        emit RewardSet(_rewardBps);
    }

    /// @notice Sets the maximum slippage tolerance in BPS.
    /// @param _maxSlippage The maximum slippage tolerance in BPS.
    function setMaxSlippage(uint256 _maxSlippage) external onlyOwner {
        if (_maxSlippage > Constants.BPS_MAX_SLIPPAGE) revert InvalidConfiguration();

        maxSlippage = _maxSlippage;

        emit MaxSlippageSet(_maxSlippage);
    }

    /// @notice Sets the swap adapter address.
    /// @param _swapAdapter The swap adapter address.
    function setSwapAdapter(address _swapAdapter) external onlyOwner {
        Common.revertZeroAddress(_swapAdapter);
        if (_swapAdapter == asset()) revert InvalidAddress();
        for (uint256 i = 0; i < sps.length; i++) {
            if (_swapAdapter == sps[i].sp || _swapAdapter == sps[i].coll) revert InvalidAddress();
        }

        swapAdapter = _swapAdapter;

        emit SwapAdapterSet(_swapAdapter);
    }

    /// @notice Sets the maximum Coll value aggregated and owned.
    /// @param _maxCollInBold The maximum Coll value.
    function setMaxCollInBold(uint256 _maxCollInBold) external onlyOwner {
        if (_maxCollInBold == 0 || _maxCollInBold > Constants.MAX_COLL_IN_BOLD_UPPER_BOUND) {
            revert InvalidConfiguration();
        }

        maxCollInBold = _maxCollInBold;

        emit MaxCollValueSet(_maxCollInBold);
    }

    /*//////////////////////////////////////////////////////////////
                                PAUSE
    //////////////////////////////////////////////////////////////*/

    /// @notice Pauses contract.
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpauses contract.
    function unpause() external onlyOwner {
        _unpause();
    }

    /*//////////////////////////////////////////////////////////////
                                INTERNAL
    //////////////////////////////////////////////////////////////*/

    /// @notice Sets Stability Pools and Coll assets structures.
    /// The total weight of all Stability Pools should be equal to `BPS_DENOMINATOR`.
    /// Each Stability Pool Coll is derived from the pools themselves.
    /// The decimal precision for each Coll is dynamically extracted.
    /// @param _sps Address and weight of Stability Pools.
    function _setSPs(SPConfig[] memory _sps) internal {
        if (_sps.length == 0 || _sps.length > Constants.MAX_SP) revert InvalidSPLength();

        uint256 totalWeight;
        for (uint256 i = 0; i < _sps.length; i++) {
            address spAddress = _sps[i].addr;
            uint96 weight = _sps[i].weight;

            // Verify input
            Common.revertZeroAddress(spAddress);
            if (weight == 0) revert ZeroWeight();
            for (uint256 j = 0; j < _sps.length; j++) {
                if (i != j && spAddress == _sps[j].addr) {
                    revert DuplicateAddress();
                }
            }

            // Update Storage related to SP
            sps.push(SP({sp: spAddress, weight: weight, coll: address(IStabilityPool(spAddress).collToken())}));

            totalWeight += weight;
        }

        if (totalWeight != Constants.BPS_DENOMINATOR) revert InvalidTotalWeight();
    }

    /// @notice Check and store collateral value in $BOLD if transient storage load is not enabled.
    function _checkAndStoreCollValueInBold() internal virtual {}
}
