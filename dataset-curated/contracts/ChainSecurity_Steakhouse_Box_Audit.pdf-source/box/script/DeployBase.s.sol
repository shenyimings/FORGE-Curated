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

///@dev This script deploys the necessary contracts for the Peaty product on Base.
///@dev Default factories are hardcoded, but can be overridden using run() which will deploy fresh contracts.
contract DeployBaseScript is Script {
    using BoxLib for IBox;
    using VaultV2Lib for VaultV2;
    using MorphoVaultV1AdapterLib for MorphoVaultV1Adapter;

    VaultV2Factory vaultV2Factory = VaultV2Factory(0x45311968F0274808B8549053EfCD9a6A713fB469);
    MorphoVaultV1AdapterFactory mv1AdapterFactory = MorphoVaultV1AdapterFactory(0x1745F0Bf26b184fEb4f7239D00a26707e200c618);
    MorphoMarketV1AdapterFactory mm1AdapterFactory = MorphoMarketV1AdapterFactory(0xf4eaC6AA3eE24ffDa96fb6d5F95aB4C646bcdD20);

    BoxFactory boxFactory = BoxFactory(0x913DeB4ca8a03Aa60c681EE5462630b728Ec2836);
    BoxAdapterFactory boxAdapterFactory = BoxAdapterFactory(0x808F9fcf09921a21aa5Cd71D87BE50c0F05A5203);
    BoxAdapterCachedFactory boxAdapterCachedFactory = BoxAdapterCachedFactory(0x09EA5EafbA623D9012124E05068ab884008f32BD);
    FundingMorphoFactory fundingMorphoFactory = FundingMorphoFactory(address(0));
    FundingAaveFactory fundingAaveFactory = FundingAaveFactory(address(0));

    address owner = address(0x0000aeB716a0DF7A9A1AAd119b772644Bc089dA8);
    address curator = address(0x0000aeB716a0DF7A9A1AAd119b772644Bc089dA8);
    address guardian = address(0x0000aeB716a0DF7A9A1AAd119b772644Bc089dA8);
    address allocator1 = address(0x0000aeB716a0DF7A9A1AAd119b772644Bc089dA8);
    address allocator2 = address(0xfeed46c11F57B7126a773EeC6ae9cA7aE1C03C9a);

    IERC20 usdc = IERC20(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913);

    IMorpho morpho = IMorpho(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb);
    IMetaMorpho bbqusdc = IMetaMorpho(0xBEEFA7B88064FeEF0cEe02AAeBBd95D30df3878F); // bbqUSDC on Base

    IERC4626 stusd = IERC4626(0x0022228a2cc5E7eF0274A7Baa600d44da5aB5776);
    IOracle stusdOracle = IOracle(0x2eede25066af6f5F2dfc695719dB239509f69915);

    IERC20 ptusr25sep = IERC20(0xa6F0A4D18B6f6DdD408936e81b7b3A8BEFA18e77);
    IOracle ptusr25sepOracle = IOracle(0x6AdeD60f115bD6244ff4be46f84149bA758D9085);

    IERC20 ptusde11dec = IERC20(0x194b8FeD256C02eF1036Ed812Cae0c659ee6F7FD);
    IOracle ptusde11decOracle = IOracle(0x15af6e452Fe5C4B78c45f9DE02842a52E600A1cA);

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

        bytes32 salt = "12";

        VaultV2 vault = VaultV2(vaultV2Factory.createVaultV2(address(tx.origin), address(usdc), salt));
        console.log("Peaty deployed at:", address(vault));

        vault.setCurator(address(tx.origin));

        vault.addAllocatorInstant(address(tx.origin));
        vault.addAllocatorInstant(address(allocator1));
        vault.addAllocatorInstant(address(allocator2));

        vault.setName("Peaty USDC");
        vault.setSymbol("ptUSDC");

        vault.setMaxRate(MAX_MAX_RATE);

        // Setting the vault to use bbqUSDC as the asset
        MorphoMarketV1Adapter bbqusdcAdapter = MorphoMarketV1Adapter(
            mm1AdapterFactory.createMorphoMarketV1Adapter(address(vault), address(morpho))
        );

        addMarketsToAdapterFromVault(vault, bbqusdcAdapter, bbqusdc);

        // Creating Box 1 which will invest in stUSD
        string memory name = "Box Angle";
        string memory symbol = "BOX_ANGLE";
        uint256 maxSlippage = 0.0001 ether; // 0.01%
        uint256 slippageEpochDuration = 7 days;
        uint256 shutdownSlippageDuration = 10 days;
        uint256 shutdownWarmup = 7 days;
        IBox box1 = boxFactory.createBox(
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
        console.log("Box Angle deployed at:", address(box1));

        // Creating the ERC4626 adapter between the vault and box1
        IBoxAdapter adapter1 = boxAdapterFactory.createBoxAdapter(address(vault), box1);

        // Allow box 1 to invest in stUSD
        box1.addTokenInstant(stusd, stusdOracle);
        box1.setIsAllocator(address(allocator1), true);
        box1.setIsAllocator(address(allocator2), true);
        box1.addFeederInstant(address(adapter1));
        box1.setCurator(address(curator));
        box1.transferOwnership(address(owner));
        vault.addCollateralInstant(address(adapter1), adapter1.adapterData(), 10_000_000 * 10 ** 6, 1 ether); // 1,000,000 USDC absolute cap and 50% relative cap

        // Creating Box 2 which will invest in PT-USR-25SEP
        name = "Box Ethena";
        symbol = "BOX_ETHENA";
        maxSlippage = 0.01 ether; // 0.1%
        slippageEpochDuration = 7 days;
        shutdownSlippageDuration = 10 days;
        shutdownWarmup = 7 days;
        IBox box2 = boxFactory.createBox(
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
        console.log("Box Ethena deployed at:", address(box2));
        // Creating the ERC4626 adapter between the vault and box2
        IBoxAdapter adapter2 = boxAdapterFactory.createBoxAdapter(address(vault), box2);

        // Allow box 2 to invest in PT-USR-25SEP
        box2.addTokenInstant(ptusde11dec, ptusde11decOracle);

        box2.setIsAllocator(address(allocator1), true);
        box2.setIsAllocator(address(allocator2), true);
        box2.addFeederInstant(address(adapter2));
        box2.setCurator(address(curator));
        box2.transferOwnership(address(owner));
        vault.addCollateralInstant(address(adapter2), adapter2.adapterData(), 100_000_000 * 10 ** 6, 0.9 ether); // 1,000,000 USDC absolute cap and 90% relative cap
        vault.setForceDeallocatePenaltyInstant(address(adapter2), 0.02 ether); // 2% penalty

        // Creating Box 2 which will invest in PT-USR-25SEP
        name = "Box Resolv";
        symbol = "BOX_RESOLV";
        maxSlippage = 0.001 ether; // 0.1%
        slippageEpochDuration = 7 days;
        shutdownSlippageDuration = 10 days;
        shutdownWarmup = 7 days;
        box2 = boxFactory.createBox(
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
        console.log("Box Resolv deployed at:", address(box2));
        // Creating the ERC4626 adapter between the vault and box2
        adapter2 = boxAdapterFactory.createBoxAdapter(address(vault), box2);

        // Allow box 2 to invest in PT-USR-25SEP
        box2.addTokenInstant(ptusr25sep, ptusr25sepOracle);

        box2.setIsAllocator(address(allocator1), true);
        box2.setIsAllocator(address(allocator2), true);
        box2.addFeederInstant(address(adapter2));
        box2.setCurator(address(curator));
        box2.transferOwnership(address(owner));
        vault.addCollateralInstant(address(adapter2), adapter2.adapterData(), 100_000_000 * 10 ** 6, 0.9 ether); // 1,000,000 USDC absolute cap and 90% relative cap
        vault.setForceDeallocatePenaltyInstant(address(adapter2), 0.02 ether); // 2% penalty

        vault.removeAllocatorInstant(address(tx.origin));
        vault.setCurator(address(curator));
        vault.setOwner(address(owner));

        vm.stopBroadcast();
        return vault;
    }

    function deployPeatyTurbo() public returns (IVaultV2) {
        vm.startBroadcast();

        bytes32 salt = "12";

        VaultV2 vault = VaultV2(vaultV2Factory.createVaultV2(address(tx.origin), address(usdc), salt));
        console.log("Peaty deployed at:", address(vault));

        vault.setCurator(address(tx.origin));

        vault.addAllocatorInstant(address(tx.origin));
        vault.addAllocatorInstant(address(allocator1));
        vault.addAllocatorInstant(address(allocator2));

        vault.setName("Peaty USDC Turbo");
        vault.setSymbol("ptUSDCturbo");

        vault.setMaxRate(MAX_MAX_RATE);

        // Setting the vault to use bbqUSDC as the asset
        MorphoMarketV1Adapter bbqusdcAdapter = MorphoMarketV1Adapter(
            mm1AdapterFactory.createMorphoMarketV1Adapter(address(vault), address(morpho))
        );

        addMarketsToAdapterFromVault(vault, bbqusdcAdapter, bbqusdc);

        // Creating Box 1 which will invest in stUSD
        string memory name = "Box Angle";
        string memory symbol = "BOX_ANGLE";
        uint256 maxSlippage = 0.001 ether; // 0.1%
        uint256 slippageEpochDuration = 7 days;
        uint256 shutdownSlippageDuration = 10 days;
        uint256 shutdownWarmup = 7 days;
        IBox box1 = boxFactory.createBox(
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
        console.log("Box Angle deployed at:", address(box1));

        // Creating the ERC4626 adapter between the vault and box1
        IBoxAdapter adapter1 = boxAdapterFactory.createBoxAdapter(address(vault), box1);

        // Allow box 1 to invest in stUSD
        box1.addTokenInstant(stusd, stusdOracle);
        box1.setIsAllocator(address(allocator1), true);
        box1.setIsAllocator(address(allocator2), true);
        box1.addFeederInstant(address(adapter1));
        box1.setCurator(address(curator));
        box1.transferOwnership(address(owner));
        vault.addCollateralInstant(address(adapter1), adapter1.adapterData(), 10_000_000 * 10 ** 6, 1 ether); // 1,000,000 USDC absolute cap and 50% relative cap

        // Creating Box 2 which will invest in PT-USR-25SEP
        name = "Box Ethena";
        symbol = "BOX_ETHENA";
        maxSlippage = 0.001 ether; // 0.1%
        slippageEpochDuration = 7 days;
        shutdownSlippageDuration = 10 days;
        shutdownWarmup = 7 days;
        IBox box2 = boxFactory.createBox(
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
        console.log("Box Ethena deployed at:", address(box2));
        // Creating the ERC4626 adapter between the vault and box2
        IBoxAdapter adapter2 = boxAdapterFactory.createBoxAdapter(address(vault), box2);

        // Allow box 2 to invest in PT-USR-25SEP
        box2.addTokenInstant(ptusde11dec, ptusde11decOracle);

        FundingMorpho fundingMorpho = new FundingMorpho(address(box2), address(morpho), 99e16);
        MarketParamsBlue memory fundingMarketParams = MarketParamsBlue({
            loanToken: address(usdc),
            collateralToken: address(ptusde11dec),
            oracle: address(ptusde11decOracle),
            irm: 0x46415998764C29aB2a25CbeA6254146D50D22687,
            lltv: 915000000000000000
        });
        bytes memory facilityData = fundingMorpho.encodeFacilityData(fundingMarketParams);
        box2.addFundingInstant(fundingMorpho);
        box2.addFundingCollateralInstant(fundingMorpho, ptusde11dec);
        box2.addFundingDebtInstant(fundingMorpho, usdc);
        box2.addFundingFacilityInstant(fundingMorpho, facilityData);

        box2.setIsAllocator(address(allocator1), true);
        box2.setIsAllocator(address(allocator2), true);
        box2.addFeederInstant(address(adapter2));
        box2.setCurator(address(curator));
        box2.transferOwnership(address(owner));
        vault.addCollateralInstant(address(adapter2), adapter2.adapterData(), 1_000_000 * 10 ** 6, 0.9 ether); // 1,000,000 USDC absolute cap and 90% relative cap
        vault.setForceDeallocatePenaltyInstant(address(adapter2), 0.02 ether); // 2% penalty

        // Creating Box 2 which will invest in PT-USR-25SEP
        name = "Box Resolv";
        symbol = "BOX_RESOLV";
        maxSlippage = 0.001 ether; // 0.1%
        slippageEpochDuration = 7 days;
        shutdownSlippageDuration = 10 days;
        shutdownWarmup = 7 days;
        box2 = boxFactory.createBox(
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
        console.log("Box Resolv deployed at:", address(box2));
        // Creating the ERC4626 adapter between the vault and box2
        adapter2 = boxAdapterFactory.createBoxAdapter(address(vault), box2);

        // Allow box 2 to invest in PT-USR-25SEP
        box2.addTokenInstant(ptusr25sep, ptusr25sepOracle);

        fundingMorpho = new FundingMorpho(address(box2), address(morpho), 99e16);
        fundingMarketParams = MarketParamsBlue({
            loanToken: address(usdc),
            collateralToken: address(ptusr25sep),
            oracle: address(ptusr25sepOracle),
            irm: 0x46415998764C29aB2a25CbeA6254146D50D22687,
            lltv: 915000000000000000
        });
        facilityData = fundingMorpho.encodeFacilityData(fundingMarketParams);
        box2.addFundingInstant(fundingMorpho);
        box2.addFundingCollateralInstant(fundingMorpho, ptusr25sep);
        box2.addFundingDebtInstant(fundingMorpho, usdc);
        box2.addFundingFacilityInstant(fundingMorpho, facilityData);

        box2.setIsAllocator(address(allocator1), true);
        box2.setIsAllocator(address(allocator2), true);
        box2.addFeederInstant(address(adapter2));
        box2.setCurator(address(curator));
        box2.transferOwnership(address(owner));
        vault.addCollateralInstant(address(adapter2), adapter2.adapterData(), 1_000_000 * 10 ** 6, 0.9 ether); // 1,000,000 USDC absolute cap and 90% relative cap
        vault.setForceDeallocatePenaltyInstant(address(adapter2), 0.02 ether); // 2% penalty

        vault.removeAllocatorInstant(address(tx.origin));
        vault.setCurator(address(curator));
        vault.setOwner(address(owner));

        vm.stopBroadcast();
        return vault;
    }

    /*
    function deployPeatyCBBTC() public returns (IVaultV2) {
        vm.startBroadcast();

        bytes32 salt = "12";

        VaultV2 vault = VaultV2(vaultV2Factory.createVaultV2(address(tx.origin), address(usdc), salt));
        console.log("Peaty cbBTC deployed at:", address(vault));

        vault.setCurator(address(tx.origin));

        vault.addAllocatorInstant(address(tx.origin));
        vault.addAllocatorInstant(address(allocator1));
        vault.addAllocatorInstant(address(allocator2));

        vault.setName("Peaty cbBTC");
        vault.setSymbol("ptCBTC");

        vault.setMaxRate(MAX_MAX_RATE);

        // Creating Box 1 which will invest in stUSD
        string memory name = "Box Peaty";
        string memory symbol = "BOX_PEATY";
        uint256 maxSlippage = 0.003 ether; // 0.3%
        uint256 slippageEpochDuration = 7 days;
        uint256 shutdownSlippageDuration = 10 days;
        uint256 shutdownWarmup = 7 days;
        IBox box1 = boxFactory.createBox(
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
        console.log("Box Peaty deployed at:", address(box1));

        // Creating the ERC4626 adapter between the vault and box1
        IBoxAdapter adapter1 = boxAdapterFactory.createBoxAdapter(address(vault), box1);

        // Allow box 1 to invest in stUSD
        box1.addTokenInstant(stusd, stusdOracle);
        box1.setIsAllocator(address(allocator1), true);
        box1.setIsAllocator(address(allocator2), true);
        box1.addFeederInstant(address(adapter1));
        box1.setCurator(address(curator));
        box1.transferOwnership(address(owner));
        vault.addCollateralInstant(address(adapter1), adapter1.adapterData(), 10_000_000 * 10 ** 6, 1 ether); // 1,000,000 USDC absolute cap and 50% relative cap

        FundingMorpho fundingMorpho = new FundingMorpho(address(box2), address(morpho), 99e16);
        MarketParamsBlue memory fundingMarketParams = MarketParamsBlue({
            loanToken: address(usdc),
            collateralToken: address(cbbtc),
            oracle: address(),
            irm: 0x46415998764C29aB2a25CbeA6254146D50D22687,
            lltv: 860000000000000000
        });
        bytes memory facilityData = fundingMorpho.encodeFacilityData(fundingMarketParams);
        box1.addFundingInstant(fundingMorpho);
        box1.addFundingCollateralInstant(fundingMorpho, cbbtc);
        box1.addFundingDebtInstant(fundingMorpho, usdc);
        box1.addFundingFacilityInstant(fundingMorpho, facilityData);



        // Creating Box 2 which will invest in PT-USR-25SEP
        name = "Box Resolv";
        symbol = "BOX_RESOLV";
        maxSlippage = 0.001 ether; // 0.1%
        slippageEpochDuration = 7 days;
        shutdownSlippageDuration = 10 days;
        shutdownWarmup = 7 days;
        box2 = boxFactory.createBox(
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
        console.log("Box Resolv deployed at:", address(box2));
        // Creating the ERC4626 adapter between the vault and box2
        adapter2 = boxAdapterFactory.createBoxAdapter(address(vault), box2);

        // Allow box 2 to invest in PT-USR-25SEP
        box2.addTokenInstant(ptusr25sep, ptusr25sepOracle);

        fundingMorpho = new FundingMorpho(address(box2), address(morpho), 99e16);
        fundingMarketParams = MarketParamsBlue({
            loanToken: address(usdc),
            collateralToken: address(ptusr25sep),
            oracle: address(ptusr25sepOracle),
            irm: 0x46415998764C29aB2a25CbeA6254146D50D22687,
            lltv: 915000000000000000
        });
        facilityData = fundingMorpho.encodeFacilityData(fundingMarketParams);
        box2.addFundingInstant(fundingMorpho);
        box2.addFundingCollateralInstant(fundingMorpho, ptusr25sep);
        box2.addFundingDebtInstant(fundingMorpho, usdc);
        box2.addFundingFacilityInstant(fundingMorpho, facilityData);

        box2.setIsAllocator(address(allocator1), true);
        box2.setIsAllocator(address(allocator2), true);
        box2.addFeederInstant(address(adapter2));
        box2.setCurator(address(curator));
        box2.transferOwnership(address(owner));
        vault.addCollateralInstant(address(adapter2), adapter2.adapterData(), 1_000_000 * 10 ** 6, 0.9 ether); // 1,000,000 USDC absolute cap and 90% relative cap
        vault.setForceDeallocatePenaltyInstant(address(adapter2), 0.02 ether); // 2% penalty

        vault.removeAllocatorInstant(address(tx.origin));
        vault.setCurator(address(curator));
        vault.setOwner(address(owner));

        vm.stopBroadcast();
        return vault;
    }*/
}
