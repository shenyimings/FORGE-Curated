// SPDX-License-Identifier: BUSL-1.1
// Terms: https://liminal.money/xtokens/license

pragma solidity 0.8.28;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract NAVOracle is AccessControlUpgradeable {
    using Math for uint256;

    bytes32 public constant VALUATION_MANAGER_ROLE = keccak256("VALUATION_MANAGER_ROLE");

    bytes32 public constant VAULT_ROLE = keccak256("VAULT_ROLE");

    struct NAVOracleStorage {
        uint256 currentTotalAssets;
        uint256 lastUpdateTime;
        uint256 maxPercentageIncrease;
        uint256 maxPercentageDecrease;
        IERC20Metadata underlyingAsset;
        address timeLockController;
        uint256 lastSetTotalAssetsBlock;
    }

    bytes32 private constant NAV_ORACLE_STORAGE_LOCATION =
        0x530b86cfd76ace1cbd39c58faa3d0b7c3932db3408b4deb9aecf4ab72aef1d00;

    function _getNAVOracleStorage() private pure returns (NAVOracleStorage storage $) {
        assembly {
            $.slot := NAV_ORACLE_STORAGE_LOCATION
        }
    }

    event NAVUpdated(uint256 newNAV, uint256 timestamp);
    event NAVUpdatedVault(uint256 newNAV, uint256 timestamp);
    event NAVIncreased(uint256 amount, uint256 newNAV, uint256 timestamp);
    event NAVDecreased(uint256 amount, uint256 newNAV, uint256 timestamp);
    event MaxPercentageIncreaseUpdated(uint256 oldValue, uint256 newValue);
    event MaxPercentageDecreaseUpdated(uint256 oldValue, uint256 newValue);
    event TimelockControllerSet(address indexed oldTimelock, address indexed newTimelock);
    event UnderlyingAssetUpdated(address indexed oldAsset, address indexed newAsset);

    error NAVIncreaseExceedsLimit(uint256 currentNAV, uint256 newNAV, uint256 maxAllowed);
    error NAVDecreaseExceedsLimit(uint256 currentNAV, uint256 newNAV, uint256 maxAllowed);
    error InvalidPercentage(uint256 percentage);
    error IntraBlockCooldownActive(uint256 lastBlock, uint256 currentBlock);

    modifier onlyTimelock() {
        NAVOracleStorage storage $ = _getNAVOracleStorage();
        require(msg.sender == $.timeLockController, "NAVOracle: only timelock");
        _;
    }

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _deployer,
        address _valuationManager,
        uint256 _initialNAV,
        uint256 _maxPercentageIncrease,
        uint256 _maxPercentageDecrease,
        address _underlyingAsset,
        address _timeLockController
    ) external initializer {
        require(_deployer != address(0), "NAVOracle: zero deployer");
        require(_valuationManager != address(0), "NAVOracle: zero address");
        require(_underlyingAsset != address(0), "NAVOracle: zero address");
        require(_timeLockController != address(0), "NAVOracle: zero timelock");
        if (_maxPercentageIncrease == 0 || _maxPercentageIncrease > 10_000) {
            revert InvalidPercentage(_maxPercentageIncrease);
        }
        if (_maxPercentageDecrease == 0 || _maxPercentageDecrease > 10_000) {
            revert InvalidPercentage(_maxPercentageDecrease);
        }

        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, _deployer);
        _grantRole(VALUATION_MANAGER_ROLE, _valuationManager);

        NAVOracleStorage storage $ = _getNAVOracleStorage();
        $.currentTotalAssets = _initialNAV;
        $.maxPercentageIncrease = _maxPercentageIncrease;
        $.maxPercentageDecrease = _maxPercentageDecrease;
        $.underlyingAsset = IERC20Metadata(_underlyingAsset);
        $.timeLockController = _timeLockController;
        $.lastUpdateTime = block.timestamp;
        emit NAVUpdated(_initialNAV, block.timestamp);
    }

    function setMaxPercentageIncrease(uint16 _newMaxPercentage) external onlyTimelock {
        if (_newMaxPercentage == 0 || _newMaxPercentage > 10_000) {
            revert InvalidPercentage(_newMaxPercentage);
        }

        uint256 oldValue = _getNAVOracleStorage().maxPercentageIncrease;
        NAVOracleStorage storage $ = _getNAVOracleStorage();
        $.maxPercentageIncrease = _newMaxPercentage;
        emit MaxPercentageIncreaseUpdated(oldValue, _newMaxPercentage);
    }

    function setMaxPercentageDecrease(uint256 _newMaxPercentage) external onlyTimelock {
        if (_newMaxPercentage == 0 || _newMaxPercentage > 10_000) {
            revert InvalidPercentage(_newMaxPercentage);
        }

        uint256 oldValue = _getNAVOracleStorage().maxPercentageDecrease;
        NAVOracleStorage storage $ = _getNAVOracleStorage();
        $.maxPercentageDecrease = _newMaxPercentage;
        emit MaxPercentageDecreaseUpdated(oldValue, _newMaxPercentage);
    }

    function _normalizeToDecimals18(uint256 amount) private view returns (uint256) {
        NAVOracleStorage storage $ = _getNAVOracleStorage();
        uint8 underlyingDecimals = $.underlyingAsset.decimals();
        if (underlyingDecimals < 18) {
            return amount * (10 ** (18 - underlyingDecimals));
        }
        return amount;
    }

    function increaseTotalAssets(uint256 amount) external onlyRole(VAULT_ROLE) {
        require(amount > 0, "NAVOracle: zero amount");
        NAVOracleStorage storage $ = _getNAVOracleStorage();

        uint256 normalizedAmount = _normalizeToDecimals18(amount);

        $.currentTotalAssets += normalizedAmount;
        $.lastUpdateTime = block.timestamp;
        emit NAVIncreased(normalizedAmount, $.currentTotalAssets, block.timestamp);
    }

    function decreaseTotalAssets(uint256 amount) external onlyRole(VAULT_ROLE) {
        require(amount > 0, "NAVOracle: zero amount");
        NAVOracleStorage storage $ = _getNAVOracleStorage();

        uint256 normalizedAmount = _normalizeToDecimals18(amount);

        require($.currentTotalAssets >= normalizedAmount, "NAVOracle: insufficient NAV");
        $.currentTotalAssets -= normalizedAmount;
        $.lastUpdateTime = block.timestamp;
        emit NAVDecreased(normalizedAmount, $.currentTotalAssets, block.timestamp);
    }

    function setTotalAssets(uint256 newTotalAssets, uint256 expectedNav) external onlyRole(VALUATION_MANAGER_ROLE) {
        NAVOracleStorage storage $ = _getNAVOracleStorage();

        if ($.lastSetTotalAssetsBlock == block.number) {
            revert IntraBlockCooldownActive($.lastSetTotalAssetsBlock, block.number);
        }

        uint256 currentNAV = $.currentTotalAssets;
        require(currentNAV == expectedNav, "NAVOracle: expected NAV mismatch");

        if (newTotalAssets > currentNAV && currentNAV > 0) {
            uint256 maxAllowed = currentNAV + currentNAV.mulDiv($.maxPercentageIncrease, 10_000);

            if (newTotalAssets > maxAllowed) {
                revert NAVIncreaseExceedsLimit(currentNAV, newTotalAssets, maxAllowed);
            }
        }

        if (newTotalAssets < currentNAV && currentNAV > 0) {
            uint256 maxAllowed = currentNAV - currentNAV.mulDiv($.maxPercentageDecrease, 10_000);

            if (newTotalAssets < maxAllowed) {
                revert NAVDecreaseExceedsLimit(currentNAV, newTotalAssets, maxAllowed);
            }
        }

        $.currentTotalAssets = newTotalAssets;
        $.lastUpdateTime = block.timestamp;
        $.lastSetTotalAssetsBlock = block.number;
        emit NAVUpdated(newTotalAssets, block.timestamp);
    }

    function setUnderlyingAsset(address _newUnderlyingAsset) external onlyTimelock {
        require(_newUnderlyingAsset != address(0), "NAVOracle: zero address");

        NAVOracleStorage storage $ = _getNAVOracleStorage();
        address oldAsset = address($.underlyingAsset);
        require(oldAsset != _newUnderlyingAsset, "NAVOracle: same asset");

        $.underlyingAsset = IERC20Metadata(_newUnderlyingAsset);

        emit UnderlyingAssetUpdated(oldAsset, _newUnderlyingAsset);
    }

    function setTimelockController(address _timeLockController) external onlyTimelock {
        require(_timeLockController != address(0), "NAVOracle: zero timelock");

        NAVOracleStorage storage $ = _getNAVOracleStorage();
        address oldTimelock = $.timeLockController;
        $.timeLockController = _timeLockController;

        emit TimelockControllerSet(oldTimelock, _timeLockController);
    }

    function getNAV() external view returns (uint256) {
        return _getNAVOracleStorage().currentTotalAssets;
    }

    function getMaxAllowedNAV() external view returns (uint256) {
        NAVOracleStorage storage $ = _getNAVOracleStorage();
        return $.currentTotalAssets + $.currentTotalAssets.mulDiv($.maxPercentageIncrease, 10_000);
    }

    function getMinAllowedNAV() external view returns (uint256) {
        NAVOracleStorage storage $ = _getNAVOracleStorage();
        return $.currentTotalAssets - $.currentTotalAssets.mulDiv($.maxPercentageDecrease, 10_000);
    }

    function maxPercentageIncrease() external view returns (uint256) {
        return _getNAVOracleStorage().maxPercentageIncrease;
    }

    function maxPercentageDecrease() external view returns (uint256) {
        return _getNAVOracleStorage().maxPercentageDecrease;
    }

    function lastUpdateTime() external view returns (uint256) {
        return _getNAVOracleStorage().lastUpdateTime;
    }

    function getUnderlyingAsset() external view returns (address) {
        return address(_getNAVOracleStorage().underlyingAsset);
    }

    function timeLockController() external view returns (address) {
        return _getNAVOracleStorage().timeLockController;
    }

    function lastSetTotalAssetsBlock() external view returns (uint256) {
        return _getNAVOracleStorage().lastSetTotalAssetsBlock;
    }
}
