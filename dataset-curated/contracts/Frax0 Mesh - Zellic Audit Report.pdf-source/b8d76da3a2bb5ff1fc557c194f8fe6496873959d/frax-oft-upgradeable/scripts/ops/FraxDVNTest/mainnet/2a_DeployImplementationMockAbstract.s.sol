// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";
import "contracts/FraxOFTMintableUpgradeable.sol";
import { FraxOFTWalletUpgradeable } from "contracts/FraxOFTWalletUpgradeable.sol";

// abstract : forge script ./scripts/ops/FraxDVNTest/mainnet/2a_DeployImplementationMockAbstract.s.sol --rpc-url https://api.mainnet.abs.xyz --zksync --verifier-url $ABSTRACT_ETHERSCAN_API_URL --etherscan-api-key $ABSTRACT_ETHERSCAN_API_KEY --verifier etherscan --verify --broadcast

contract DeployImplementationMockAbstract is DeployFraxOFTProtocol {
    address[] public proxyOftWallets;
    address mFraxProxyAdmin = 0x8d8290d49e88D16d81C6aDf6C8774eD88762274A;

    function run() public override {
        deploySource();
    }

    function postDeployChecks() internal view override {
    }

    function deployFraxOFTUpgradeablesAndProxies() public override broadcastAs(oftDeployerPK) {
        implementationMock = address(new ImplementationMock());
    }
}
