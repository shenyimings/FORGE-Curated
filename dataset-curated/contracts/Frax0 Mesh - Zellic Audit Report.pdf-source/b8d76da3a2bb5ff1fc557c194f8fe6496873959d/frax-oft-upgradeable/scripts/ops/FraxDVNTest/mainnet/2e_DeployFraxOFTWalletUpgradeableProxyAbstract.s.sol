// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";
import "contracts/FraxOFTMintableUpgradeable.sol";
import { FraxOFTWalletUpgradeable } from "contracts/FraxOFTWalletUpgradeable.sol";

// abstract : forge script ./scripts/ops/FraxDVNTest/mainnet/2e_DeployFraxOFTWalletUpgradeableProxyAbstract.s.sol --rpc-url https://api.mainnet.abs.xyz --zksync --verifier-url $ABSTRACT_ETHERSCAN_API_URL --etherscan-api-key $ABSTRACT_ETHERSCAN_API_KEY --verifier etherscan --verify --broadcast

contract DeployMockFrax is DeployFraxOFTProtocol {
    address[] public proxyOftWallets;
    address mFraxProxyAdmin = 0x8d8290d49e88D16d81C6aDf6C8774eD88762274A;

    function run() public override {
        deploySource();
    }

    function postDeployChecks() internal view override {
        require(proxyOftWallets.length == 1, "Did not deploy OFT Wallet");
    }

    function deployFraxOFTUpgradeablesAndProxies() public override broadcastAs(oftDeployerPK) {
        // Implementation mock (0x8f1B9c1fd67136D525E14D96Efb3887a33f16250 if predeterministic)
        implementationMock = 0x0AC30D5aAA765fb0BA5629C1e2BC9f7a0BBFfAe6;

        // Deploy OFT Wallet
        deployFraxOFTWalletUpgradeableAndProxy();
    }

    function deployFraxOFTWalletUpgradeableAndProxy() public returns (address implementation, address proxy) {
        proxyAdmin = mFraxProxyAdmin;

        implementation = 0x54b3421704a12022040F98EC192bff8dF9Ef91bB;
        /// @dev: create semi-pre-deterministic proxy address, then initialize with correct implementation
        proxy = address(new TransparentUpgradeableProxy(implementationMock, vm.addr(oftDeployerPK), ""));
        /// @dev: broadcastConfig deployer is temporary owner until setPriviledgedRoles()
        bytes memory initializeArgs = abi.encodeWithSelector(
            FraxOFTWalletUpgradeable.initialize.selector,
            vm.addr(configDeployerPK)
        );
        TransparentUpgradeableProxy(payable(proxy)).upgradeToAndCall({
            newImplementation: implementation,
            data: initializeArgs
        });
        TransparentUpgradeableProxy(payable(proxy)).changeAdmin(proxyAdmin);

        proxyOftWallets.push(proxy);
    }
}
