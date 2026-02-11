// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";
import { Constant } from "@fraxfinance/layerzero-v2-upgradeable/messagelib/test/util/Constant.sol";

struct UlnConfig {
    uint64 confirmations;
    // we store the length of required DVNs and optional DVNs instead of using DVN.length directly to save gas
    uint8 requiredDVNCount; // 0 indicate DEFAULT, NIL_DVN_COUNT indicate NONE (to override the value of default)
    uint8 optionalDVNCount; // 0 indicate DEFAULT, NIL_DVN_COUNT indicate NONE (to override the value of default)
    uint8 optionalDVNThreshold; // (0, optionalDVNCount]
    address[] requiredDVNs; // no duplicates. sorted an an ascending order. allowed overlap with optionalDVNs
    address[] optionalDVNs; // no duplicates. sorted an an ascending order. allowed overlap with requiredDVNs
}

/// @dev now that the oft is deployed, setup the adapter
// forge script scripts/ops/dvn/test/4_SetupTestOFT.s.sol --rpc-url https://arbitrum-sepolia.drpc.org --broadcast
contract SetupTestOFT is DeployFraxOFTProtocol {
    address sepoliaOFT = 0x29a5134D3B22F47AD52e0A22A63247363e9F35c2;
    address arbSepoliaOFT = 0x0768C16445B41137F98Ab68CA545C0afD65A7513;
    uint256 sepoliaPeerId = 40161;

    SetConfigParam[] public setConfigParams;

    constructor() {
        delete connectedOfts;
        connectedOfts.push(sepoliaOFT);
        proxyOfts.push(arbSepoliaOFT);
    }

    function run() public override {
        setupSource();
    }

    function setupSource() public override broadcastAs(configDeployerPK) {
        /// @dev set enforced options / peers separately
        setupEvms();

        /// @dev configures legacy configs as well
        setDVNs({ _connectedConfig: broadcastConfig, _connectedOfts: proxyOfts, _configs: allConfigs });

        setLibs({ _connectedConfig: broadcastConfig, _connectedOfts: proxyOfts, _configs: allConfigs });

        // setPriviledgedRoles();
    }

    function setupEvms() public override {
        setEvmEnforcedOptions({ _connectedOfts: proxyOfts, _configs: proxyConfigs });

        /// @dev Upgradeable OFTs maintaining the same address cross-chain.
        setEvmPeers({ _connectedOfts: proxyOfts, _peerOfts: connectedOfts, _configs: proxyConfigs });
    }

    function setEnforcedOptions(
        address[] memory _connectedOfts,
        L0Config[] memory _configs,
        bytes memory _optionsTypeOne,
        bytes memory _optionsTypeTwo
    ) public override {
        // clear out any pre-existing enforced options params
        delete enforcedOptionParams;

        // Build enforced options for each chain
        for (uint256 c = 0; c < _configs.length; c++) {
            // destination peer should only be set
            if (_configs[c].eid != sepoliaPeerId) continue;
            // cannot set enforced options to self
            if (block.chainid == _configs[c].chainid) continue;

            enforcedOptionParams.push(EnforcedOptionParam(uint32(_configs[c].eid), 1, _optionsTypeOne));
            enforcedOptionParams.push(EnforcedOptionParam(uint32(_configs[c].eid), 2, _optionsTypeTwo));
        }

        for (uint256 o = 0; o < _connectedOfts.length; o++) {
            setEnforcedOption({ _connectedOft: _connectedOfts[o] });
        }
    }

    function setEvmPeers(
        address[] memory _connectedOfts,
        address[] memory _peerOfts,
        L0Config[] memory _configs
    ) public override {
        require(_connectedOfts.length == _peerOfts.length, "connectedOfts.length != _peerOfts.length");
        // For each OFT
        for (uint256 o = 0; o < _connectedOfts.length; o++) {
            // Set the config per chain
            for (uint256 c = 0; c < _configs.length; c++) {
                // destination peer should only be set
                if (_configs[c].eid != sepoliaPeerId) continue;
                setPeer({
                    _config: _configs[c],
                    _connectedOft: _connectedOfts[o],
                    _peerOftAsBytes32: addressToBytes32(_peerOfts[o])
                });
            }
        }
    }

    function setDVNs(
        L0Config memory _connectedConfig,
        address[] memory _connectedOfts,
        L0Config[] memory _configs
    ) public override {
        UlnConfig memory ulnConfig;
        ulnConfig.requiredDVNCount = 2;
        address[] memory requiredDVNs = new address[](2);

        // skip setting up DVN if the address is null
        if (_connectedConfig.dvnHorizen == address(0)) return;

        // sort in ascending order (as spec'd in UlnConfig)
        if (uint160(_connectedConfig.dvnHorizen) < uint160(_connectedConfig.dvnL0)) {
            requiredDVNs[0] = _connectedConfig.dvnHorizen;
            requiredDVNs[1] = _connectedConfig.dvnL0;
        } else {
            requiredDVNs[0] = _connectedConfig.dvnL0;
            requiredDVNs[1] = _connectedConfig.dvnHorizen;
        }
        ulnConfig.requiredDVNs = requiredDVNs;

        // push allConfigs
        for (uint256 c = 0; c < _configs.length; c++) {
            // only set config for destination
            if (_configs[c].eid != sepoliaPeerId) continue;
            // cannot set enforced options to self
            if (block.chainid == _configs[c].chainid) continue;

            setConfigParams.push(
                SetConfigParam({
                    eid: uint32(_configs[c].eid),
                    configType: Constant.CONFIG_TYPE_ULN,
                    config: abi.encode(ulnConfig)
                })
            );
        }

        // Submit txs to set DVN
        for (uint256 o = 0; o < _connectedOfts.length; o++) {
            address endpoint = _connectedConfig.endpoint;

            // receiveLib
            bytes memory data = abi.encodeCall(
                IMessageLibManager.setConfig,
                (_connectedOfts[o], _connectedConfig.receiveLib302, setConfigParams)
            );
            (bool success, ) = endpoint.call(data);
            require(success, "Unable to setConfig for receiveLib");
            serializedTxs.push(SerializedTx({ name: "setConfig for receiveLib", to: endpoint, value: 0, data: data }));

            // sendLib
            data = abi.encodeCall(
                IMessageLibManager.setConfig,
                (_connectedOfts[o], _connectedConfig.sendLib302, setConfigParams)
            );
            (success, ) = endpoint.call(data);
            require(success, "Unable to setConfig for sendLib");
            serializedTxs.push(SerializedTx({ name: "setConfig for sendLib", to: endpoint, value: 0, data: data }));
        }
    }

    function setLibs(
        L0Config memory _connectedConfig,
        address[] memory _connectedOfts,
        L0Config[] memory _configs
    ) public override {
        // for each oft
        for (uint256 o = 0; o < _connectedOfts.length; o++) {
            // for each destination
            for (uint256 c = 0; c < _configs.length; c++) {
                // only set config for destination
                if (_configs[c].eid != sepoliaPeerId) continue;
                setLib({ _connectedConfig: _connectedConfig, _connectedOft: _connectedOfts[o], _config: _configs[c] });
            }
        }
    }

    function setPriviledgedRoles() public override {
        /// @dev transfer ownership of OFT
        for (uint256 o = 0; o < proxyOfts.length; o++) {
            address proxyOft = proxyOfts[o];
            FraxOFTUpgradeable(proxyOft).setDelegate(broadcastConfig.delegate);
            Ownable(proxyOft).transferOwnership(broadcastConfig.delegate);
        }
    }
}
