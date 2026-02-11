// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import "../lib/forge-std/src/Vm.sol";
import "../src/@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "../src/adapters/resolv/p2pResolvProxyFactory/P2pResolvProxyFactory.sol";
import {Script} from "forge-std/Script.sol";

contract Deploy is Script {
    address constant USR = 0x66a1E37c9b0eAddca17d3662D6c05F4DECf3e110;
    address constant stUSR = 0x6c8984bc7DBBeDAf4F6b2FD766f16eBB7d10AAb4;
    address constant RESOLV = 0x259338656198eC7A76c729514D3CB45Dfbf768A1;
    address constant stRESOLV = 0xFE4BCE4b3949c35fB17691D8b03c3caDBE2E5E23;
    address constant P2pTreasury = 0xfeef177E6168F9b7fd59e6C5b6c2d87FF398c6FD;
    address constant StakedTokenDistributor = 0xCE9d50db432e0702BcAd5a4A9122F1F8a77aD8f9;

    function run()
        external
        returns (P2pResolvProxyFactory factory, P2pResolvProxy proxy)
    {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        Vm.Wallet memory wallet = vm.createWallet(deployerKey);

        vm.startBroadcast(deployerKey);
        AllowedCalldataChecker implementation = new AllowedCalldataChecker();
        ProxyAdmin admin = new ProxyAdmin();
        bytes memory initData = abi.encodeWithSelector(AllowedCalldataChecker.initialize.selector);
        TransparentUpgradeableProxy tup = new TransparentUpgradeableProxy(
            address(implementation),
            address(admin),
            initData
        );
        factory = new P2pResolvProxyFactory(
            wallet.addr,
            P2pTreasury,
            stUSR,
            USR,
            stRESOLV,
            RESOLV,
            address(tup),
            StakedTokenDistributor
        );
        vm.stopBroadcast();

        proxy = P2pResolvProxy(factory.getReferenceP2pYieldProxy());

        return (factory, proxy);
    }
}
