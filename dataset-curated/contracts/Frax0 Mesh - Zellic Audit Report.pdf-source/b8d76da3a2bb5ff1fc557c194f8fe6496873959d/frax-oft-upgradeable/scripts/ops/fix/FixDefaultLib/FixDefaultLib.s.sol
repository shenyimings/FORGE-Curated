// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";
import {IOAppCore} from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oapp/interfaces/IOAppCore.sol";

// Set all default send/receive libraries if there is a peer for the OFT and the default lib is not already set
// forge script scripts/ops/fix/FixDefaultLib/FixDefaultLib.s.sol
contract FixDefaultLib is DeployFraxOFTProtocol {
    using Strings for uint256;
    using stdJson for string;

    function filename() public view override returns (string memory) {
        string memory root = vm.projectRoot();
        root = string.concat(root, "/scripts/ops/fix/FixDefaultLib/txs/");
        string memory name = string.concat("FixDefaultLib-", simulateConfig.chainid.toString());
        name = string.concat(name, ".json");

        return string.concat(root, name);
    }

    function run() public override {
        for (uint256 i=0; i<expectedProxyOfts.length; i++) {
            proxyOfts.push(expectedProxyOfts[i]);
        }

        for (uint256 c=0; c<proxyConfigs.length; c++) {
            fixDefaultLibs(proxyConfigs[c]);
        }
    }

    function fixDefaultLibs(L0Config memory _srcConfig) public simulateAndWriteTxs(_srcConfig) {
        // For each OFT
        for (uint256 o=0; o<connectedOfts.length; o++) {
            address oft = connectedOfts[o];

            // loop through potential destinations
            for (uint256 d=0; d<proxyConfigs.length; d++) {
                L0Config memory dstConfig = proxyConfigs[d];

                // If the OFT has a peer, set the default send/receive libraries
                if (hasPeer(oft, dstConfig)) {
                    
                    // If the default send library is not set, set it
                    if (isDefaultSendLib(oft, _srcConfig, dstConfig)) {
                        setDefaultSendLib(oft, _srcConfig, dstConfig);
                    }

                    // if the default receive library is not set, set it
                    if (isDefaultReceiveLib(oft, _srcConfig, dstConfig)) {
                        setDefaultReceiveLib(oft, _srcConfig, dstConfig);
                    }
                        
                }
            }
        }
    }

    function hasPeer(address _oft, L0Config memory _dstConfig) internal view returns (bool) {
        bytes32 peer = IOAppCore(_oft).peers(uint32(_dstConfig.eid));
        return peer != bytes32(0);
    }

    function isDefaultSendLib(address _oft, L0Config memory _srcConfig, L0Config memory _dstConfig) internal view returns (bool) {
        bool isDefault = IMessageLibManager(_srcConfig.endpoint).isDefaultSendLibrary({
            _sender: _oft,
            _eid: uint32(_dstConfig.eid)
        });
        return isDefault;
    }

    function setDefaultSendLib(address _oft, L0Config memory _srcConfig, L0Config memory _dstConfig) internal {
        bytes memory data = abi.encodeCall(
            IMessageLibManager.setSendLibrary,
            (
                _oft, 
                uint32(_dstConfig.eid), 
                _srcConfig.sendLib302
            )
        );
        (bool success, ) = _srcConfig.endpoint.call(data);
        require(success, "Failed to set default send library");
        serializedTxs.push(
            SerializedTx({
                name: "setDefaultSendLib",
                to: _srcConfig.endpoint,
                value: 0,
                data: data
            })
        );
    }

    function isDefaultReceiveLib(address _oft, L0Config memory _srcConfig, L0Config memory _dstConfig) internal view returns (bool) {
        (, bool isDefault) = IMessageLibManager(_srcConfig.endpoint).getReceiveLibrary({
            _receiver: _oft,
            _eid: uint32(_dstConfig.eid)
        });
        return isDefault;
    }

    function setDefaultReceiveLib(address _oft, L0Config memory _srcConfig, L0Config memory _dstConfig) internal {
        bytes memory data = abi.encodeCall(
            IMessageLibManager.setReceiveLibrary,
            (
                _oft,
                uint32(_dstConfig.eid),
                _srcConfig.receiveLib302,
                0
            )
        );
        (bool success, ) = _srcConfig.endpoint.call(data);
        require(success, "Failed to set default receive library");
        serializedTxs.push(
            SerializedTx({
                name: "setDefaultReceiveLib",
                to: _srcConfig.endpoint,
                value: 0,
                data: data
            })
        );
    }
}