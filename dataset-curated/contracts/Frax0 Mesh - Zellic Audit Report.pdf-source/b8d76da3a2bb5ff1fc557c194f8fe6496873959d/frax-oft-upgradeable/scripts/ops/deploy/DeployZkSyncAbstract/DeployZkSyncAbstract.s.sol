// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";

// Wire fraxtal lockboxes to zksync and abstract
// forge script scripts/ops/deploy/DeployZkSyncAbstract/DeployZkSyncAbstract.s.sol --rpc-url https://rpc.frax.com
contract DeployZkSyncAbstract is DeployFraxOFTProtocol {

    L0Config[] public tempConfigs; 

    function filename() public view override returns (string memory) {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/scripts/ops/deploy/DeployZkSyncAbstract/txs/252.json");
        return path;
    }

    function setUp() public override {
        super.setUp();

        // set the ofts to the lockboxes so that `getPeerFromArray()` returns the correct peer
        frxUsdOft = fraxtalFrxUsdLockbox;
        sfrxUsdOft = fraxtalSFrxUsdLockbox;
        frxEthOft = fraxtalFrxEthLockbox;
        sfrxEthOft = fraxtalSFrxEthLockbox;
        wfraxOft = fraxtalFraxLockbox;
        fpiOft = fraxtalFpiLockbox;

        // populate proxyOfts to the fraxtal lockboxes in order of deployment
        proxyOfts.push(fraxtalFraxLockbox);
        proxyOfts.push(fraxtalSFrxUsdLockbox);
        proxyOfts.push(fraxtalSFrxEthLockbox);
        proxyOfts.push(fraxtalFrxUsdLockbox);
        proxyOfts.push(fraxtalFrxEthLockbox);
        proxyOfts.push(fraxtalFpiLockbox);

        // set proxyConfigs to only zksync / abstract 
        for (uint256 i=0; i<proxyConfigs.length; i++) {
            if (proxyConfigs[i].chainid == 2741 || proxyConfigs[i].chainid == 324) {
                tempConfigs.push(proxyConfigs[i]);
            }
        }
        require(tempConfigs.length == 2, "Incorrect temp configs");
        delete proxyConfigs;
        for (uint256 i=0; i<tempConfigs.length; i++) {
            proxyConfigs.push(tempConfigs[i]);
        }
        delete tempConfigs;
    }

    function run() public override {
        setupSource();
    }

    function setupSource() public override simulateAndWriteTxs(broadcastConfig) {
        setupEvms();

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
    }
}