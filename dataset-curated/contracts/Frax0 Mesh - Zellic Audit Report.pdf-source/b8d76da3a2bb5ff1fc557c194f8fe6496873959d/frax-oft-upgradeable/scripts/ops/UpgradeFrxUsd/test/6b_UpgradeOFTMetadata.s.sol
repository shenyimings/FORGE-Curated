// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {FrxUSDOFTUpgradeable} from "contracts/frxUsd/FrxUSDOFTUpgradeable.sol";
import {SFrxUSDOFTUpgradeable} from "contracts/frxUsd/SFrxUSDOFTUpgradeable.sol";


/// @dev craft tx to upgrade the FRAX / sFRAX OFT with the new name & symbol
// TODO: add etherscan / verifier links
/// @dev forge script scripts/UpgradeFrax/test/6b_UpgradeOFTMetadata.s.sol --rpc-url https://xlayerrpc.okx.com
contract UpgradeOFTMetadata is DeployFraxOFTProtocol {
    using stdJson for string;
    using Strings for uint256;

    /// @dev these change per chain
    address public frxUsdImplementation;
    address public sfrxUsdImplementation;

    address public cacOft = 0x45682729Bdc0f68e7A02E76E9CfdA57D0cD4d20b;

    constructor() {
        /// @dev declared in BaseL0Script.sol, already deployed
        proxyAdmin = 0x223a681fc5c5522c85C96157c0efA18cd6c5405c;
        // frxUsdOft = 0x80Eede496655FB9047dd39d9f418d5483ED600df;
        // sfrxUsdOft = 0x5Bff88cA1442c2496f7E475E9e7786383Bc070c0;

        if (block.chainid == 34443) {
            // mode
            frxUsdImplementation = 0x83a3581c22C143a574B584af583DE3D6d3A2fD50;
            sfrxUsdImplementation = 0x09EE6975fEff1Ba02d7FEA060Dd196c58e2e4c9E;
        } else if (block.chainid == 1329) {
            // sei
            frxUsdImplementation = 0x9735Eef5e5D7fA1BC5a7956C7439d15D5E658601;
            sfrxUsdImplementation = 0x493f17254f8A6cF7B4346a9d6927148521B03680;
        } else {
            // xlayer
            frxUsdImplementation = 0x9D0FEe988A8134Db109c587DB047761904A34B5b;
            sfrxUsdImplementation = 0xD09F0B6B4b76D5832BfE911793437f5b4c143100;
        }
    }

    function run() public override {
        upgradeOfts();
    }

    function upgradeOfts() public /* simulateAndWriteTxs(broadcastConfig) */  {
        // upgradeOft({
        //     _oft: frxUsdOft,
        //     _implementation: frxUsdImplementation,
        //     _name: "Frax USD",
        //     _symbol: "frxUSD"
        // });
        // upgradeOft({
        //     _oft: sfrxUsdOft,
        //     _implementation: sfrxUsdImplementation,
        //     _name: "Staked Frax USD",
        //     _symbol: "sfrxUSD"
        // });

        uint256 supplyBefore = IERC20(cacOft).totalSupply();

        upgradeOft({
            _oft: cacOft,
            _implementation: frxUsdImplementation
        });

        // state checks
        require(supplyBefore == IERC20(cacOft).totalSupply(), "total supply changed");
        require(isStringEqual("Frax USD", IERC20Metadata(cacOft).name()), "name not changed");
        require(isStringEqual("frxUSD", IERC20Metadata(cacOft).symbol()), "symbol not changed");

        // make sure contract cannot be re-initialized
        bytes memory initialize = abi.encodeCall(
            FraxOFTUpgradeable.initialize,
            (
                "Mock name", "mName", address(1)
            )
        );
        (bool success, ) = cacOft.call(initialize);
        require(!success, "should not be able to initialize");
    }

    function upgradeOft(
        address _oft,
        address _implementation
    ) public broadcastAs(senderDeployerPK) {
        // require(supplyBefore > 0, "Supply before == 0");

        // bytes memory upgrade = abi.encodeCall(
        //     ProxyAdmin.upgrade,
        //     (
        //         TransparentUpgradeableProxy(payable(_oft)),
        //         _implementation
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