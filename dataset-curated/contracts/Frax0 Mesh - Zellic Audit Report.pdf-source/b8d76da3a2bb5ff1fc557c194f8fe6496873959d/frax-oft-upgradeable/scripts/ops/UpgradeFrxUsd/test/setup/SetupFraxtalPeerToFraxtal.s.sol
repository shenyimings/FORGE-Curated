// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";
import "scripts/DeployFraxOFTProtocol/inherited/SetDVNs.s.sol";

/// @dev Set the fraxtal peer to fraxtal to see if we can send to self
// forge script scripts/ops/UpgradeFrxUsd/test/setup/SetupFraxtalPeerToFraxtal.s.sol --rpc-url https://rpc.frax.com
contract SetupFraxtalOFT is DeployFraxOFTProtocol {
    address fraxtalOft = 0x103C430c9Fcaa863EA90386e3d0d5cd53333876e;
    // address xlayerOft = 0x45682729Bdc0f68e7A02E76E9CfdA57D0cD4d20b;

    SetConfigParam[] setConfigParams;

    constructor() {
        delete connectedOfts;
        connectedOfts.push(fraxtalOft);
        proxyOfts.push(fraxtalOft);
    }

    function run() public override {
        // deploySource();
        // setupSource();
        setupDestinations();   
    }

    function setupDestinations() public override {
        // setupLegacyDestinations();
        setupProxyDestinations();
    }

    function setupProxyDestinations() public override {
        for (uint256 i=0; i<proxyConfigs.length; i++) {
            // skip if destination == source
            // if (proxyConfigs[i].eid == broadcastConfig.eid) continue;
            // skip if not fraxtal
            if (proxyConfigs[i].chainid != 252) continue;
            setupDestination(proxyConfigs[i], connectedOfts);
        }
    }

    function setupDestination(
        L0Config memory /* _connectedConfig */,
        address[] memory _connectedOfts
    ) public /* simulateAndWriteTxs(_connectedConfig) */ broadcastAs(configDeployerPK) {
        setEvmEnforcedOptions({
            _connectedOfts: _connectedOfts,
            _configs: broadcastConfigArray
        });

        // setEvmPeers({
        //     _connectedOfts: _connectedOfts,
        //     _peerOfts: proxyOfts,
        //     _configs: broadcastConfigArray
        // });
        setPeer({
            _config: broadcastConfig,
            _connectedOft: _connectedOfts[0],
            _peerOftAsBytes32: bytes32(uint256(uint160(_connectedOfts[0])))
        });

        setDVNs({
            _connectedConfig: broadcastConfig,
            _connectedOfts: _connectedOfts,
            _configs: broadcastConfigArray
        });
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
        for (uint256 c=0; c<_configs.length; c++) {            
            // cannot set enforced options to self
            // if (block.chainid == _configs[c].chainid) continue;

            enforcedOptionParams.push(EnforcedOptionParam(uint32(_configs[c].eid), 1, _optionsTypeOne));
            enforcedOptionParams.push(EnforcedOptionParam(uint32(_configs[c].eid), 2, _optionsTypeTwo));
        }

        for (uint256 o=0; o<_connectedOfts.length; o++) {
            setEnforcedOption({
                _connectedOft: _connectedOfts[o]
            });
        }
    }

    function setPeer(
        L0Config memory _config,
        address _connectedOft,
        bytes32 _peerOftAsBytes32
    ) public override {
        // cannot set peer to self
        // if (block.chainid == _config.chainid) return;

        bytes memory data = abi.encodeCall(
            IOAppCore.setPeer,
            (
                uint32(_config.eid), _peerOftAsBytes32
            )
        );
        (bool success, ) = _connectedOft.call(data);
        require(success, "Unable to setPeer");
        serializedTxs.push(
            SerializedTx({
                name: "setPeer",
                to: _connectedOft,
                value: 0,
                data: data
            })
        );
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
        for (uint256 c=0; c<_configs.length; c++) {
            // cannot set enforced options to self
            // if (block.chainid == _configs[c].chainid) continue;

            setConfigParams.push(
                SetConfigParam({
                    eid: uint32(_configs[c].eid),
                    configType: Constant.CONFIG_TYPE_ULN,
                    config: abi.encode(ulnConfig)                    
                })
            );
        }

        // Submit txs to set DVN
        for (uint256 o=0; o<_connectedOfts.length; o++) {
            address endpoint = _connectedConfig.endpoint;
            
            // receiveLib
            bytes memory data = abi.encodeCall(
                IMessageLibManager.setConfig,
                (
                    _connectedOfts[o],
                    _connectedConfig.receiveLib302,
                    setConfigParams
                )
            );
            (bool success, ) = endpoint.call(data);
            require(success, "Unable to setConfig for receiveLib");
            serializedTxs.push(
                SerializedTx({
                    name: "setConfig for receiveLib",
                    to: endpoint,
                    value: 0,
                    data: data
                })
            );

            // sendLib
            data = abi.encodeCall(
                IMessageLibManager.setConfig,
                (
                    _connectedOfts[o],
                    _connectedConfig.sendLib302,
                    setConfigParams
                )
            );
            (success, ) = endpoint.call(data);
            require(success, "Unable to setConfig for sendLib");
            serializedTxs.push(
                SerializedTx({
                    name: "setConfig for sendLib",
                    to: endpoint,
                    value: 0,
                    data: data
                })
            );
        }
    }
}