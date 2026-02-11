// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";


/*
struct UlnConfig {
    uint64 confirmations;
    // we store the length of required DVNs and optional DVNs instead of using DVN.length directly to save gas
    uint8 requiredDVNCount; // 0 indicate DEFAULT, NIL_DVN_COUNT indicate NONE (to override the value of default)
    uint8 optionalDVNCount; // 0 indicate DEFAULT, NIL_DVN_COUNT indicate NONE (to override the value of default)
    uint8 optionalDVNThreshold; // (0, optionalDVNCount]
    address[] requiredDVNs; // no duplicates. sorted an an ascending order. allowed overlap with optionalDVNs
    address[] optionalDVNs; // no duplicates. sorted an an ascending order. allowed overlap with requiredDVNs
}
*/

// forge script scripts/ops/UpgradeDVNs/UpgradeDVNs.s.sol --rpc-url https://rpc.frax.com
contract UpgradeDVNs is DeployFraxOFTProtocol {

    using Strings for uint256;
    using stdJson for string;

    // used in getDvnStack to craft the memory array
    L0Config dstConfig;

    function filename() public view override returns (string memory) {
        string memory root = vm.projectRoot();
        root = string.concat(root, "/scripts/ops/UpgradeDVNs/txs/");

        string memory name = string.concat(simulateConfig.chainid.toString(), "-");
        name = string.concat(name, dstConfig.chainid.toString());
        name = string.concat(name, ".json");
        return string.concat(root, name);
    }

    function run() public override {
        /// @dev to skip checks
        proxyOfts = new address[](6);

        setAllConfigs({
            _srcConfig: broadcastConfig,
            _dstConfigs: proxyConfigs
        });
    }

    function setAllConfigs(
        L0Config memory _srcConfig,
        L0Config[] memory _dstConfigs
    ) public {
        // loop through ofts
        for (uint256 d=0; d<_dstConfigs.length; d++) {
            dstConfig = _dstConfigs[d];

            // cannot set dvn options to self
            if (_srcConfig.chainid == dstConfig.chainid) continue;

            setConfigs({
                _srcConfig: _srcConfig,
                _dstConfig: dstConfig
            });
        }
    }

    function setConfigs(
        L0Config memory _srcConfig,
        L0Config memory _dstConfig
    ) public virtual simulateAndWriteTxs(_srcConfig) {
        for (uint256 o=0; o<connectedOfts.length; o++) {
            address oft = connectedOfts[o];

            setConfig({
                _srcConfig: _srcConfig,
                _dstConfig: _dstConfig,
                _lib: _srcConfig.sendLib302,
                _oft: oft
            });

            setConfig({
                _srcConfig: _srcConfig,
                _dstConfig: _dstConfig,
                _lib: _srcConfig.receiveLib302,
                _oft: oft
            });
        }
    }

}