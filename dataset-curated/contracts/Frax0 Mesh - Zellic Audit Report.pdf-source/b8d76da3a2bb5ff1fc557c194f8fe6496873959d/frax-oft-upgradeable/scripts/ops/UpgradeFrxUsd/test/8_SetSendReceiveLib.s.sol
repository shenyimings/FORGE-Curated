// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";
import { IMessageLibManager } from "@fraxfinance/layerzero-v2-upgradeable/protocol/contracts/interfaces/IMessageLibManager.sol";

/// @dev On ethereum, reset the peers of FRAX / sFRAX to prevent bridging.  Additionally, reset the peers of FRAX / sFRAX
///        on destination chains to prevent bridging
// forge script scripts/UpgradeFrax/test/8_SetSendReceiveLib.s.sol --rpc-url https://mainnet.base.org
contract SetSendReceiveLib is DeployFraxOFTProtocol {
    using stdJson for string;
    using Strings for uint256;

    /// @dev skip deployment, set oft addrs to only FRAX/sFRAX
    function run() public override {
        delete legacyOfts;
        // legacyOfts.push(0x909DBdE1eBE906Af95660033e478D59EFe831fED); // FRAX
        // legacyOfts.push(0xe4796cCB6bB5DE2290C417Ac337F2b66CA2E770E); // sFRAX
        legacyOfts.push(0xa536976c9cA36e74Af76037af555eefa632ce469); // base CAC OFT adapter

        delete proxyOfts;
        // proxyOfts.push(0x80Eede496655FB9047dd39d9f418d5483ED600df); // FRAX
        // proxyOfts.push(0x5Bff88cA1442c2496f7E475E9e7786383Bc070c0); // sFRAX

        setLibs();
    }

    function setLibs() public {
        // For legacy chains, unblock legacy paths
        for (uint256 c=0; c<legacyConfigs.length; c++) {
            if (legacyConfigs[c].chainid != 8453) continue; // only for base
            setLib(legacyOfts, legacyConfigs, legacyConfigs[c]);
        }
        // For proxy chains, unblock proxy paths
        // for (uint256 c=0; c<proxyConfigs.length; c++) {
        //     setLib(proxyOfts, proxyConfigs, proxyConfigs[c]);
        // }
    }

    function setLib(
        address[] memory _connectedOfts,
        L0Config[] memory _peerConfigs,
        L0Config memory _config
    ) broadcastAs(configDeployerPK) public {

        // for both FRAX/sFRAX
        for (uint256 o=0; o<_connectedOfts.length; o++) {
            address connectedOft = _connectedOfts[o];
            
            // For each destination
            for (uint256 c=0; c<_peerConfigs.length; c++) {
                uint32 eid = uint32(_peerConfigs[c].eid);

                // skip setting sendLib for self
                if (_config.eid == eid) continue;

                // Set sendLib to default

                bytes memory data = abi.encodeCall(
                    IMessageLibManager.setSendLibrary,
                    (
                        connectedOft, eid, _config.sendLib302
                    )
                );
                (bool success,) = _config.endpoint.call(data);
                require(success, "Unable to call setSendLib");
                serializedTxs.push(
                    SerializedTx({
                        name: "setSendLib",
                        to: _config.endpoint,
                        value: 0,
                        data: data
                    })
                );

                // Set receiveLib to default

                data = abi.encodeCall(
                    IMessageLibManager.setReceiveLibrary,
                    (
                        connectedOft, eid, _config.receiveLib302, 0
                    )
                );
                (success,) = _config.endpoint.call(data);
                require(success, "Unable to cal setReceiveLib");
                serializedTxs.push(
                    SerializedTx({
                        name: "setReceiveLib",
                        to: _config.endpoint,
                        value: 0,
                        data: data
                    })
                );
            }
        }
    }
}