// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";

// Configure fraxtal enforced options to sonic
// forge script scripts/ops/fix/FixFraxtalSonicEnforcedOptions/FixFraxtalSonicEnforcedOptions.s.sol --rpc-url https://rpc.frax.com
contract FixFraxtalSonicEnforcedOptions is DeployFraxOFTProtocol {

    L0Config[] sonicConfigAsArray;

    function filename() public view override returns (string memory) {
        string memory root = vm.projectRoot();
        string memory name = string.concat(root, "/scripts/ops/fix/FixFraxtalSonicEnforcedOptions/txs/FixFraxtalSonicEnforcedOptions.json");
        return name;
    }

    function run() public override simulateAndWriteTxs(broadcastConfig) {
        delete proxyOfts;
        proxyOfts.push(fraxtalFrxUsdLockbox);
        proxyOfts.push(fraxtalSFrxUsdLockbox);

        for (uint256 i=0; i<proxyConfigs.length; i++) {
            if (proxyConfigs[i].chainid == 146) {
                sonicConfigAsArray.push(proxyConfigs[i]);
            }
        }
        require(sonicConfigAsArray.length == 1, "Too many configs added");
        require(sonicConfigAsArray[0].eid == 30332, "Did not add sonic eid");

        setEvmEnforcedOptions({
            _connectedOfts: proxyOfts,
            _configs: sonicConfigAsArray
        });
    }
}