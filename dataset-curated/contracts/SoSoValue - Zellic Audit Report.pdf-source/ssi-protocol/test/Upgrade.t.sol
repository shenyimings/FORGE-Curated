// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;
import "forge-std/console.sol";
import {Test, console} from "forge-std/Test.sol";
import "./MockToken.sol";
import "../src/Interface.sol";
import {Swap} from "../src/Swap.sol";
import {AssetFactory} from "../src/AssetFactory.sol";
import {AssetToken} from "../src/AssetFactory.sol";
import {AssetController} from "../src/AssetController.sol";
import {AssetIssuer} from "../src/AssetIssuer.sol";
import {AssetRebalancer} from "../src/AssetRebalancer.sol";
import {AssetFeeManager} from "../src/AssetFeeManager.sol";
import {StakeToken} from "../src/StakeToken.sol";
import {StakeFactory} from "../src/StakeFactory.sol";
import {AssetLocking} from "../src/AssetLocking.sol";
import {USSI} from "../src/USSI.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Upgrades} from "../lib/openzeppelin-foundry-upgrades/src/Upgrades.sol";

contract UpgradeTest is Test {
    MockToken WBTC = new MockToken("Wrapped BTC", "WBTC", 8);

    address owner = vm.addr(0x1);
    address vault = vm.addr(0x2);
    address orderSigner = vm.addr(0x3);
    address redeemToken = vm.addr(0x4);
    string chain = "SETH";

    AssetFactory factory;
    address assetToken;
    StakeFactory stakeFactory;
    address stakeToken;
    AssetLocking assetLocking;
    USSI uSSI;
    StakeToken sUSSI;
    AssetIssuer issuer;
    AssetFeeManager feeManager;
    AssetRebalancer rebalancer;
    Swap swap;

    function getAsset() public view returns (Asset memory) {
        Token[] memory tokenset_ = new Token[](1);
        tokenset_[0] = Token({
            chain: "SETH",
            symbol: WBTC.symbol(),
            addr: vm.toString(address(WBTC)),
            decimals: WBTC.decimals(),
            amount: 10 * 10 ** WBTC.decimals() / 60000
        });
        Asset memory asset = Asset({
            id: 1,
            name: "BTC",
            symbol: "BTC",
            tokenset: tokenset_
        });
        return asset;
    }

    function setUp() public {
        swap = Swap(address(new ERC1967Proxy(
            address(new Swap()),
            abi.encodeCall(Swap.initialize, (owner, chain)))
        ));
        AssetToken tokenImpl = new AssetToken();
        AssetFactory factoryImpl = new AssetFactory();
        factory = AssetFactory(address(new ERC1967Proxy(
            address(factoryImpl),
            abi.encodeCall(AssetFactory.initialize, (owner, vault, chain, address(tokenImpl)))
        )));
        AssetIssuer issuerImpl = new AssetIssuer();
        issuer = AssetIssuer(address(new ERC1967Proxy(
            address(issuerImpl),
            abi.encodeCall(AssetController.initialize, (owner, address(factory)))
        )));
        AssetRebalancer rebalancerImpl = new AssetRebalancer();
        rebalancer = AssetRebalancer(address(new ERC1967Proxy(
            address(rebalancerImpl),
            abi.encodeCall(AssetController.initialize, (owner, address(factory)))
        )));
        AssetFeeManager feeManagerImpl = new AssetFeeManager();
        feeManager = AssetFeeManager(address(new ERC1967Proxy(
            address(feeManagerImpl),
            abi.encodeCall(AssetController.initialize, (owner, address(factory)))
        )));

        vm.startPrank(owner);
        assetToken = AssetFactory(factory).createAssetToken(getAsset(), 10000, address(issuer), address(rebalancer), address(feeManager), address(swap));
        vm.stopPrank();

        StakeToken stakeTokenImpl = new StakeToken();
        StakeFactory stakeFactoryImpl = new StakeFactory();
        stakeFactory = StakeFactory(address(new ERC1967Proxy(
            address(stakeFactoryImpl),
            abi.encodeCall(StakeFactory.initialize, (owner, address(factory), address(stakeTokenImpl)))
        )));

        vm.startPrank(owner);
        stakeToken = StakeFactory(stakeFactory).createStakeToken(1, 10000);
        vm.stopPrank();

        assetLocking = AssetLocking(address(new ERC1967Proxy(
            address(new AssetLocking()),
            abi.encodeCall(AssetLocking.initialize, owner)
        )));
        uSSI = USSI(address(new ERC1967Proxy(
            address(new USSI()),
            abi.encodeCall(USSI.initialize, (owner, orderSigner, address(factory), redeemToken, "SETH"))
        )));
        sUSSI = StakeToken(address(new ERC1967Proxy(
            address(stakeTokenImpl),
            abi.encodeCall(StakeToken.initialize, ("Staked USSI", "sUSSI", address(uSSI), 7 days, owner))
        )));
    }

    function test_UpgradeContracts() public {
        address factoryImpl = address(new AssetFactory());
        address tokenImpl = address(new AssetToken());
        address stImpl = address(new StakeToken());
        vm.expectRevert();
        factory.upgradeToAndCall(factoryImpl, new bytes(0));
        vm.startPrank(owner);
        // upgrade factory
        factory.upgradeToAndCall(factoryImpl, new bytes(0));
        assertEq(Upgrades.getImplementationAddress(address(factory)), factoryImpl);
        uint256[] memory assetIDs = factory.getAssetIDs();
        assertEq(assetIDs.length, 1);
        // upgrade asset token
        address oldTokenImpl = factory.tokenImpl();
        factory.setTokenImpl(tokenImpl);
        assertNotEq(oldTokenImpl, tokenImpl);
        assertEq(assetToken, factory.assetTokens(1));
        assertNotEq(Upgrades.getImplementationAddress(assetToken), tokenImpl);
        uint256[] memory toUpgradeAssetIDs = new uint256[](1);
        toUpgradeAssetIDs[0] = 1;
        factory.upgradeTokenImpl(toUpgradeAssetIDs);
        assertEq(factory.tokenImpls(1), tokenImpl);
        assertEq(Upgrades.getImplementationAddress(assetToken), tokenImpl);
        // upgrade stake factory
        address stakeFactoryImpl = address(new StakeFactory());
        stakeFactory.upgradeToAndCall(stakeFactoryImpl, new bytes(0));
        (uint256[] memory ids, address[] memory stTokens) = stakeFactory.getStakeTokens();
        assertEq(Upgrades.getImplementationAddress(address(stakeFactory)), stakeFactoryImpl);
        assertEq(ids.length, 1);
        assertEq(stTokens.length, 1);
        assertEq(stTokens[0], stakeToken);
        // upgrade stake token
        address oldSTImpl = stakeFactory.stImpl();
        stakeFactory.setSTImpl(stImpl);
        assertNotEq(Upgrades.getImplementationAddress(stakeToken), stImpl);
        stakeFactory.upgradeSTImpl(toUpgradeAssetIDs);
        assertEq(stakeFactory.stImpls(1), stImpl);
        assertEq(Upgrades.getImplementationAddress(stakeToken), stImpl);
        assertNotEq(oldSTImpl, stImpl);
        assertEq(stakeToken, stTokens[0]);
        // upgrade asset locking
        address lockImpl = address(new AssetLocking());
        assetLocking.upgradeToAndCall(lockImpl, new bytes(0));
        assertEq(Upgrades.getImplementationAddress(address(assetLocking)), lockImpl);
        // upgrade sUSSI
        address ussiImpl = address(new USSI());
        uSSI.upgradeToAndCall(ussiImpl, new bytes(0));
        assertEq(Upgrades.getImplementationAddress(address(uSSI)), ussiImpl);
        assertEq(uSSI.symbol(), "USSI");
        // upgrade USSI
        address sussiImpl = address(new StakeToken());
        sUSSI.upgradeToAndCall(sussiImpl, new bytes(0));
        assertEq(Upgrades.getImplementationAddress(address(sUSSI)), sussiImpl);
        assertEq(sUSSI.cooldown(), 7 days);
        // upgrade issuer
        address issuerImpl = address(new AssetIssuer());
        issuer.upgradeToAndCall(issuerImpl, new bytes(0));
        assertEq(Upgrades.getImplementationAddress(address(issuer)), issuerImpl);
        // upgrade rebalancer
        address rebalancerImpl = address(new AssetRebalancer());
        rebalancer.upgradeToAndCall(rebalancerImpl, new bytes(0));
        assertEq(Upgrades.getImplementationAddress(address(rebalancer)), rebalancerImpl);
        // upgrade feeManager
        address feeManagerImpl = address(new AssetFeeManager());
        feeManager.upgradeToAndCall(feeManagerImpl, new bytes(0));
        assertEq(Upgrades.getImplementationAddress(address(feeManager)), feeManagerImpl);
        // upgrade swap
        address swapImpl = address(new Swap());
        swap.upgradeToAndCall(swapImpl, new bytes(0));
        assertEq(Upgrades.getImplementationAddress(address(feeManager)), feeManagerImpl);
        vm.stopPrank();
    }
}
