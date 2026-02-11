// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";
import "contracts/FraxOFTMintableUpgradeable.sol";
import { FraxOFTWalletUpgradeable } from "contracts/FraxOFTWalletUpgradeable.sol";

// fraxtal : forge script ./scripts/ops/FraxDVNTest/mainnet/1a_DeployMintableMockFrax.s.sol --rpc-url https://rpc.frax.com --verifier-url $FRAXSCAN_API_URL --etherscan-api-key $FRAXSCAN_API_KEY --verify --broadcast
// verify Implementation Mock : forge verify-contract 0x01c9C9aD9FCF0Be1Bb028A503DA27BaE1eEe8205 ./contracts/mocks/ImplementationMock.sol:ImplementationMock --chain-id 252 --watch --verifier etherscan --etherscan-api-key $FRAXSCAN_API_KEY --verifier-url $FRAXSCAN_API_URL
// verify FraxOFTMintableUpgradeable : forge verify-contract 0x7130176a1f87e29d2c4543f3bd3edc245ea6b70d ./contracts/FraxOFTMintableUpgradeable.sol:FraxOFTMintableUpgradeable --constructor-args $(cast abi-encode "constructor(address)" 0x1a44076050125825900e736c501f859c50fE728c)  --chain-id 252 --watch --verifier etherscan --etherscan-api-key $FRAXSCAN_API_KEY --verifier-url $FRAXSCAN_API_URL
// verify TransparentUpgradeableProxy : forge verify-contract 0x57558Cb8d6005DE0BAe8a2789d5EfaaE52dba5a8 ./node_modules/@fraxfinance/layerzero-v2-upgradeable/messagelib/contracts/upgradeable/proxy/TransparentUpgradeableProxy.sol:TransparentUpgradeableProxy --constructor-args $(cast abi-encode "constructor(address,address,bytes)" 0x01c9C9aD9FCF0Be1Bb028A503DA27BaE1eEe8205 0x45DCE8e4F2Dc005A5F28206A46cb034697eEDA8e 0x)  --chain-id 252 --watch --verifier etherscan --etherscan-api-key $FRAXSCAN_API_KEY --verifier-url $FRAXSCAN_API_URL
// verify FraxOFTWalletUpgradeable : forge verify-contract 0x5b9d960752963c92317b76adacfcc104f69f31a7 ./contracts/FraxOFTWalletUpgradeable.sol:FraxOFTWalletUpgradeable  --chain-id 252 --watch --verifier etherscan --etherscan-api-key $FRAXSCAN_API_KEY --verifier-url $FRAXSCAN_API_URL
// verify TransparentUpgradeableProxy : forge verify-contract 0x741F0d8Bde14140f62107FC60A0EE122B37D4630 ./node_modules/@fraxfinance/layerzero-v2-upgradeable/messagelib/contracts/upgradeable/proxy/TransparentUpgradeableProxy.sol:TransparentUpgradeableProxy --constructor-args $(cast abi-encode "constructor(address,address,bytes)" 0x01c9C9aD9FCF0Be1Bb028A503DA27BaE1eEe8205 0x45DCE8e4F2Dc005A5F28206A46cb034697eEDA8e 0x)  --chain-id 252 --watch --verifier etherscan --etherscan-api-key $FRAXSCAN_API_KEY --verifier-url $FRAXSCAN_API_URL

contract DeployMintableMockFrax is DeployFraxOFTProtocol {
    address[] public proxyOftWallets;

    address mFraxProxyAdmin = 0x8d8290d49e88D16d81C6aDf6C8774eD88762274A;

    function run() public override {
        deploySource();
    }

    function postDeployChecks() internal view override {
        require(proxyOfts.length == 1, "Did not deploy OFT");
        require(proxyOftWallets.length == 1, "Did not deploy OFT Wallet");
    }

    function deployFraxOFTUpgradeablesAndProxies() public override broadcastAs(oftDeployerPK) {
        // Implementation mock (0x8f1B9c1fd67136D525E14D96Efb3887a33f16250 if predeterministic)
        implementationMock = address(new ImplementationMock());

        // / @dev: follows deployment order of legacy OFTs found at https://etherscan.io/address/0xded884435f2db0169010b3c325e733df0038e51d
        // Deploy FRAX
        deployFraxOFTUpgradeableAndProxy({ _name: "Mock Frax", _symbol: "mFRAX" });

        // Deploy OFT Wallet
        deployFraxOFTWalletUpgradeableAndProxy();
    }

    /// @notice Sourced from https://github.com/FraxFinance/LayerZero-v2-upgradeable/blob/e1470197e0cffe0d89dd9c776762c8fdcfc1e160/oapp/test/TestHelper.sol#L266
    ///     With state checks
    function deployFraxOFTUpgradeableAndProxy(
        string memory _name,
        string memory _symbol
    ) public override returns (address implementation, address proxy) {
        proxyAdmin = mFraxProxyAdmin;

        implementation = address(new FraxOFTMintableUpgradeable(broadcastConfig.endpoint));
        /// @dev: create semi-pre-deterministic proxy address, then initialize with correct implementation
        proxy = address(new TransparentUpgradeableProxy(implementationMock, vm.addr(oftDeployerPK), ""));
        /// @dev: broadcastConfig deployer is temporary OFT owner until setPriviledgedRoles()
        bytes memory initializeArgs = abi.encodeWithSelector(
            FraxOFTUpgradeable.initialize.selector,
            _name,
            _symbol,
            vm.addr(configDeployerPK)
        );
        TransparentUpgradeableProxy(payable(proxy)).upgradeToAndCall({
            newImplementation: implementation,
            data: initializeArgs
        });
        TransparentUpgradeableProxy(payable(proxy)).changeAdmin(proxyAdmin);

        proxyOfts.push(proxy);

        // State checks
        require(isStringEqual(FraxOFTMintableUpgradeable(proxy).name(), _name), "OFT name incorrect");
        require(isStringEqual(FraxOFTMintableUpgradeable(proxy).symbol(), _symbol), "OFT symbol incorrect");
        require(
            address(FraxOFTMintableUpgradeable(proxy).endpoint()) == broadcastConfig.endpoint,
            "OFT endpoint incorrect"
        );
        require(
            EndpointV2(broadcastConfig.endpoint).delegates(proxy) == vm.addr(configDeployerPK),
            "Endpoint delegate incorrect"
        );
        require(FraxOFTMintableUpgradeable(proxy).owner() == vm.addr(configDeployerPK), "OFT owner incorrect");
    }

    function deployFraxOFTWalletUpgradeableAndProxy() public returns (address implementation, address proxy) {
        proxyAdmin = mFraxProxyAdmin;

        implementation = address(new FraxOFTWalletUpgradeable());
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
