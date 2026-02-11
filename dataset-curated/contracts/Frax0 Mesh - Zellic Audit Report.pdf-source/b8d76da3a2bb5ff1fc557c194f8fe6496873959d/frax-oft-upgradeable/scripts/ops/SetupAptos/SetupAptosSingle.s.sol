// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

// Used to setup a single destination to Aptos, for example Fraxtal <> Aptos
// forge script scripts/ops/SetupAptos/SetupAptosSingle.s.sol --rpc-url https://rpc.frax.com
contract SetupAptosSingle is DeployFraxOFTProtocol {

    L0Config[] public aptosConfigArray;
    using Strings for uint256;


    function filename() public view override returns (string memory) {
        string memory root = vm.projectRoot();
        root = string.concat(root, "/scripts/ops/SetupAptos/txs/");
        string memory name = string.concat(simulateConfig.chainid.toString(), ".json");

        return string.concat(root, name);
    }

    function run() public override {
        aptosConfigArray.push(nonEvmConfigs[2]);
        require(aptosConfigArray.length == 1, "Aptos config not added");
        require(aptosConfigArray[0].eid == 30108, "Not aptos config");

        setupAptosDestinations();
    }

    function _populateConnectedOfts() public override {
        // TODO: modify this readme to "Fraxtal Lockboxes"
        // https://github.com/FraxFinance/frax-oft-upgradeable?tab=readme-ov-file#fraxtal-standalone-frxusdsfrxusd-lockboxes
        connectedOfts[0] = fraxtalLockboxes[0];
        connectedOfts[1] = fraxtalLockboxes[1];
        connectedOfts[2] = fraxtalLockboxes[2];
        connectedOfts[3] = fraxtalLockboxes[3];
        connectedOfts[4] = fraxtalLockboxes[4];
        connectedOfts[5] = fraxtalLockboxes[5];
    }

    function setupAptosDestinations() public virtual {
        setupAptosDestination(broadcastConfig);
    }

    function setupAptosDestination(L0Config memory _simulateConfig) simulateAndWriteTxs(_simulateConfig) public {
        /// @dev connectedOfts are set in BaseL0Script.simulateAndWriteTxs()

        setAptosEnforcedOptions({
            _connectedOfts: connectedOfts
        });

        setAptosPeers({
            _connectedConfig: nonEvmConfigs[2], // maps to aptos
            _connectedOfts: connectedOfts
        });

        setDVNs({
            _connectedConfig: _simulateConfig,
            _connectedOfts: connectedOfts,
            _configs: aptosConfigArray
        });
    }

    function setAptosPeers(
        L0Config memory _connectedConfig,
        address[] memory _connectedOfts
    ) public {
        for (uint256 o=0; o<_connectedOfts.length; o++) {
            // aptos is nonEvmPeersArrays[1] from BaseL0Script.loadJsonConfig()
            setPeer({
                _config: _connectedConfig,
                _connectedOft: _connectedOfts[o],
                _peerOftAsBytes32: nonEvmPeersArrays[1][o]
            });
        }
    }
}