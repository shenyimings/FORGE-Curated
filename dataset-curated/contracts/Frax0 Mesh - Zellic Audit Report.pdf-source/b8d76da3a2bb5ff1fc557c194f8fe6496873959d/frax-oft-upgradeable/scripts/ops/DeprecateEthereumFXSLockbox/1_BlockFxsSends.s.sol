pragma solidity ^0.8.0;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";
import { IMessageLibManager } from "@fraxfinance/layerzero-v2-upgradeable/protocol/contracts/interfaces/IMessageLibManager.sol";

interface IEndpointV2 {
    function blockedLibrary() external view returns (address);
}

/// @notice halt FXS bridging through setting the send library to the blocked send library.  This allows in-flight bridges to settle.
// forge script scripts/ops/DeprecateEthereumFXSLockbox/1_BlockFxsSends.s.sol
contract BlockFxsSends is DeployFraxOFTProtocol {
    using Strings for uint256;

    function filename() public view override returns (string memory) {
        string memory root = vm.projectRoot();
        root = string.concat(root, "/scripts/ops/DeprecateEthereumFXSLockbox/txs/");
        string memory name = string.concat("1_BlockFxsSends-", simulateConfig.chainid.toString());
        name = string.concat(name, ".json");
        return string.concat(root, name);
    }

    function run() public override {
        for (uint256 i=0; i<expectedProxyOfts.length; i++) {
            proxyOfts.push(expectedProxyOfts[i]);
        }

        setSendLibs();
    }

    function setSendLibs() public {

        L0Config[] memory ethConfigAsArray = new L0Config[](1);
        for (uint256 i=0; i<proxyConfigs.length; i++) {
            if (proxyConfigs[i].chainid == 1) {
                ethConfigAsArray[0] = proxyConfigs[i];
            }
        }
        require(ethConfigAsArray[0].eid == 30101, "incorrect eth config");

        // push solana to proxyConfigs
        proxyConfigs.push(nonEvmConfigs[0]);

        // loop through all configs minus solana
        for (uint256 c=0; c<proxyConfigs.length - 1; c++) {
            // skip zk-chains
            if (proxyConfigs[c].chainid == 324 || proxyConfigs[c].chainid == 2741) continue;

            // skip fraxtal- maintain bridgeability
            if (proxyConfigs[c].chainid == 252) continue;

            if (proxyConfigs[c].chainid == 1) {
                // For Ethereum lockbox, block sending to all chains
                setSendLib(proxyConfigs[c], proxyConfigs);
            } else {
                // For all other chains, block sending to Ethereum lockbox
                setSendLib(proxyConfigs[c], ethConfigAsArray);
            }
        }
    }

    function setSendLib(
        L0Config memory _config,
        L0Config[] memory _dstConfigs
    ) simulateAndWriteTxs(_config) public virtual {
        address blockedLibrary = IEndpointV2(_config.endpoint).blockedLibrary();
        wfraxOft = connectedOfts[0]; // position 0 is always WFRAX/FXS
    
        // for each destination
        for (uint256 i=0; i<_dstConfigs.length; i++) {
            L0Config memory dstConfig = _dstConfigs[i];

            bytes memory data = abi.encodeCall(
                IMessageLibManager.setSendLibrary,
                (wfraxOft, uint32(dstConfig.eid), blockedLibrary)
            );
            (bool success, ) = _config.endpoint.call(data);
            require(success, "unable to block send library");
            serializedTxs.push(
                SerializedTx({
                    name: "blockSendLibrary",
                    to: _config.endpoint,
                    value: 0,
                    data: data
                })
            );
        }
        
    }
}