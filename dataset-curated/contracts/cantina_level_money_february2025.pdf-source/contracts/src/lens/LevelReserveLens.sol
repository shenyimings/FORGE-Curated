// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.21;

import {Initializable} from "@openzeppelin-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";

import {ILevelMinting} from "../interfaces/ILevelMinting.sol";
import {IVault} from "../interfaces/ISymbioticVault.sol";
import {AggregatorV3Interface} from "../interfaces/AggregatorV3Interface.sol";
import {ILevelReserveLens} from "../interfaces/lens/ILevelReserveLens.sol";

/**
 *                                     .-==+=======+:
 *                                      :---=-::-==:
 *                                      .-:-==-:-==:
 *                    .:::--::::::.     .--:-=--:--.       .:--:::--..
 *                   .=++=++:::::..     .:::---::--.    ....::...:::.
 *                    :::-::..::..      .::::-:::::.     ...::...:::.
 *                    ...::..::::..     .::::--::-:.    ....::...:::..
 *                    ............      ....:::..::.    ------:......
 *    ...........     ........:....     .....::..:..    ======-......      ...........
 *    :------:.:...   ...:+***++*#+     .------:---.    ...::::.:::...   .....:-----::.
 *    .::::::::-:..   .::--..:-::..    .-=+===++=-==:   ...:::..:--:..   .:==+=++++++*:
 *
 * @title LevelReserveLens
 * @author Level (https://level.money)
 * @notice The LevelReserveLens contract is a simple contract that allows users to query the reserves backing lvlUSD per underlying collateral token address.
 * @dev It is upgradeable so that we can add future reserve managers without affecting downstream consumers.
 */
contract LevelReserveLens is ILevelReserveLens, Initializable, OwnableUpgradeable, UUPSUpgradeable {
    // Addresses that store lvlUSD reserves
    address public constant levelMintingAddress = 0x8E7046e27D14d09bdacDE9260ff7c8c2be68a41f;
    address public constant eigenReserveManager = 0x7B2c2C905184CEf1FABe920D4CbEA525acAa6f14;
    address public constant symbioticReserveManager = 0x21C937d436f2D86859ce60311290a8072368932D;
    address public constant karakReserveManager = 0x329F91FE82c1799C3e089FabE9D3A7efDC2D3151;
    address public constant waUsdcSymbioticVault = 0x67F91a36c5287709E68E3420cd17dd5B13c60D6d;
    address public constant waUsdtSymbioticVault = 0x9BF93077Ad7BB7f43E177b6AbBf8Dae914761599;
    address public constant usdcEigenStrategy = 0x82A2e702C4CeCA35D8c474e218eD6f0852827380;
    address public constant usdtEigenStrategy = 0x38fb62B973e4515a2A2A8B819a3B2217101Ad691;

    address public constant usdcAddress = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant usdtAddress = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address public constant waUsdcAddress = 0x78c6B27Be6DB520d332b1b44323F94bC831F5e33;
    address public constant waUsdtAddress = 0xb723377679b807370Ae8615ae3E76F6D1E75a5F2;
    address public constant lvlusdAddress = 0x7C1156E515aA1A2E851674120074968C905aAF37;

    address public constant usdcOracle = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
    address public constant usdtOracle = 0x3E7d1eAB13ad0104d2750B8863b489D65364e32D;

    uint8 public constant LVLUSD_DECIMALS = 18;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     * @param admin The address of the admin of the contract.
     */
    function initialize(address admin) public initializer {
        __Ownable_init(admin);
        __UUPSUpgradeable_init();
    }

    /// @inheritdoc ILevelReserveLens
    function getReserves(address collateral) public view virtual override returns (uint256) {
        IERC20Metadata usdc = IERC20Metadata(usdcAddress);
        IERC20Metadata usdt = IERC20Metadata(usdtAddress);

        uint256 reserves;
        if (collateral == address(usdc)) {
            reserves = _getReserves(usdc, waUsdcAddress, usdcEigenStrategy, waUsdcSymbioticVault);

            return safeAdjustForDecimals(reserves, usdc.decimals(), LVLUSD_DECIMALS);
        } else if (collateral == address(usdt)) {
            reserves = _getReserves(usdt, waUsdtAddress, usdtEigenStrategy, waUsdtSymbioticVault);

            return safeAdjustForDecimals(reserves, usdt.decimals(), LVLUSD_DECIMALS);
        } else {
            revert("Invalid collateral token");
        }
    }

    /// @inheritdoc ILevelReserveLens
    function getReserveValue(address collateral) public view override returns (uint256 usdReserves) {
        uint256 reserves = getReserves(collateral);

        AggregatorV3Interface oracle;
        if (collateral == usdcAddress) {
            oracle = AggregatorV3Interface(usdcOracle);
        } else if (collateral == usdtAddress) {
            oracle = AggregatorV3Interface(usdtOracle);
        } else {
            revert("Invalid collateral token");
        }
        (, int256 answer,,,) = oracle.latestRoundData();

        if (answer == 0) {
            revert("Oracle price is 0");
        }

        uint8 oracleDecimals = oracle.decimals();

        return (reserves * uint256(answer)) / (10 ** oracleDecimals);
    }

    /// @inheritdoc ILevelReserveLens
    function getReserveValue() public view override returns (uint256 usdReserves) {
        address[] memory collateral = new address[](2);
        collateral[0] = usdcAddress;
        collateral[1] = usdtAddress;

        uint256 totalReservesUsd;

        for (uint256 i = 0; i < collateral.length; i++) {
            totalReservesUsd += getReserveValue(collateral[i]);
        }

        return totalReservesUsd;
    }

    /// @inheritdoc ILevelReserveLens
    function getReservePrice() public view override returns (uint256) {
        uint256 usdReserves = getReserveValue();
        uint256 totalSupply = IERC20Metadata(lvlusdAddress).totalSupply();

        uint256 answer;

        if (usdReserves >= totalSupply) {
            answer = 1e18;
        } else {
            answer = usdReserves * 1e18 / totalSupply;
        }

        return answer;
    }

    /// @inheritdoc ILevelReserveLens
    function getReservePriceDecimals() external pure override returns (uint8) {
        return LVLUSD_DECIMALS;
    }

    /// @inheritdoc ILevelReserveLens
    function getMintPrice(IERC20Metadata collateral) external view override returns (uint256) {
        ILevelMinting levelMinting = ILevelMinting(levelMintingAddress);

        (int256 price, uint256 oracleDecimals) = levelMinting.getPriceAndDecimals(address(collateral));
        if (price == 0) {
            revert("Oracle price is 0");
        }

        uint8 collateralAssetDecimals = collateral.decimals();
        uint256 oneUnit = 10 ** (collateralAssetDecimals);

        uint256 mintPrice;
        if (uint256(price) < 10 ** oracleDecimals) {
            mintPrice = (oneUnit * uint256(price) * 10 ** 18) / 10 ** (oracleDecimals) / 10 ** (collateralAssetDecimals);
        } else {
            mintPrice = (oneUnit * (10 ** 18)) / (10 ** (collateralAssetDecimals));
        }

        return mintPrice;
    }

    /// @inheritdoc ILevelReserveLens
    function getRedeemPrice(IERC20Metadata collateral) external view override returns (uint256) {
        ILevelMinting levelMinting = ILevelMinting(levelMintingAddress);

        (int256 price, uint256 oracleDecimals) = levelMinting.getPriceAndDecimals(address(collateral));
        if (price == 0) {
            revert("Oracle price is 0");
        }

        uint8 collateralAssetDecimals = collateral.decimals();
        uint256 oneLvlUsd = 1e18;

        uint256 redeemPrice;
        if (uint256(price) > 10 ** oracleDecimals) {
            redeemPrice =
                (oneLvlUsd * (10 ** oracleDecimals) * (10 ** (collateralAssetDecimals))) / uint256(price) / (10 ** 18);
        } else {
            redeemPrice = (oneLvlUsd * (10 ** (collateralAssetDecimals))) / (10 ** 18);
        }

        return redeemPrice;
    }

    /**
     * @notice Returns the underlying tokens staked in a given Eigen strategy
     * @dev Note: this function returns everything held in the strategy, which may include deposits from non-Level participants
     * @param collateral The address of the collateral token
     * @param strategy The address of the strategy
     * @return eigenStake The total collateral tokens held by the given Level strategy
     */
    function getEigenStake(IERC20Metadata collateral, address strategy) public view returns (uint256) {
        IERC20Metadata collateralToken = IERC20Metadata(collateral);
        return collateralToken.balanceOf(strategy);
    }

    /**
     * @notice Returns the underlying tokens staked in a given Symbiotic vault and burner
     * @dev Note: this function returns everything held in the strategy, which may include deposits from non-Level participants
     * @param collateral The address of the collateral token
     * @param vault The address of the Symbiotic vault
     * @return symbioticStake The total collateral tokens held by the given vault and vault burner
     */
    function getSymbioticStake(IERC20Metadata collateral, address vault) public view returns (uint256) {
        IERC20Metadata collateralToken = IERC20Metadata(collateral);
        IVault symbioticVault = IVault(vault);

        uint256 balance = collateralToken.balanceOf(vault);

        if (symbioticVault.burner() != address(0)) {
            balance += collateralToken.balanceOf(symbioticVault.burner());
        }
        return balance;
    }

    /**
     * @notice Adjusts the amount for the difference in decimals. Reverts if the amount would lose precision.
     * @param amount The amount to adjust
     * @param fromDecimals The decimals of the amount
     * @param toDecimals The decimals to adjust to
     * @return adjustedAmount The adjusted amount
     */
    function safeAdjustForDecimals(uint256 amount, uint8 fromDecimals, uint8 toDecimals)
        public
        pure
        returns (uint256)
    {
        if (fromDecimals == toDecimals) {
            return amount;
        }

        if (fromDecimals > toDecimals) {
            revert("Cannot lose precision");
        } else {
            return amount * (10 ** (toDecimals - fromDecimals));
        }
    }

    /**
     * @notice Helper function to get the reserves of the given collateral token.
     * @param collateral The address of the collateral token.
     * @param waCollateralAddress The address of the wrapped Aave token for the collateral.
     * @param eigenStrategy The address of the Eigen strategy for the collateral.
     * @param symbioticVault The address of the Symbiotic vault for the collateral.
     * @return reserves The lvlUSD reserves for a given collateral token, in the given token's decimals.
     */
    function _getReserves(
        IERC20Metadata collateral,
        address waCollateralAddress,
        address eigenStrategy,
        address symbioticVault
    ) internal view returns (uint256) {
        IERC20Metadata waCollateral = IERC20Metadata(waCollateralAddress);

        uint256 waCollateralInEigenStrategy = getEigenStake(waCollateral, eigenStrategy);
        uint256 waCollateralInSymbiotic = getSymbioticStake(waCollateral, symbioticVault);

        uint256 waCollateralBalance = waCollateral.balanceOf(eigenReserveManager)
            + waCollateral.balanceOf(symbioticReserveManager) + waCollateral.balanceOf(karakReserveManager);
        uint256 collateralBalance = collateral.balanceOf(eigenReserveManager)
            + collateral.balanceOf(symbioticReserveManager) + collateral.balanceOf(karakReserveManager)
            + collateral.balanceOf(levelMintingAddress);

        return waCollateralBalance + collateralBalance + waCollateralInEigenStrategy + waCollateralInSymbiotic;
    }

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address) internal override onlyOwner {}
}
