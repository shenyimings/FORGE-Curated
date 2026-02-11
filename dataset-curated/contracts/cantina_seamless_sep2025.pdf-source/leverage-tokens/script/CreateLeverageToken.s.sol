// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";

import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Id, MarketParams} from "@morpho-blue/interfaces/IMorpho.sol";
import {IMorpho} from "@morpho-blue/interfaces/IMorpho.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IPreLiquidationRebalanceAdapter} from "src/interfaces/IPreLiquidationRebalanceAdapter.sol";
import {ICollateralRatiosRebalanceAdapter} from "src/interfaces/ICollateralRatiosRebalanceAdapter.sol";
import {ActionData} from "src/types/DataTypes.sol";
import {RebalanceAdapter} from "src/rebalance/RebalanceAdapter.sol";
import {ILendingAdapter} from "src/interfaces/ILendingAdapter.sol";
import {ILeverageManager} from "src/interfaces/ILeverageManager.sol";
import {IMorphoLendingAdapterFactory} from "src/interfaces/IMorphoLendingAdapterFactory.sol";
import {LeverageTokenConfig} from "src/types/DataTypes.sol";
import {IMorphoLendingAdapter} from "src/interfaces/IMorphoLendingAdapter.sol";
import {ILeverageToken} from "src/interfaces/ILeverageToken.sol";
import {IRebalanceAdapterBase} from "src/interfaces/IRebalanceAdapterBase.sol";
import {DeployConstants} from "./DeployConstants.sol";

contract CreateLeverageToken is Script {
    uint256 public constant WAD = 1e18;

    ILeverageManager public leverageManager = ILeverageManager(DeployConstants.LEVERAGE_MANAGER);
    IMorphoLendingAdapterFactory public lendingAdapterFactory =
        IMorphoLendingAdapterFactory(DeployConstants.LENDING_ADAPTER_FACTORY);

    /// @dev Market ID for Morpho market that LT will be created on top of
    Id public MORPHO_MARKET_ID = Id.wrap(0x8793cf302b8ffd655ab97bd1c695dbd967807e8367a65cb2f4edaf1380ba1bda);
    /// @dev Salt that will be used to deploy the lending adapter. Should be unique for deployer. Update after each deployment.
    bytes32 public BASE_SALT = bytes32(uint256(3));

    /// @dev Minimum collateral ratio for the LT on 18 decimals
    uint256 public MIN_COLLATERAL_RATIO = 1.8e18;
    /// @dev Target collateral ratio for the LT on 18 decimals
    uint256 public TARGET_COLLATERAL_RATIO = 2e18;
    /// @dev Maximum collateral ratio for the LT on 18 decimals
    uint256 public MAX_COLLATERAL_RATIO = 2.2e18;
    /// @dev Duration of the dutch auction for the LT
    uint120 public AUCTION_DURATION = 1 minutes;
    /// @dev Initial oracle price multiplier on Dutch auction on 18 decimals. In percentage.
    uint256 public INITIAL_PRICE_MULTIPLIER = 1.02e18;
    /// @dev Minimum oracle price multiplier on Dutch auction on 18 decimals. In percentage.
    uint256 public MIN_PRICE_MULTIPLIER = 0.98e18;
    /// @dev Collateral ratio threshold for the pre-liquidation rebalance adapter
    /// @dev When collateral ratio falls below this value, rebalance adapter will allow rebalance without Dutch auction for special premium
    uint256 public PRE_LIQUIDATION_COLLATERAL_RATIO_THRESHOLD = 1.3e18;
    /// @dev Rebalance reward for the rebalance adapter, 100% = 10000
    /// @dev Represents reward for pre liquidation rebalance, relative to the liquidation penalty. 50_00 means 50% of liquidation penalty
    /// @dev Liquidation penalty is relative to the lltv on Morpho market.
    uint256 public REBALANCE_REWARD = 50_00;

    /// @dev Token fee when minting. 100% = 10000
    uint256 public MINT_TOKEN_FEE = 1;
    /// @dev Token fee when redeeming. 100% = 10000
    uint256 public REDEEM_TOKEN_FEE = 1;

    /// @dev Name of the LT
    string public LT_NAME = "NAME";
    /// @dev Symbol of the LT
    string public LT_SYMBOL = "SYMBOL";

    /// @dev Initial equity deposit for the LT
    uint256 public INITIAL_EQUITY_DEPOSIT = 0.0001 * 1e18;

    address public COLLATERAL_TOKEN_ADDRESS = 0x4200000000000000000000000000000000000006;
    address public DEBT_TOKEN_ADDRESS = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    string public COLLATERAL_TOKEN_NAME = "Wrapped Ether";
    string public COLLATERAL_TOKEN_SYMBOL = "WETH";
    string public DEBT_TOKEN_NAME = "USD Coin";
    string public DEBT_TOKEN_SYMBOL = "USDC";

    function run() public {
        console.log("BlockNumber: ", block.number);
        console.log("ChainId: ", block.chainid);

        console.log("Deploying...");

        vm.startBroadcast();

        address deployerAddress = msg.sender;
        console.log("DeployerAddress: ", deployerAddress);

        address rebalanceAdapterProxy = Upgrades.deployUUPSProxy(
            "RebalanceAdapter.sol",
            abi.encodeCall(
                RebalanceAdapter.initialize,
                (
                    RebalanceAdapter.RebalanceAdapterInitParams({
                        owner: DeployConstants.SEAMLESS_TIMELOCK_SHORT,
                        authorizedCreator: deployerAddress,
                        leverageManager: leverageManager,
                        minCollateralRatio: MIN_COLLATERAL_RATIO,
                        targetCollateralRatio: TARGET_COLLATERAL_RATIO,
                        maxCollateralRatio: MAX_COLLATERAL_RATIO,
                        auctionDuration: AUCTION_DURATION,
                        initialPriceMultiplier: INITIAL_PRICE_MULTIPLIER,
                        minPriceMultiplier: MIN_PRICE_MULTIPLIER,
                        preLiquidationCollateralRatioThreshold: PRE_LIQUIDATION_COLLATERAL_RATIO_THRESHOLD,
                        rebalanceReward: REBALANCE_REWARD
                    })
                )
            )
        );

        console.log("RebalanceAdapter proxy deployed at: ", address(rebalanceAdapterProxy));

        IMorphoLendingAdapter lendingAdapter =
            lendingAdapterFactory.deployAdapter(MORPHO_MARKET_ID, deployerAddress, BASE_SALT);
        console.log("LendingAdapter deployed at: ", address(lendingAdapter));

        ILeverageToken leverageToken = leverageManager.createNewLeverageToken(
            LeverageTokenConfig({
                lendingAdapter: ILendingAdapter(address(lendingAdapter)),
                rebalanceAdapter: IRebalanceAdapterBase(address(rebalanceAdapterProxy)),
                mintTokenFee: MINT_TOKEN_FEE,
                redeemTokenFee: REDEEM_TOKEN_FEE
            }),
            LT_NAME,
            LT_SYMBOL
        );

        console.log("LeverageToken deployed at: ", address(leverageToken));

        require(Id.unwrap(lendingAdapter.morphoMarketId()) == Id.unwrap(MORPHO_MARKET_ID), "Invalid market");

        IMorpho morpho = IMorpho(DeployConstants.MORPHO);
        MarketParams memory marketParams = morpho.idToMarketParams(lendingAdapter.morphoMarketId());
        IERC20Metadata loanToken = IERC20Metadata(marketParams.loanToken);
        IERC20Metadata collateralToken = IERC20Metadata(marketParams.collateralToken);

        require(address(loanToken) == DEBT_TOKEN_ADDRESS, "Incorrect debt token on Morpho market");
        require(address(collateralToken) == COLLATERAL_TOKEN_ADDRESS, "Incorrect collateral token on Morpho market");

        _assertEqString(loanToken.name(), DEBT_TOKEN_NAME);
        _assertEqString(loanToken.symbol(), DEBT_TOKEN_SYMBOL);
        _assertEqString(collateralToken.name(), COLLATERAL_TOKEN_NAME);
        _assertEqString(collateralToken.symbol(), COLLATERAL_TOKEN_SYMBOL);

        uint256 preLiquidationThreshold =
            IPreLiquidationRebalanceAdapter(address(rebalanceAdapterProxy)).getCollateralRatioThreshold();
        uint256 preLiquidationLltv = Math.mulDiv(WAD, WAD, preLiquidationThreshold);
        uint256 marketLltv = marketParams.lltv;

        require(marketLltv >= preLiquidationLltv, "Market LLTV is less than pre-liquidation LLTV");

        uint256 minCollateralRatio =
            ICollateralRatiosRebalanceAdapter(address(rebalanceAdapterProxy)).getLeverageTokenMinCollateralRatio();
        uint256 minLtv = Math.mulDiv(WAD, WAD, minCollateralRatio);
        require(marketLltv >= minLtv, "Market LLTV is less than min LTV");

        require(
            minCollateralRatio >= preLiquidationThreshold,
            "Min collateral ratio is less than pre-liquidation collateral ratio threshold"
        );

        ActionData memory actionData = leverageManager.previewMint(leverageToken, INITIAL_EQUITY_DEPOSIT);

        collateralToken.approve(address(leverageManager), actionData.collateral);
        leverageManager.mint(leverageToken, INITIAL_EQUITY_DEPOSIT, 0);

        console.log("Performed initial mint to leverage token");

        vm.stopBroadcast();
    }

    function _assertEqString(string memory a, string memory b) internal pure {
        require(keccak256(abi.encodePacked(a)) == keccak256(abi.encodePacked(b)), "Invalid token name or symbol");
    }
}
