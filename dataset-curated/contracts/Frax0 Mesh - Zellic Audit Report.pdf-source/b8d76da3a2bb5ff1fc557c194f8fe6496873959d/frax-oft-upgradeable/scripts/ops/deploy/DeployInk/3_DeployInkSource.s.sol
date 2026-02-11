// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";

// Resume Ink deployment by setting config
// forge script scripts/DeployInk/3_DeployInkSource.s.sol --rpc-url https://rpc-gel.inkonchain.com
contract DeployInkSource is DeployFraxOFTProtocol {

    function run() public override {

        // deploySource();

        // since ofts are already deployed, manually populate the addresses for setup
        proxyOfts.push(expectedProxyOfts[0]);
        proxyOfts.push(expectedProxyOfts[1]);
        proxyOfts.push(expectedProxyOfts[2]);
        proxyOfts.push(expectedProxyOfts[3]);
        proxyOfts.push(expectedProxyOfts[4]);
        proxyOfts.push(expectedProxyOfts[5]);

        // manually set proxyAdmin as it is deployed in source
        proxyAdmin = 0x223a681fc5c5522c85C96157c0efA18cd6c5405c;

        setupSource();
        // setupDestinations();
    }
}