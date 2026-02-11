// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";
import { FraxOFTAdapterUpgradeable } from "contracts/FraxOFTAdapterUpgradeable.sol";
import { IMessageLibManager } from "@fraxfinance/layerzero-v2-upgradeable/protocol/contracts/interfaces/IMessageLibManager.sol";

// forge script scripts/UpgradeFrax/test/4b_UpgradeFraxtalOFT.s.sol --rpc-url https://rpc.frax.com
contract UpgradeFraxtalOFT is DeployFraxOFTProtocol {
    using OptionsBuilder for bytes;
    using stdJson for string;
    using Strings for uint256;

    // address public frxUsd = 0xFc00000000000000000000000000000000000001;
    // address public sfrxUsd = 0xfc00000000000000000000000000000000000008;
    // address public frxUsdAdapterImp = 0xDe41062782F469816cD44ca3B40C16900aaA2EFf;
    // address public sfrxUsdAdapterImp = 0x5abB63fE6214cfb8C8030E01378D732fCDEec74a;
    address public newCac = 0x7131F0ec2aac01a5d30138c2D96C25e4fBbc78CE;
    address public adapterImp = 0xCd223049c07c10bA31612D6fbCe1731E9Cc20Bbf;
    address public cacOft;

    constructor() {
        /// @dev: already deployed
        proxyAdmin = 0x223a681fc5c5522c85C96157c0efA18cd6c5405c;
        // frxUsdOft = 0x80Eede496655FB9047dd39d9f418d5483ED600df;
        // sfrxUsdOft = 0x5Bff88cA1442c2496f7E475E9e7786383Bc070c0;
        cacOft = 0x103C430c9Fcaa863EA90386e3d0d5cd53333876e;
    }

    function run() public override {
        upgradeOfts();
    }

    /// @dev Deploy the FRAX and sFRAX adapter implementations,
    /// upgrade OFT to adapter through ProxyAdmin as delegate (txs must be pranked and crafted for msig execution)
    function upgradeOfts() /* simulateAndWriteTxs(broadcastConfig) */ public {

        // upgrade frax
        // upgradeOft({
        //     _token: frxUsd,
        //     _oft: frxUsdOft,
        //     _implementation: frxUsdAdapterImp
        // });

        // // upgrade sFrax
        // upgradeOft({
        //     _token: sfrxUsd,
        //     _oft: sfrxUsdOft,
        //     _implementation: sfrxUsdAdapterImp
        // });
        upgradeOft({
            _oft: cacOft,
            _implementation: adapterImp
        });

        // Make sure contract cannot be re-initialized
        bytes memory initialize = abi.encodeCall(
            FraxOFTAdapterUpgradeable.initialize,
            (
                address(1)
            )
        );
        (bool success, ) = cacOft.call(initialize);
        require(!success, "should not be able to initialize");

        // Ensure state remains / new token view is added
        require(
            address(FraxOFTUpgradeable(cacOft).endpoint()) == broadcastConfig.endpoint,
            "OFT endpoint incorrect"
        );
        require(
            FraxOFTUpgradeable(cacOft).owner() == vm.addr(configDeployerPK),
            "OFT owner incorrect"
        );
        require(
            FraxOFTAdapterUpgradeable(cacOft).token() == newCac,
            "OFT token not set"
        );

        // ensure old oft methods no longer pass
        (success, ) = cacOft.call(abi.encodeWithSignature("name()"));
        require(!success, "token metadata still exists");
        (success, ) = cacOft.call(abi.encodeWithSignature("totalSupply()"));
        require(!success, "oft supply still exists");
    }

    /// @dev create the oft lockbox implementation and upgrade the proxy to the lockbox
   function upgradeOft(
        address _oft,
        address _implementation
    ) public broadcastAs(senderDeployerPK) {
        // Proxy admin - upgrade to new implementation
        // bytes memory upgrade = abi.encodeCall(
        //     ProxyAdmin.upgrade,
        //     (
        //         TransparentUpgradeableProxy(payable(_oft)), _implementation
        //     )
        // );
        bytes memory upgrade = abi.encodeCall(
            TransparentUpgradeableProxy.upgradeTo,
            (
                _implementation
            )
        );
        // (bool success, ) = proxyAdmin.call(upgrade);
        (bool success, ) = _oft.call(upgrade);
        require(success, "Unable to upgrade proxy");

        // save tx
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