// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {BoxFactory} from "../src/factories/BoxFactory.sol";
import {BoxAdapterFactory} from "../src/factories/BoxAdapterFactory.sol";
import {MorphoVaultV1AdapterFactory} from "@vault-v2/src/adapters/MorphoVaultV1AdapterFactory.sol";
import {MorphoMarketV1AdapterFactory} from "@vault-v2/src/adapters/MorphoMarketV1AdapterFactory.sol";
import {IMetaMorpho} from "@vault-v2/lib/metamorpho/src/interfaces/IMetaMorpho.sol";
import {MarketParams, IMorpho, Id} from "@vault-v2/lib/morpho-blue/src/interfaces/IMorpho.sol";
import {Id as MetaId} from "@vault-v2/lib/metamorpho/lib/morpho-blue/src/interfaces/IMorpho.sol";
import {MarketParams as MarketParamsBlue, IMorpho as IMorphoBlue} from "@morpho-blue/interfaces/IMorpho.sol";
import {VaultV2Factory} from "@vault-v2/src/VaultV2Factory.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IOracle} from "../src/interfaces/IOracle.sol";
import {IVaultV2} from "@vault-v2/src/interfaces/IVaultV2.sol";
import {IBoxAdapter} from "../src/interfaces/IBoxAdapter.sol";
import {IBox} from "../src/interfaces/IBox.sol";
import {MorphoVaultV1Adapter} from "@vault-v2/src/adapters/MorphoVaultV1Adapter.sol";
import {MorphoMarketV1Adapter} from "@vault-v2/src/adapters/MorphoMarketV1Adapter.sol";
import {MorphoVaultV1AdapterLib} from "../src/periphery/MorphoVaultV1AdapterLib.sol";
import {VaultV2Lib} from "../src/periphery/VaultV2Lib.sol";
import {BoxLib} from "../src/periphery/BoxLib.sol";
import {FundingMorpho} from "../src/FundingMorpho.sol";
import {VaultV2} from "@vault-v2/src/VaultV2.sol";
import {BoxAdapterFactory} from "../src/factories/BoxAdapterFactory.sol";
import {BoxAdapterCachedFactory} from "../src/factories/BoxAdapterCachedFactory.sol";
import {FundingMorphoFactory} from "../src/factories/FundingMorphoFactory.sol";
import {FundingAaveFactory} from "../src/factories/FundingAaveFactory.sol";
import {FlashLoanMorpho} from "../src/periphery/FlashLoanMorpho.sol";
import "@vault-v2/src/libraries/ConstantsLib.sol";
import {ISwapper} from "../src/interfaces/ISwapper.sol";
import {FlashLoanMorpho} from "../src/periphery/FlashLoanMorpho.sol";
import {Box} from "../src/Box.sol";

///@dev This script deploys the necessary contracts for the Peaty product on Base.
///@dev Default factories are hardcoded, but can be overridden using run() which will deploy fresh contracts.
contract DeployEthereumScript is Script {
    using BoxLib for IBox;
    using VaultV2Lib for VaultV2;
    using MorphoVaultV1AdapterLib for MorphoVaultV1Adapter;

    VaultV2Factory vaultV2Factory = VaultV2Factory(0xA1D94F746dEfa1928926b84fB2596c06926C0405);
    MorphoVaultV1AdapterFactory mv1AdapterFactory = MorphoVaultV1AdapterFactory(0xD1B8E2dee25c2b89DCD2f98448a7ce87d6F63394);
    MorphoMarketV1AdapterFactory mm1AdapterFactory = MorphoMarketV1AdapterFactory(0xb049465969ac6355127cDf9E88deE63d25204d5D);

    BoxFactory boxFactory = BoxFactory(0xA1eD8959EF9cCbd57C6b1362938E1DAee96f4473);
    BoxAdapterFactory boxAdapterFactory = BoxAdapterFactory(0x767fa3827d7aA8F69C937689C5ab09412FFc1a2A);
    BoxAdapterCachedFactory boxAdapterCachedFactory = BoxAdapterCachedFactory(0xb5d69fE3149ba4549f5234851d9DaAb83A3c2bE9);
    FundingMorphoFactory fundingMorphoFactory = FundingMorphoFactory(address(0));
    FundingAaveFactory fundingAaveFactory = FundingAaveFactory(address(0));

    address owner = address(0x0000aeB716a0DF7A9A1AAd119b772644Bc089dA8);
    address curator = address(0x0000aeB716a0DF7A9A1AAd119b772644Bc089dA8);
    address guardian = address(0x0000aeB716a0DF7A9A1AAd119b772644Bc089dA8);
    address allocator1 = address(0x0000aeB716a0DF7A9A1AAd119b772644Bc089dA8);
    address allocator2 = address(0xfeed46c11F57B7126a773EeC6ae9cA7aE1C03C9a);

    IERC20 usdc = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

    // Ethena
    IERC20 ptsusde25sep = IERC20(0x9F56094C450763769BA0EA9Fe2876070c0fD5F77);
    IOracle ptsusde25sepOracle = IOracle(0x5139aa359F7F7FdE869305e8C7AD001B28E1C99a);

    IERC20 ptusde25sep = IERC20(0xBC6736d346a5eBC0dEbc997397912CD9b8FAe10a);
    IOracle ptusde25sepOracle = IOracle(0xe6aBD3B78Abbb1cc1Ee76c5c3689Aa9646481Fbb);

    IERC20 ptsusde27nov = IERC20(0xe6A934089BBEe34F832060CE98848359883749B3);
    IOracle ptsusde27novOracle = IOracle(0x639c6f403822E1bDA434BEb2034Beb54f725BA0c);

    IERC20 ptusde27nov = IERC20(0x62C6E813b9589C3631Ba0Cdb013acdB8544038B7);
    IOracle ptusde27novOracle = IOracle(0x0beC5A0f7Bea1D14efC2663054D6D1E2B764b630);

    IERC20 usde = IERC20(0x4c9EDD5852cd905f086C759E8383e09bff1E68B3);
    IOracle usdeOracle = IOracle(0x6779b2F08611906FcE70c70c596e05859701235d);

    IERC20 susde = IERC20(0x9D39A5DE30e57443BfF2A8307A4256c8797A3497);
    IOracle susdeOracle = IOracle(0x873CD44b860DEDFe139f93e12A4AcCa0926Ffb87);

    // Reservoir
    IERC20 ptwsrusd30oct = IERC20(0x10a099BAf814B5FDa138c4e6b60eD42c0d975be8);
    IOracle ptwsrusd30octOracle = IOracle(0x211Cd125045A395c7054D132F3aC53e21D9A2C25);

    IERC20 wsrusd = IERC20(0xd3fD63209FA2D55B07A0f6db36C2f43900be3094);
    IOracle wsrusdOracle = IOracle(0x938D2eDb20425cF80F008E7ec314Eb456940Da15);

    // Coinshift
    IERC20 ptcusdl30oct = IERC20(0xDBf6feC5A012A13c456Bac3B67C3B9CF2830A122);
    IOracle ptcusdl30octOracle = IOracle(0x82dBE10a7D516D8F8b532570134faA81eA63FC51);

    // cUSDO
    IERC20 ptcusdo20nov = IERC20(0xB10DA2F9147f9cf2B8826877Cd0c95c18A0f42dc);
    IOracle ptcusdo20novOracle = IOracle(0x0dF910a47452B995F545D66eb135f38D0FbB142E);

    IMorpho morpho = IMorpho(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb);
    IMetaMorpho bbqusdc = IMetaMorpho(0xBEeFFF209270748ddd194831b3fa287a5386f5bC);

    ISwapper swapper = ISwapper(0x732ca7E5b02f3E9Fe8D5CA7B17B1D1ea47A57A1B);
    FlashLoanMorpho flashLoanMorpho = FlashLoanMorpho(address(0));

    ///@dev This script deploys the necessary contracts for the Peaty product on Base.
    function run() public {
        boxFactory = deployBoxFactory();
        boxAdapterFactory = deployBoxAdapterFactory();
        boxAdapterCachedFactory = deployBoxAdapterCachedFactory();
    }

    function deployBoxFactory() public returns (BoxFactory) {
        vm.startBroadcast();
        BoxFactory boxFactory_ = new BoxFactory();
        console.log("BoxFactory deployed at:", address(boxFactory_));
        new Box(address(usdc), address(1), address(1), "test", "test", 1, 1, 1, 1); // Just for basescan to have the source code
        vm.stopBroadcast();
        return boxFactory_;
    }

    function deployBoxAdapterFactory() public returns (BoxAdapterFactory) {
        vm.startBroadcast();
        BoxAdapterFactory boxAdapterFactory_ = new BoxAdapterFactory();
        console.log("BoxAdapterFactory deployed at:", address(boxAdapterFactory_));
        vm.stopBroadcast();
        return boxAdapterFactory_;
    }

    function deployBoxAdapterCachedFactory() public returns (BoxAdapterCachedFactory) {
        vm.startBroadcast();
        BoxAdapterCachedFactory boxAdapterCachedFactory_ = new BoxAdapterCachedFactory();
        console.log("BoxAdapterCachedFactory deployed at:", address(boxAdapterCachedFactory_));
        vm.stopBroadcast();
        return boxAdapterCachedFactory_;
    }

    function deployFlashLoanMorpho() public {
        vm.startBroadcast();
        FlashLoanMorpho flm = new FlashLoanMorpho(address(morpho));
        console.log("FlashLoanMorpho deployed at:", address(flm));
        vm.stopBroadcast();
    }

    function addMarketsToAdapterFromVault(VaultV2 vault, MorphoMarketV1Adapter mm1Adapter, IMetaMorpho vaultv1) public {
        uint256 length = vaultv1.withdrawQueueLength();
        vault.addCollateralInstant(
            address(mm1Adapter),
            abi.encode("this", address(mm1Adapter)),
            1_000_000_000 * 10 ** 6, // 1_000_000_000 USDC absolute cap
            1 ether // 100% relative cap
        );
        for (uint256 i = 0; i < length; i++) {
            Id id = Id.wrap(MetaId.unwrap(vaultv1.withdrawQueue(i)));
            MarketParams memory marketParams = morpho.idToMarketParams(id);
            // We skip Idle markets
            if (marketParams.collateralToken != address(0)) {
                continue;
            }
            vault.addCollateralInstant(
                address(mm1Adapter),
                abi.encode("collateralToken", marketParams.collateralToken),
                100_000_000 * 10 ** 6, // 100_000_000 USDC absolute cap
                1 ether // 100% relative cap
            );
            vault.addCollateralInstant(
                address(mm1Adapter),
                abi.encode("this/marketParams", address(mm1Adapter), marketParams),
                100_000_000 * 10 ** 6, // 100_000_000 USDC absolute cap
                1 ether // 100% relative cap
            );
        }
    }

    function deployPeaty() public returns (IVaultV2) {
        vm.startBroadcast();

        bytes32 salt = "42";

        VaultV2 vault = VaultV2(vaultV2Factory.createVaultV2(address(tx.origin), address(usdc), salt));
        console.log("Peaty deployed at:", address(vault));

        vault.setCurator(address(tx.origin));

        vault.addAllocatorInstant(address(tx.origin));
        vault.addAllocatorInstant(address(allocator1));
        vault.addAllocatorInstant(address(allocator2));

        vault.setName("Peaty USDC");
        vault.setSymbol("ptUSDC");

        vault.setMaxRate(MAX_MAX_RATE);

        address adapterMV1 = mv1AdapterFactory.createMorphoVaultV1Adapter(address(vault), address(bbqusdc));
        console.log("MorphoVaultV1Adapter deployed at:", adapterMV1);

        vault.addCollateralInstant(
            adapterMV1,
            abi.encode("this", adapterMV1),
            1_000_000_000 * 10 ** 6, // 1_000_000_000 USDC absolute cap
            1 ether // 100% relative cap
        );

        // Creating Box which will invest in Ethena ecosystem
        string memory name = "Box Ethena";
        string memory symbol = "BOX_ETHENA";
        uint256 maxSlippage = 0.0025 ether; // 0.25%
        uint256 slippageEpochDuration = 7 days;
        uint256 shutdownSlippageDuration = 10 days;
        uint256 shutdownWarmup = 7 days;
        IBox box = boxFactory.createBox(
            usdc,
            address(tx.origin),
            address(tx.origin),
            name,
            symbol,
            maxSlippage,
            slippageEpochDuration,
            shutdownSlippageDuration,
            shutdownWarmup,
            salt
        );
        console.log("Box Ethena deployed at:", address(box));
        // Creating the ERC4626 adapter between the vault and box
        IBoxAdapter adapter = boxAdapterFactory.createBoxAdapter(address(vault), box);

        box.addTokenInstant(ptsusde25sep, ptsusde25sepOracle);
        box.addTokenInstant(ptusde25sep, ptusde25sepOracle);
        box.addTokenInstant(ptsusde27nov, ptsusde27novOracle);
        box.addTokenInstant(ptusde27nov, ptusde27novOracle);
        box.addTokenInstant(usde, usdeOracle);
        box.addTokenInstant(susde, susdeOracle);

        box.abdicateTimelock(box.addFunding.selector);

        box.setIsAllocator(address(allocator1), true);
        box.setIsAllocator(address(allocator2), true);
        box.addFeederInstant(address(adapter));
        box.setCurator(address(curator));
        box.transferOwnership(address(owner));
        vault.addCollateralInstant(address(adapter), adapter.adapterData(), 100_000_000 * 10 ** 6, 0.9 ether); // 1,000,000 USDC absolute cap and 90% relative cap
        vault.setForceDeallocatePenaltyInstant(address(adapter), 0.0 ether); // 0% penalty

        IBox boxEthena = box;
        address boxEthenaAdapter = address(adapter);

        // Creating Box which will invest in Reservoir ecosystem
        name = "Box Reservoir";
        symbol = "BOX_RESERVOIR";
        maxSlippage = 0.0025 ether; // 0.25%
        slippageEpochDuration = 7 days;
        shutdownSlippageDuration = 10 days;
        shutdownWarmup = 7 days;
        box = boxFactory.createBox(
            usdc,
            address(tx.origin),
            address(tx.origin),
            name,
            symbol,
            maxSlippage,
            slippageEpochDuration,
            shutdownSlippageDuration,
            shutdownWarmup,
            salt
        );
        console.log("Box Reservoir deployed at:", address(box));
        // Creating the ERC4626 adapter between the vault and box2
        adapter = boxAdapterFactory.createBoxAdapter(address(vault), box);

        // Allow box 2 to invest in PT-WSR-USD-30OCT
        box.addTokenInstant(ptwsrusd30oct, ptwsrusd30octOracle);
        box.addTokenInstant(wsrusd, wsrusdOracle);
        box.abdicateTimelock(box.addFunding.selector);

        box.setIsAllocator(address(allocator1), true);
        box.setIsAllocator(address(allocator2), true);
        box.addFeederInstant(address(adapter));
        box.setCurator(address(curator));
        box.transferOwnership(address(owner));
        vault.addCollateralInstant(address(adapter), adapter.adapterData(), 100_000_000 * 10 ** 6, 0.9 ether); // 1,000,000 USDC absolute cap and 90% relative cap
        vault.setForceDeallocatePenaltyInstant(address(adapter), 0.0 ether); // 0% penalty

        IBox boxReservoir = box;
        address boxReservoirAdapter = address(adapter);

        // Creating Box which will invest in csUSDL ecosystem
        name = "Box csUSDL";
        symbol = "BOX_CSUSDL";
        maxSlippage = 0.0025 ether; // 0.25%
        slippageEpochDuration = 7 days;
        shutdownSlippageDuration = 10 days;
        shutdownWarmup = 7 days;
        box = boxFactory.createBox(
            usdc,
            address(tx.origin),
            address(tx.origin),
            name,
            symbol,
            maxSlippage,
            slippageEpochDuration,
            shutdownSlippageDuration,
            shutdownWarmup,
            salt
        );
        console.log("Box csUSDL deployed at:", address(box));
        // Creating the ERC4626 adapter between the vault and box2
        adapter = boxAdapterFactory.createBoxAdapter(address(vault), box);

        // Allow box 2 to invest in PT-CUSDL-30OCT
        box.addTokenInstant(ptcusdl30oct, ptcusdl30octOracle);
        box.abdicateTimelock(box.addFunding.selector);

        box.setIsAllocator(address(allocator1), true);
        box.setIsAllocator(address(allocator2), true);
        box.addFeederInstant(address(adapter));
        box.setCurator(address(curator));
        box.transferOwnership(address(owner));
        vault.addCollateralInstant(address(adapter), adapter.adapterData(), 100_000_000 * 10 ** 6, 0.9 ether); // 1,000,000 USDC absolute cap and 90% relative cap
        vault.setForceDeallocatePenaltyInstant(address(adapter), 0.0 ether); // 0% penalty

        IBox boxCoinshift = box;
        address boxCoinshiftAdapter = address(adapter);

        // Creating Box which will invest in cUSDO ecosystem
        name = "Box cUSDO";
        symbol = "BOX_CUSDO";
        maxSlippage = 0.0025 ether; // 0.25%
        slippageEpochDuration = 7 days;
        shutdownSlippageDuration = 10 days;
        shutdownWarmup = 7 days;
        box = boxFactory.createBox(
            usdc,
            address(tx.origin),
            address(tx.origin),
            name,
            symbol,
            maxSlippage,
            slippageEpochDuration,
            shutdownSlippageDuration,
            shutdownWarmup,
            salt
        );
        console.log("Box cUSDO deployed at:", address(box));
        // Creating the ERC4626 adapter between the vault and box2
        adapter = boxAdapterFactory.createBoxAdapter(address(vault), box);

        // Allow box 2 to invest in PT-CUSDO-20NOV
        box.addTokenInstant(ptcusdo20nov, ptcusdo20novOracle);
        box.abdicateTimelock(box.addFunding.selector);

        box.setIsAllocator(address(allocator1), true);
        box.setIsAllocator(address(allocator2), true);
        box.addFeederInstant(address(adapter));
        box.setCurator(address(curator));
        box.transferOwnership(address(owner));
        vault.addCollateralInstant(address(adapter), adapter.adapterData(), 100_000_000 * 10 ** 6, 0.9 ether); // 1,000,000 USDC absolute cap and 90% relative cap
        vault.setForceDeallocatePenaltyInstant(address(adapter), 0.0 ether); // 0% penalty

        IBox boxUSDO = box;
        address boxUSDOAdapter = address(adapter);

        //========== Seeding some USDC to the vault for testing ==========
        usdc.approve(address(vault), 10 * 10 ** 6);
        vault.deposit(10 * 10 ** 6, address(vault));

        vault.allocate(adapterMV1, "", 1 * 10 ** 6);

        vault.allocate(boxEthenaAdapter, "", 2 * 10 ** 6);
        boxEthena.allocate(ptusde25sep, 1.6 * 10 ** 6, swapper, "");
        boxEthena.allocate(ptsusde25sep, 0.2 * 10 ** 6, swapper, "");
        boxEthena.allocate(ptusde27nov, 0.1 * 10 ** 6, swapper, "");
        boxEthena.allocate(ptsusde27nov, 0.1 * 10 ** 6, swapper, "");

        vault.allocate(boxReservoirAdapter, "", 2 * 10 ** 6);
        boxReservoir.allocate(ptwsrusd30oct, 1.9 * 10 ** 6, swapper, "");
        boxReservoir.allocate(wsrusd, 0.1 * 10 ** 6, swapper, "");

        vault.allocate(boxCoinshiftAdapter, "", 1 * 10 ** 6);
        boxCoinshift.allocate(ptcusdl30oct, 1 * 10 ** 6, swapper, "");

        vault.allocate(boxUSDOAdapter, "", 2 * 10 ** 6);
        boxUSDO.allocate(ptcusdo20nov, 2 * 10 ** 6, swapper, "");

        //========== Preprod settings ==========
        vault.setCurator(address(curator));
        vault.setOwner(address(owner));

        // To fail the script
        // boxEthena.abdicateTimelock(Box.setGuardian.selector);

        vm.stopBroadcast();
        return vault;
    }
}
