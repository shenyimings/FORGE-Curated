// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";

// Deploy everything with a hub model vs. a spoke model where the only peer is Fraxtal
// forge script scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocolFraxtalHub.s.sol --rpc-url $RPC_URL --broadcast
contract DeployFraxOFTProtocolFraxtalHub is DeployFraxOFTProtocol {
    L0Config[] public tempConfigs;

    function run() public override {
        for (uint256 i=0; i<proxyConfigs.length; i++) {
            // Set up destinations for Fraxtal lockboxes only
            if (
                proxyConfigs[i].chainid == 252 ||
                proxyConfigs[i].chainid == broadcastConfig.chainid
            ) {
                tempConfigs.push(proxyConfigs[i]);
            }
        }

        require(tempConfigs.length == 2, "Incorrect tempConfigs array");

        delete proxyConfigs;
        for (uint256 i=0; i<tempConfigs.length; i++) {
            proxyConfigs.push(tempConfigs[i]);
        }
        delete tempConfigs;

        super.run();
    }

    function setupNonEvms() public override {}

    function preDeployChecks() public override view {
        for (uint256 i=0; i<proxyConfigs.length; i++) {
            uint32 eid = uint32(proxyConfigs[i].eid);
            require(
                IMessageLibManager(broadcastConfig.endpoint).isSupportedEid(eid),
                "L0 team required to setup `defaultSendLibrary` and `defaultReceiveLibrary` for EID"
            );   
        }
    }

    function setupSource() public override broadcastAs(configDeployerPK) {
        /// @dev set enforced options / peers separately
        setupEvms();
        setupNonEvms();

        setDVNs({
            _connectedConfig: broadcastConfig,
            _connectedOfts: proxyOfts,
            _configs: proxyConfigs
        });

        setLibs({
            _connectedConfig: broadcastConfig,
            _connectedOfts: proxyOfts,
            _configs: proxyConfigs
        });

        setPriviledgedRoles();
    }

}
