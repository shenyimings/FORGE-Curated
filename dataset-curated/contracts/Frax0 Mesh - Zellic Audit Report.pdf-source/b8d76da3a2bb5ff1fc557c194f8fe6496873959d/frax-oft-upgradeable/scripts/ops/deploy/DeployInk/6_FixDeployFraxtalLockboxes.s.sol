// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";
import { Constant } from "@fraxfinance/layerzero-v2-upgradeable/messagelib/test/util/Constant.sol";
import { UlnConfig } from "@fraxfinance/layerzero-v2-upgradeable/messagelib/contracts/uln/UlnBase.sol";

// Setup DVN for Sonic
// forge script scripts/DeployInk/6_FixDeployFraxtalLockboxes.s.sol --rpc-url https://rpc.frax.com
contract FixDeployFraxtalLockboxes is DeployFraxOFTProtocol {

    address[] public inkProxyOfts;
    SetConfigParam[] public setConfigParams;

    constructor() {
        inkProxyOfts.push(0x80Eede496655FB9047dd39d9f418d5483ED600df); // frxUsd
        inkProxyOfts.push(0x5Bff88cA1442c2496f7E475E9e7786383Bc070c0); // sfrxUsd
    }

    modifier simulateAndWriteTxs(
        L0Config memory _simulateConfig
    ) override {
        // Clear out any previous txs
        delete enforcedOptionParams;
        delete setConfigParams;
        delete serializedTxs;

        // store for later referencing
        simulateConfig = _simulateConfig;

        // Use the correct OFT addresses given the chain we're simulating
        _populateConnectedOfts();

        // Simulate fork as delegate (aka msig) as we're crafting txs within the modified function
        vm.createSelectFork(_simulateConfig.RPC);
        vm.startPrank(_simulateConfig.delegate);
        _;
        vm.stopPrank();

        // serialized txs may have been pushed within the decorated function- write to file
        if (serializedTxs.length > 0) {
            new SafeTxUtil().writeTxs(serializedTxs, filename());
        }
    }

    function filename() public view override returns (string memory) {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/scripts/ops/deploy/DeployInk/txs/FixLockboxDVNs.json");
        return path;
    }

    // customize setup to only set peers of the proxy frxUSD, sfrxUSD on ink
    function run() public override {
        proxyOfts.push(0x96A394058E2b84A89bac9667B19661Ed003cF5D4); // frxUSD lockbox
        proxyOfts.push(0x88Aa7854D3b2dAA5e37E7Ce73A1F39669623a361); // sfrxUSD lockbox

        // deploySource();
        setupSource();
        // setupDestinations();
    }

    // skip solana
    function setupSource() public override simulateAndWriteTxs(broadcastConfig) {
        /// @dev set enforced options / peers separately
        // setupEvms();
        // setupNonEvms();

        /// @dev configures legacy configs as well
        setDVNs({
            _connectedConfig: broadcastConfig,
            _connectedOfts: proxyOfts,
            _configs: allConfigs
        });

        setLibs({
            _connectedConfig: broadcastConfig,
            _connectedOfts: proxyOfts,
            _configs: allConfigs
        });

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
            if (block.chainid == _configs[c].chainid) continue;

            // Only set DVNs for sonic
            if (_configs[c].chainid != 146) continue;

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