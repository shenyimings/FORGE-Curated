// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

// Used to setup a single destination to Movement, for example Fraxtal <> Movement
// forge script scripts/ops/SetupMovement/SetupMovementSingle.s.sol --rpc-url https://rpc.frax.com
contract SetupMovementSingle is DeployFraxOFTProtocol {

    L0Config[] public movementConfigArray;
    using Strings for uint256;


    function filename() public view override returns (string memory) {
        string memory root = vm.projectRoot();
        root = string.concat(root, "/scripts/ops/SetupMovement/txs/");
        string memory name = string.concat(simulateConfig.chainid.toString(), ".json");

        return string.concat(root, name);
    }

    function run() public override {
        movementConfigArray.push(nonEvmConfigs[1]);
        require(movementConfigArray.length == 1, "Movement config not added");
        require(movementConfigArray[0].eid == 30325, "Not movement config");

        setupMovementDestinations();
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

    function setupMovementDestinations() public virtual {
        setupMovementDestination(broadcastConfig);
    }

    function setupMovementDestination(L0Config memory _simulateConfig) simulateAndWriteTxs(_simulateConfig) public {
        /// @dev connectedOfts are set in BaseL0Script.simulateAndWriteTxs()
        setMovementEnforcedOptions({
            _connectedOfts: connectedOfts
        });

        setMovementPeers({
            _connectedConfig: nonEvmConfigs[1],// maps to movement
            _connectedOfts: connectedOfts
        });

        setDVNs({
            _connectedConfig: _simulateConfig,
            _connectedOfts: connectedOfts,
            _configs: movementConfigArray
        });
    }

    function setMovementPeers(
        L0Config memory _connectedConfig,
        address[] memory _connectedOfts
    ) public {
        for (uint256 o=0; o<_connectedOfts.length; o++) {
            // movement is nonEvmPeersArrays[1] from BaseL0Script.loadJsonConfig()
            setPeer({
                _config: _connectedConfig,
                _connectedOft: _connectedOfts[o],
                _peerOftAsBytes32: nonEvmPeersArrays[1][o]
            });
        }
    }
}