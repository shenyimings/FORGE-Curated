// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract UpgradeOFTMetadata is DeployFraxOFTProtocol {
    using Strings for uint256;

    address public fxsImplementation;

    constructor() {
        for (uint256 i=0; i<expectedProxyOfts.length; i++) {
            proxyOfts.push(expectedProxyOfts[i]);
        }

        if (block.chainid == 34443) { // mode
            fxsImplementation = 0x36076294472DaF59391a7dDbEDeBf4b681D823c7;
        } else if (block.chainid == 1329) { // sei
            fxsImplementation = 0x36076294472DaF59391a7dDbEDeBf4b681D823c7;
        } else if (block.chainid == 196) { // xlayer
            fxsImplementation = 0xa574095bb0Cf76dc1E08C9428C2B59Ebc1FcF1fF;
        } else if (block.chainid == 146) { // sonic
            fxsImplementation = 0x5217Ab28ECE654Aab2C68efedb6A22739df6C3D5;
        } else if (block.chainid == 57073) { // ink
            fxsImplementation = 0x742109450E2466421b00A2Bf61D513D2616a74FC;
        } else if (block.chainid == 42161) { // arbitrum
            fxsImplementation = 0xc6C20B1bDBda2AED8444111a735780a4f208c062;
        } else if (block.chainid == 10) { // optimism
            fxsImplementation = 0x9af0d1cf192bC0b12336c44aE1be62263f8fa117;
        } else if (block.chainid == 137) { // polygon
            fxsImplementation = 0xBB47c4046a73d0b3a9520833e4673C0a3fc03a7A;
        } else if (block.chainid == 43114) { // avalanche
            fxsImplementation = 0x3596FCA443e34D638aCf253D87240BDAb559AF93;
        } else if (block.chainid == 56) { // bsc
            fxsImplementation = 0x80cE6E31fCF84A06923aB58bDCe1eB833C7a359a;
        } else if (block.chainid == 1101) { // polygon zkevm
            fxsImplementation = 0xEAf6C10a5660f3f73aC8340A1f726bcDaeE1b419;
        } else if (block.chainid == 81457) { // blast
            fxsImplementation = 0x8612a9fdf219Ab6C0E92bDD69E2266572c7D893B;
        } else if (block.chainid == 8453) { // base
            fxsImplementation = 0x31E1c1a72e608557ceEEdb4d12d4033baAF4aFB2;
        } else if (block.chainid == 80094) { // berachain
            fxsImplementation = 0xfecBe17dC010Fe68A2b4FcE199A1e289ceE74c2a;
        } else if (block.chainid == 59144) { // linea
            fxsImplementation = 0xEA12Ae50E998D2551eFABE01c569Be4274a6a684;
        } else if (block.chainid == 324) { // zksync
            fxsImplementation = 0x619cc437e9F57f9008a54c5467f3D454a99be435; 
        } else if (block.chainid == 2741) { // abstract
            fxsImplementation = 0x619cc437e9F57f9008a54c5467f3D454a99be435;
        } else {
            revert("Unsupported chain");
        }
    }

    function filename() public view override returns (string memory) {
        string memory root = vm.projectRoot();
        root = string.concat(root, "/scripts/ops/UpgradeFrax/txs/");
        string memory name = string.concat("2_UpgradeOFTMetadata-", simulateConfig.chainid.toString());
        name = string.concat(name, ".json");

        return string.concat(root, name);
    }

    function run() public override simulateAndWriteTxs(broadcastConfig) {
        wfraxOft = connectedOfts[0]; // fxs
        // OZ contracts/proxy/ERC1967/ERC1967Upgrade.sol `_ADMIN_SLOT`
        proxyAdmin = address(uint160(uint256(vm.load(wfraxOft, 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103))));

        // verify OFT is FRAX
        require(isStringEqual("Frax", IERC20Metadata(wfraxOft).name()), "OFT is not FRAX");
        require(isStringEqual("FRAX", IERC20Metadata(wfraxOft).symbol()), "OFT is not FRAX");

        uint256 supplyBefore = IERC20(wfraxOft).totalSupply();

        bytes memory upgrade = abi.encodeCall(
            ProxyAdmin.upgrade,
            (TransparentUpgradeableProxy(payable(wfraxOft)), fxsImplementation)
        );
        (bool success, ) = proxyAdmin.call(upgrade);
        require(success, "Unable to upgrade proxy");

        // state checks
        require(supplyBefore == IERC20(wfraxOft).totalSupply(), "total supply changed");
        require(isStringEqual("Wrapped Frax", IERC20Metadata(wfraxOft).name()), "name not changed");
        require(isStringEqual("WFRAX", IERC20Metadata(wfraxOft).symbol()), "symbol not changed");

        // make sure contract cannot be re-initialized
        bytes memory initialize = abi.encodeCall(
            FraxOFTUpgradeable.initialize,
            ("Mock name", "mName", address(1))
        );
        (success, ) = wfraxOft.call(initialize);
        require(!success, "should not be able to initialize");

        serializedTxs.push(
            SerializedTx({
                name: "upgrade",
                to: proxyAdmin,
                value: 0,
                data: upgrade
            })
        );
    }
}