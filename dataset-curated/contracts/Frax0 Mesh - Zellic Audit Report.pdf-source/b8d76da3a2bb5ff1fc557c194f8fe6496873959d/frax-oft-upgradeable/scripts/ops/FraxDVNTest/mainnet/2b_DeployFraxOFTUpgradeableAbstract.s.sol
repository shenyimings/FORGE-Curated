// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";
import "contracts/FraxOFTMintableUpgradeable.sol";
import { FraxOFTWalletUpgradeable } from "contracts/FraxOFTWalletUpgradeable.sol";

// abstract : forge script ./scripts/ops/FraxDVNTest/mainnet/2b_DeployFraxOFTUpgradeable.s.sol --rpc-url https://api.mainnet.abs.xyz --zksync --verifier-url $ABSTRACT_ETHERSCAN_API_URL --etherscan-api-key $ABSTRACT_ETHERSCAN_API_KEY --verifier etherscan --verify --broadcast

contract deployFraxOFTUpgradeableAbstract is DeployFraxOFTProtocol {
    address[] public proxyOftWallets;
    address mFraxProxyAdmin = 0x8d8290d49e88D16d81C6aDf6C8774eD88762274A;

    function run() public override {
        deploySource();
    }

    function postDeployChecks() internal view override {}

    function deployFraxOFTUpgradeablesAndProxies() public override broadcastAs(oftDeployerPK) {
        // / @dev: follows deployment order of legacy OFTs found at https://etherscan.io/address/0xded884435f2db0169010b3c325e733df0038e51d
        // Deploy FRAX
        deployFraxOFTUpgradeableAndProxy("Mock Frax", "mFRAX");
    }

    /// @notice Sourced from https://github.com/FraxFinance/LayerZero-v2-upgradeable/blob/e1470197e0cffe0d89dd9c776762c8fdcfc1e160/oapp/test/TestHelper.sol#L266
    ///     With state checks
    function deployFraxOFTUpgradeableAndProxy(
        string memory,
        string memory
    ) public override returns (address implementation, address) {
        proxyAdmin = mFraxProxyAdmin;

        implementation = address(new FraxOFTUpgradeable(broadcastConfig.endpoint));
    }
}
