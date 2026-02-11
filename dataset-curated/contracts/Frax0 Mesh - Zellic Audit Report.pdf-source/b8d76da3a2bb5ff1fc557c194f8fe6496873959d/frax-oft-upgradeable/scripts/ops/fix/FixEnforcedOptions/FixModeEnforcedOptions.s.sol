// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";

// Configure mode enforced options
// forge script scripts/ops/fix/FixEnforcedOptions/FixModeEnforcedOptions.s.sol --rpc-url https://mainnet.mode.network/
contract FixModeEnforcedOptions is DeployFraxOFTProtocol {

    function filename() public view override returns (string memory) {
        string memory root = vm.projectRoot();
        string memory name = string.concat(root, "/scripts/ops/fix/FixEnforcedOptions/txs/FixModeEnforcedOptions.json");
        return name;
    }

    function run() public override simulateAndWriteTxs(broadcastConfig) {
        setEvmEnforcedOptions({
            _connectedOfts: expectedProxyOfts,
            _configs: evmConfigs
        });
    }
}