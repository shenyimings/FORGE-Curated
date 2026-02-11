// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Forge imports
import {Test} from "forge-std/Test.sol";

// Dependency imports
import {UnsafeUpgrades} from "@foundry-upgrades/Upgrades.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IMorpho, Id} from "@morpho-blue/interfaces/IMorpho.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// Internal imports
import {ILendingAdapter} from "src/interfaces/ILendingAdapter.sol";
import {IMorphoLendingAdapterFactory} from "src/interfaces/IMorphoLendingAdapterFactory.sol";
import {IRebalanceAdapter} from "src/interfaces/IRebalanceAdapter.sol";
import {IRebalanceAdapterBase} from "src/interfaces/IRebalanceAdapterBase.sol";
import {ILeverageManager} from "src/interfaces/ILeverageManager.sol";
import {ILeverageToken} from "src/interfaces/ILeverageToken.sol";
import {MorphoLendingAdapter} from "src/lending/MorphoLendingAdapter.sol";
import {BeaconProxyFactory} from "src/BeaconProxyFactory.sol";
import {LeverageManager} from "src/LeverageManager.sol";
import {LeverageToken} from "src/LeverageToken.sol";
import {LeverageTokenConfig} from "src/types/DataTypes.sol";
import {LeverageManagerHarness} from "test/unit/harness/LeverageManagerHarness.t.sol";
import {MorphoLendingAdapterFactory} from "src/lending/MorphoLendingAdapterFactory.sol";
import {RebalanceAdapter} from "src/rebalance/RebalanceAdapter.sol";

contract IntegrationTestBase is Test {
    uint256 public constant FORK_BLOCK_NUMBER = 25473904;
    uint256 public constant BASE_RATIO = 1e18;

    IERC20 public constant WETH = IERC20(0x4200000000000000000000000000000000000006);
    IERC20 public constant USDC = IERC20(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913);
    IMorpho public constant MORPHO = IMorpho(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb);
    Id public constant WETH_USDC_MARKET_ID = Id.wrap(0x8793cf302b8ffd655ab97bd1c695dbd967807e8367a65cb2f4edaf1380ba1bda);

    address public user = makeAddr("user");
    address public treasury = makeAddr("treasury");

    RebalanceAdapter rebalanceAdapterImplementation;

    ILeverageToken public leverageToken;
    IMorphoLendingAdapterFactory public morphoLendingAdapterFactory;
    ILeverageManager public leverageManager = ILeverageManager(makeAddr("leverageManager"));
    MorphoLendingAdapter public morphoLendingAdapter;
    RebalanceAdapter public rebalanceAdapter;

    function setUp() public virtual {
        vm.createSelectFork(vm.envString("BASE_RPC_URL"), FORK_BLOCK_NUMBER);

        LeverageToken leverageTokenImplementation = new LeverageToken();
        BeaconProxyFactory leverageTokenFactory =
            new BeaconProxyFactory(address(leverageTokenImplementation), address(this));

        address leverageManagerImplementation = address(new LeverageManagerHarness());
        leverageManager = ILeverageManager(
            UnsafeUpgrades.deployUUPSProxy(
                leverageManagerImplementation,
                abi.encodeWithSelector(LeverageManager.initialize.selector, address(this), leverageTokenFactory)
            )
        );
        LeverageManager(address(leverageManager)).grantRole(keccak256("FEE_MANAGER_ROLE"), address(this));

        MorphoLendingAdapter morphoLendingAdapterImplementation =
            new MorphoLendingAdapter(ILeverageManager(leverageManager), MORPHO);

        morphoLendingAdapterFactory = new MorphoLendingAdapterFactory(morphoLendingAdapterImplementation);

        morphoLendingAdapter = MorphoLendingAdapter(
            address(morphoLendingAdapterFactory.deployAdapter(WETH_USDC_MARKET_ID, address(this), bytes32(0)))
        );

        rebalanceAdapterImplementation = new RebalanceAdapter();
        rebalanceAdapter = _deployRebalanceAdapter(1.5e18, 2e18, 2.5e18, 7 minutes, 1.2e18, 0.9e18, 1.2e18, 40_00);

        leverageToken = leverageManager.createNewLeverageToken(
            LeverageTokenConfig({
                lendingAdapter: ILendingAdapter(address(morphoLendingAdapter)),
                rebalanceAdapter: IRebalanceAdapter(address(rebalanceAdapter)),
                depositTokenFee: 0,
                withdrawTokenFee: 0
            }),
            "Seamless ETH/USDC 2x leverage token",
            "ltETH/USDC-2x"
        );

        leverageManager.setTreasury(treasury);

        vm.label(address(user), "user");
        vm.label(address(treasury), "treasury");
        vm.label(address(leverageToken), "leverageToken");
        vm.label(address(morphoLendingAdapter), "morphoLendingAdapter");
        vm.label(address(MORPHO), "MORPHO");
        vm.label(address(leverageManager), "leverageManager");
    }

    function testFork_setUp() public view virtual {
        assertEq(address(morphoLendingAdapter.leverageManager()), address(leverageManager));
        assertEq(address(morphoLendingAdapter.morpho()), address(MORPHO));
        assertEq(leverageManager.getTreasury(), treasury);
        assertEq(address(morphoLendingAdapter.getCollateralAsset()), address(WETH));
        assertEq(address(morphoLendingAdapter.getDebtAsset()), address(USDC));

        assertEq(morphoLendingAdapter.getCollateral(), 0);
        assertEq(morphoLendingAdapter.getCollateralInDebtAsset(), 0);
        assertEq(morphoLendingAdapter.getDebt(), 0);
        assertEq(morphoLendingAdapter.getEquityInCollateralAsset(), 0);
        assertEq(morphoLendingAdapter.getEquityInDebtAsset(), 0);
    }

    function _convertToAssets(uint256 shares) internal view returns (uint256) {
        return Math.mulDiv(
            shares,
            morphoLendingAdapter.getEquityInCollateralAsset() + 1,
            leverageToken.totalSupply() + 1,
            Math.Rounding.Floor
        );
    }

    function _createNewLeverageToken(
        uint256 minColRatio,
        uint256 targetCollateralRatio,
        uint256 maxColRatio,
        uint256 depositFee,
        uint256 withdrawFee
    ) internal returns (ILeverageToken) {
        ILendingAdapter lendingAdapter = ILendingAdapter(
            morphoLendingAdapterFactory.deployAdapter(WETH_USDC_MARKET_ID, address(this), bytes32(vm.randomUint()))
        );

        address _rebalanceAdapter = address(
            _deployRebalanceAdapter(
                minColRatio, targetCollateralRatio, maxColRatio, 7 minutes, 1.2 * 1e18, 0.9 * 1e18, 1.1e18, 40_00
            )
        );

        ILeverageToken _leverageToken = leverageManager.createNewLeverageToken(
            LeverageTokenConfig({
                lendingAdapter: lendingAdapter,
                rebalanceAdapter: IRebalanceAdapter(_rebalanceAdapter),
                depositTokenFee: depositFee,
                withdrawTokenFee: withdrawFee
            }),
            "dummy name",
            "dummy symbol"
        );

        return _leverageToken;
    }

    function _deployRebalanceAdapter(
        uint256 minCollateralRatio,
        uint256 targetCollateralRatio,
        uint256 maxCollateralRatio,
        uint256 auctionDuration,
        uint256 initialPriceMultiplier,
        uint256 minPriceMultiplier,
        uint256 collateralRatioThreshold,
        uint256 rebalanceReward
    ) internal returns (RebalanceAdapter) {
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(rebalanceAdapterImplementation),
            abi.encodeWithSelector(
                RebalanceAdapter.initialize.selector,
                RebalanceAdapter.RebalanceAdapterInitParams({
                    owner: address(this),
                    authorizedCreator: address(this),
                    leverageManager: leverageManager,
                    minCollateralRatio: minCollateralRatio,
                    targetCollateralRatio: targetCollateralRatio,
                    maxCollateralRatio: maxCollateralRatio,
                    auctionDuration: auctionDuration,
                    initialPriceMultiplier: initialPriceMultiplier,
                    minPriceMultiplier: minPriceMultiplier,
                    preLiquidationCollateralRatioThreshold: collateralRatioThreshold,
                    rebalanceReward: rebalanceReward
                })
            )
        );

        return RebalanceAdapter(address(proxy));
    }
}
