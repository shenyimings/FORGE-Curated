// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";
import { IMessageLibManager } from "@fraxfinance/layerzero-v2-upgradeable/protocol/contracts/interfaces/IMessageLibManager.sol";

interface IEndpointV2 {
    function blockedLibrary() external view returns (address);
}

// forge script scripts/UpgradeFrax/test/1_BlockSendLib.s.sol --rpc-url https://mainnet.base.org
contract BlockSendLib is DeployFraxOFTProtocol {

    /// @dev skip deployment, set oft addrs to only FRAX/sFRAX
    function run() public override {
        delete legacyOfts;
        legacyOfts.push(0xa536976c9cA36e74Af76037af555eefa632ce469); // COFT on Base

        setSendLibs();
    }

    function setSendLibs() public {
        // set for legacy chains
        for (uint256 c=0; c<legacyConfigs.length; c++) {
            // only set for base
            if (legacyConfigs[c].chainid != 8453) continue;
            setSendLib(legacyOfts, legacyConfigs[c]);
        }
        // // set for proxy chains
        // for (uint256 c=0; c<proxyConfigs.length; c++) {
        //     // skip blocking for fraxtal- keep open to send mock OFT
        //     if (proxyConfigs[c].chainid == 252) continue;
        //     setSendLib(proxyOfts, proxyConfigs[c]);
        // }
    }

    /// @dev override to broadcast
    function setSendLib(
        address[] memory _connectedOfts,
        L0Config memory _config
    ) broadcastAs(configDeployerPK) public {

        address blockedLibrary = IEndpointV2(_config.endpoint).blockedLibrary();

        // for both FRAX/sFRAX
        for (uint256 o=0; o<_connectedOfts.length; o++) {
            address connectedOft = _connectedOfts[o];
            
            // For each destination
            for (uint256 c=0; c<evmConfigs.length; c++) {
                uint32 eid = uint32(evmConfigs[c].eid);

                // only set sendLib for fraxtal
                if (eid != 30255) continue;

                bytes memory data = abi.encodeCall(
                    IMessageLibManager.setSendLibrary,
                    (
                        connectedOft, eid, blockedLibrary
                    )
                );
                (bool success,) = _config.endpoint.call(data);
                require(success, "Unable to block setSendLib");
                serializedTxs.push(
                    SerializedTx({
                        name: "setSendLib",
                        to: _config.endpoint,
                        value: 0,
                        data: data
                    })
                );
            }
        }
    }
}