// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";
import "contracts/FraxOFTAdapterUpgradeable.sol";

/*
GOALS
- Deploy (s)frxUSD lockboxes on Ethereum
- Connect to the standalone (s)frxUSD fraxtal lockboxes
- Connect to the proxy OFTs

TODO
- Connect to Solana OFTs
*/

// forge script scripts/ops/deploy/DeployFrxUsdEthereumLockboxes/DeployFrxUsdEthereumLockboxes.s.sol --rpc-url https://ethereum-rpc.publicnode.com
contract DeployFrxUsdEthereumLockboxes is DeployFraxOFTProtocol {

    using Strings for uint256;
    using stdJson for string;

    address frxUsd = 0xCAcd6fd266aF91b8AeD52aCCc382b4e165586E29;
    address sfrxUsd = 0xcf62F905562626CfcDD2261162a51fd02Fc9c5b6;

    function filename() public view override returns (string memory) {
        string memory root = vm.projectRoot();
        root = string.concat(root, "/scripts/ops/deploy/DeployFrxUsdEthereumLockboxes/txs/");

        string memory name = string.concat(broadcastConfig.chainid.toString(), "-");
        name = string.concat(name, simulateConfig.chainid.toString());
        name = string.concat(name, ".json");
        return string.concat(root, name);
    }

    function run() public override {
        // set expectedProxyOfts to [frxUsdOft, sfrxUsdOft]
        delete expectedProxyOfts;
        expectedProxyOfts.push(proxyFrxUsdOft);
        expectedProxyOfts.push(proxySFrxUsdOft);

        deploySource();
    }

    // Additional deployProxyAdmin to get 0x223 addr for proxyAdmin
    function deploySource() public override {
        preDeployChecks();
        deployProxyAdminAndImplementationMock();
        // postDeployChecks()
    }

    // deploy only the proxyAdmin and implementationMock from the predeterministic address 
    //  - maintains 0x223 for proxyAdmin (used for OFTs on other chains)
    //  - if we want to have later pre-deterministic proxies, we can.
    function deployProxyAdminAndImplementationMock() public broadcastAs(oftDeployerPK) {
                
        // Proxy admin (0x223a681fc5c5522c85C96157c0efA18cd6c5405c)
        proxyAdmin = address(new FraxProxyAdmin(vm.addr(configDeployerPK)));
        require(address(proxyAdmin) == 0x223a681fc5c5522c85C96157c0efA18cd6c5405c, "Unexpected ProxyAdmin address");

        // Implementation mock (0x8f1B9c1fd67136D525E14D96Efb3887a33f16250)
        implementationMock = address(new ImplementationMock());
        require(implementationMock == 0x8f1B9c1fd67136D525E14D96Efb3887a33f16250, "Unexpected ImplementationMock address");
    }
}