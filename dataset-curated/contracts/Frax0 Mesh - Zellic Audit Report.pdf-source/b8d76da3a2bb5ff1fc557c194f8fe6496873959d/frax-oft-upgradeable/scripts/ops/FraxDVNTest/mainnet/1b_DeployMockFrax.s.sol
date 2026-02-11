// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";
import "contracts/FraxOFTMintableUpgradeable.sol";
import { FraxOFTWalletUpgradeable } from "contracts/FraxOFTWalletUpgradeable.sol";

// ethereum : forge script ./scripts/ops/FraxDVNTest/mainnet/1b_DeployMockFrax.s.sol --rpc-url https://ethereum-rpc.publicnode.com --etherscan-api-key $ETHERSCAN_API_KEY --verifier etherscan --verify --broadcast
// blast : forge script ./scripts/ops/FraxDVNTest/mainnet/1b_DeployMockFrax.s.sol --rpc-url https://rpc.blast.io  --verifier-url $BLASTSCAN_API_URL --etherscan-api-key $BLASTSCAN_API_KEY --verifier etherscan --verify --broadcast
// base : forge script ./scripts/ops/FraxDVNTest/mainnet/1b_DeployMockFrax.s.sol --rpc-url https://mainnet.base.org  --verifier-url $BASESCAN_API_URL --etherscan-api-key $BASESCAN_API_KEY --verifier etherscan --verify --broadcast
// mode : forge script ./scripts/ops/FraxDVNTest/mainnet/1b_DeployMockFrax.s.sol --rpc-url https://mainnet.mode.network/ --verifier-url $MODE_ROUTESCAN_API_URL --etherscan-api-key $MODE_ROUTESCAN_API_KEY --verify --broadcast
// mode : verify implementation Mock : forge verify-contract 0x01c9C9aD9FCF0Be1Bb028A503DA27BaE1eEe8205 ./contracts/mocks/ImplementationMock.sol:ImplementationMock --chain-id 34443 --watch  --verifier-url $MODE_BLOCKSCOUT_API_URL --verifier blockscout
// mode : verify FraxOFTUpgradeable : forge verify-contract 0x7130176a1f87e29d2c4543f3bd3edc245ea6b70d ./contracts/FraxOFTUpgradeable.sol:FraxOFTUpgradeable --constructor-args $(cast abi-encode "constructor(address)" 0x1a44076050125825900e736c501f859c50fE728c)  --chain-id 34443 --watch --verifier blockscout --verifier-url $MODE_BLOCKSCOUT_API_URL
// mode : verify TransparentUpgradeableProxy : forge verify-contract 0x57558Cb8d6005DE0BAe8a2789d5EfaaE52dba5a8 ./node_modules/@fraxfinance/layerzero-v2-upgradeable/messagelib/contracts/upgradeable/proxy/TransparentUpgradeableProxy.sol:TransparentUpgradeableProxy --constructor-args $(cast abi-encode "constructor(address,address,bytes)" 0x01c9C9aD9FCF0Be1Bb028A503DA27BaE1eEe8205 0x45DCE8e4F2Dc005A5F28206A46cb034697eEDA8e 0x)  --chain-id 34443 --watch --verifier blockscout --verifier-url $MODE_BLOCKSCOUT_API_URL
// mode : verify FraxOFTWalletUpgradeable : forge verify-contract 0x5b9d960752963c92317b76adacfcc104f69f31a7 ./contracts/FraxOFTWalletUpgradeable.sol:FraxOFTWalletUpgradeable  --chain-id 34443 --watch --verifier blockscout --verifier-url $MODE_BLOCKSCOUT_API_URL
// mode : verify TransparentUpgradeable : forge verify-contract 0x741F0d8Bde14140f62107FC60A0EE122B37D4630 ./node_modules/@fraxfinance/layerzero-v2-upgradeable/messagelib/contracts/upgradeable/proxy/TransparentUpgradeableProxy.sol:TransparentUpgradeableProxy --constructor-args $(cast abi-encode "constructor(address,address,bytes)" 0x01c9C9aD9FCF0Be1Bb028A503DA27BaE1eEe8205 0x45DCE8e4F2Dc005A5F28206A46cb034697eEDA8e 0x)  --chain-id 34443 --watch --verifier blockscout --verifier-url $MODE_BLOCKSCOUT_API_URL
// sei : forge script ./scripts/ops/FraxDVNTest/mainnet/1b_DeployMockFrax.s.sol --rpc-url https://evm-rpc.sei-apis.com  --verifier-url $SEI_SEITRACE_API_URL --etherscan-api-key $SEI_SEITRACE_API_KEY --verifier blockscout --verify --broadcast
// sei : verify implementation Mock : forge verify-contract 0x01c9C9aD9FCF0Be1Bb028A503DA27BaE1eEe8205 ./contracts/mocks/ImplementationMock.sol:ImplementationMock --chain-id 1329 --watch  --verifier-url $SEI_SEITRACE_API_URL --verifier-api-key $SEI_SEITRACE_API_KEY  --verifier custom
// sei : verify FraxOFTUpgradeable : forge verify-contract 0x7130176a1f87e29d2c4543f3bd3edc245ea6b70d ./contracts/FraxOFTUpgradeable.sol:FraxOFTUpgradeable --constructor-args $(cast abi-encode "constructor(address)" 0x1a44076050125825900e736c501f859c50fE728c) --chain-id 1329 --watch  --verifier-url $SEI_SEITRACE_API_URL --verifier-api-key $SEI_SEITRACE_API_KEY  --verifier custom
// sei : verify TransparentUpgradeableProxy : forge verify-contract 0x57558Cb8d6005DE0BAe8a2789d5EfaaE52dba5a8 ./node_modules/@fraxfinance/layerzero-v2-upgradeable/messagelib/contracts/upgradeable/proxy/TransparentUpgradeableProxy.sol:TransparentUpgradeableProxy --constructor-args $(cast abi-encode "constructor(address,address,bytes)" 0x01c9C9aD9FCF0Be1Bb028A503DA27BaE1eEe8205 0x45DCE8e4F2Dc005A5F28206A46cb034697eEDA8e 0x)  --chain-id 1329 --watch  --verifier-url $SEI_SEITRACE_API_URL --verifier-api-key $SEI_SEITRACE_API_KEY  --verifier custom
// sei : verify FraxOFTWalletUpgradeable : forge verify-contract 0x5b9d960752963c92317b76adacfcc104f69f31a7 ./contracts/FraxOFTWalletUpgradeable.sol:FraxOFTWalletUpgradeable  --chain-id 1329 --watch  --verifier-url $SEI_SEITRACE_API_URL --verifier-api-key $SEI_SEITRACE_API_KEY  --verifier custom
// sei : verify TransparentUpgradeable : forge verify-contract 0x741F0d8Bde14140f62107FC60A0EE122B37D4630 ./node_modules/@fraxfinance/layerzero-v2-upgradeable/messagelib/contracts/upgradeable/proxy/TransparentUpgradeableProxy.sol:TransparentUpgradeableProxy --constructor-args $(cast abi-encode "constructor(address,address,bytes)" 0x01c9C9aD9FCF0Be1Bb028A503DA27BaE1eEe8205 0x45DCE8e4F2Dc005A5F28206A46cb034697eEDA8e 0x)  --chain-id 1329 --watch  --verifier-url $SEI_SEITRACE_API_URL --verifier-api-key $SEI_SEITRACE_API_KEY  --verifier custom
// TODO : pending verification , xlayer : forge script ./scripts/ops/FraxDVNTest/mainnet/1b_DeployMockFrax.s.sol --rpc-url https://xlayerrpc.okx.com/ --legacy --broadcast
// sonic : forge script ./scripts/ops/FraxDVNTest/mainnet/1b_DeployMockFrax.s.sol --rpc-url https://rpc.soniclabs.com/ --verifier-url $SONICSCAN_API_URL --etherscan-api-key $SONICSCAN_API_KEY --verifier etherscan --verify  --broadcast
// ink : forge script ./scripts/ops/FraxDVNTest/mainnet/1b_DeployMockFrax.s.sol --rpc-url https://rpc-gel.inkonchain.com --verifier-url $INK_BLOCKSCOUT_API_URL --verifier blockscout --verify --broadcast
// arbitrum : forge script ./scripts/ops/FraxDVNTest/mainnet/1b_DeployMockFrax.s.sol --rpc-url https://arb1.arbitrum.io/rpc --verifier-url $ARBISCAN_API_URL --etherscan-api-key $ARBISCAN_API_KEY --verifier etherscan --verify --broadcast
// optimism : forge script ./scripts/ops/FraxDVNTest/mainnet/1b_DeployMockFrax.s.sol --rpc-url https://optimism-mainnet.public.blastapi.io --verifier-url $OPTIMISTIC_ETHERSCAN_API_URL --etherscan-api-key $OPTIMISTIC_ETHERSCAN_API_KEY --verifier etherscan --verify --broadcast
// polygon : forge script ./scripts/ops/FraxDVNTest/mainnet/1b_DeployMockFrax.s.sol --rpc-url https://polygon-rpc.com --verifier-url $POLYGONSCAN_API_URL --etherscan-api-key $POLYGONSCAN_API_KEY --verifier etherscan --verify --broadcast
// avalanche : forge script ./scripts/ops/FraxDVNTest/mainnet/1b_DeployMockFrax.s.sol --rpc-url https://api.avax.network/ext/bc/C/rpc --verifier-url $SNOWSCAN_API_URL --etherscan-api-key $SNOWSCAN_API_KEY --verifier etherscan --verify --broadcast
// bsc : forge script ./scripts/ops/FraxDVNTest/mainnet/1b_DeployMockFrax.s.sol --rpc-url https://neat-lingering-orb.bsc.quiknode.pro/a9e1547db6f8261bf94f92603eec0cc3d0c66605 --verifier-url $BSCSCAN_API_URL --etherscan-api-key $BSCSCAN_API_KEY --verifier etherscan --verify --broadcast
// bsc : verify implementation Mock : forge verify-contract 0x01c9C9aD9FCF0Be1Bb028A503DA27BaE1eEe8205 ./contracts/mocks/ImplementationMock.sol:ImplementationMock --chain-id 56 --watch  --verifier-url $BSCSCAN_API_URL --verifier etherscan --etherscan-api-key $BSCSCAN_API_KEY
// bsc : verify FraxOFTUpgradeable : forge verify-contract 0x7130176a1f87e29d2c4543f3bd3edc245ea6b70d ./contracts/FraxOFTUpgradeable.sol:FraxOFTUpgradeable --constructor-args $(cast abi-encode "constructor(address)" 0x1a44076050125825900e736c501f859c50fE728c)  --chain-id 56 --watch --verifier etherscan --verifier-url $BSCSCAN_API_URL --etherscan-api-key $BSCSCAN_API_KEY
// bsc : verify TransparentUpgradeableProxy : forge verify-contract 0x57558Cb8d6005DE0BAe8a2789d5EfaaE52dba5a8 ./node_modules/@fraxfinance/layerzero-v2-upgradeable/messagelib/contracts/upgradeable/proxy/TransparentUpgradeableProxy.sol:TransparentUpgradeableProxy --constructor-args $(cast abi-encode "constructor(address,address,bytes)" 0x01c9C9aD9FCF0Be1Bb028A503DA27BaE1eEe8205 0x45DCE8e4F2Dc005A5F28206A46cb034697eEDA8e 0x)  --chain-id 56 --watch --verifier etherscan --verifier-url $BSCSCAN_API_URL --etherscan-api-key $BSCSCAN_API_KEY
// bsc : verify FraxOFTWalletUpgradeable : forge verify-contract 0x5b9d960752963c92317b76adacfcc104f69f31a7 ./contracts/FraxOFTWalletUpgradeable.sol:FraxOFTWalletUpgradeable  --chain-id 56 --watch --verifier etherscan --verifier-url $BSCSCAN_API_URL --etherscan-api-key $BSCSCAN_API_KEY
// bsc : verify TransparentUpgradeable : forge verify-contract 0x741F0d8Bde14140f62107FC60A0EE122B37D4630 ./node_modules/@fraxfinance/layerzero-v2-upgradeable/messagelib/contracts/upgradeable/proxy/TransparentUpgradeableProxy.sol:TransparentUpgradeableProxy --constructor-args $(cast abi-encode "constructor(address,address,bytes)" 0x01c9C9aD9FCF0Be1Bb028A503DA27BaE1eEe8205 0x45DCE8e4F2Dc005A5F28206A46cb034697eEDA8e 0x)  --chain-id 56 --watch --verifier etherscan --verifier-url $BSCSCAN_API_URL --etherscan-api-key $BSCSCAN_API_KEY
// zkpolygon : forge script ./scripts/ops/FraxDVNTest/mainnet/1b_DeployMockFrax.s.sol --rpc-url https://polygon-zkevm-mainnet.public.blastapi.io --verifier-url $ZK_POLYGONSCAN_API_URL --etherscan-api-key $ZK_POLYGONSCAN_API_KEY --verifier etherscan --verify --broadcast
// berachain : forge script ./scripts/ops/FraxDVNTest/mainnet/1b_DeployMockFrax.s.sol --rpc-url https://rpc.berachain.com --verifier-url $BERASCAN_API_URL --etherscan-api-key $BERASCAN_API_KEY --verifier etherscan --verify --broadcast
// linea : forge script ./scripts/ops/FraxDVNTest/mainnet/1b_DeployMockFrax.s.sol --rpc-url https://rpc.linea.build --verifier-url $LINEASCAN_API_URL --etherscan-api-key $LINEASCAN_API_KEY --verifier etherscan --verify --broadcast --evm-version paris
// zksync : forge script ./scripts/ops/FraxDVNTest/mainnet/1b_DeployMockFrax.s.sol --rpc-url https://mainnet.era.zksync.io --zksync --verifier-url $ZKSYNC_ERA_ETHERSCAN_API_URL --etherscan-api-key $ZKSYNC_ERA_ETHERSCAN_API_KEY --verifier etherscan --verify --broadcast
// worldchain : forge script ./scripts/ops/FraxDVNTest/mainnet/1b_DeployMockFrax.s.sol --rpc-url https://worldchain-mainnet.g.alchemy.com/public --verifier-url $WORLDSCAN_API_URL --etherscan-api-key $WORLDSCAN_API_KEY --verifier etherscan --verify --broadcast
// unichain : forge script ./scripts/ops/FraxDVNTest/mainnet/1b_DeployMockFrax.s.sol --rpc-url https://unichain.drpc.org --verifier-url $UNISCAN_API_URL --etherscan-api-key $UNISCAN_API_KEY --verifier etherscan --verify --broadcast
// unichain : verify implementation Mock : forge verify-contract 0x01c9C9aD9FCF0Be1Bb028A503DA27BaE1eEe8205 ./contracts/mocks/ImplementationMock.sol:ImplementationMock --chain-id 130 --watch  --etherscan-api-key $UNISCAN_API_KEY --verifier etherscan
// unichain : verify FraxOFTUpgradeable : forge verify-contract 0x7130176a1f87e29d2c4543f3bd3edc245ea6b70d ./contracts/FraxOFTUpgradeable.sol:FraxOFTUpgradeable --constructor-args $(cast abi-encode "constructor(address)" 0x1a44076050125825900e736c501f859c50fE728c)  --chain-id 130 --watch --verifier etherscan --etherscan-api-key $UNISCAN_API_KEY
// unichain : verify TransparentUpgradeableProxy : forge verify-contract 0x57558Cb8d6005DE0BAe8a2789d5EfaaE52dba5a8 ./node_modules/@fraxfinance/layerzero-v2-upgradeable/messagelib/contracts/upgradeable/proxy/TransparentUpgradeableProxy.sol:TransparentUpgradeableProxy --constructor-args $(cast abi-encode "constructor(address,address,bytes)" 0x01c9C9aD9FCF0Be1Bb028A503DA27BaE1eEe8205 0x45DCE8e4F2Dc005A5F28206A46cb034697eEDA8e 0x)  --chain-id 130 --watch --verifier etherscan --etherscan-api-key $UNISCAN_API_KEY
// unichain : verify FraxOFTWalletUpgradeable : forge verify-contract 0x5b9d960752963c92317b76adacfcc104f69f31a7 ./contracts/FraxOFTWalletUpgradeable.sol:FraxOFTWalletUpgradeable  --chain-id 130 --watch --verifier etherscan --etherscan-api-key $UNISCAN_API_KEY
// unichain : verify TransparentUpgradeable : forge verify-contract 0x741F0d8Bde14140f62107FC60A0EE122B37D4630 ./node_modules/@fraxfinance/layerzero-v2-upgradeable/messagelib/contracts/upgradeable/proxy/TransparentUpgradeableProxy.sol:TransparentUpgradeableProxy --constructor-args $(cast abi-encode "constructor(address,address,bytes)" 0x01c9C9aD9FCF0Be1Bb028A503DA27BaE1eEe8205 0x45DCE8e4F2Dc005A5F28206A46cb034697eEDA8e 0x)  --chain-id 130 --watch --verifier etherscan --etherscan-api-key $UNISCAN_API_KEY
// plumephoenix : forge script ./scripts/ops/FraxDVNTest/mainnet/1b_DeployMockFrax.s.sol --rpc-url https://rpc.plume.org --verifier-url $PLUMEPHOENIX_BLOCKSCOUT_API_URL --verifier blockscout --verify --broadcast

contract DeployMockFrax is DeployFraxOFTProtocol {
    address[] public proxyOftWallets;
    address mFraxProxyAdmin = 0x8d8290d49e88D16d81C6aDf6C8774eD88762274A;

    function run() public override {
        deploySource();
    }

    function preDeployChecks() public view override {
        for (uint256 e = 0; e < allConfigs.length; e++) {
            uint256 eid = allConfigs[e].eid;
            // source and dest eid cannot be same
            if (eid == broadcastConfig.eid) continue;
            if (broadcastConfig.eid == 30370) {
                // L0 team has not setup defaultSendLibrary and defaultReceiveLibrary on plumephoenix for
                // 30274 (x-layer), polygon zkevm (30158), worldchain (30319), zksync (30165), movement (30325)
                // and aptos (30108)
                if (eid == 30274 || eid == 30158 || eid == 30319 || eid == 30165 || eid == 30325 || eid == 30108) continue; 
            } 
            require(
                IMessageLibManager(broadcastConfig.endpoint).isSupportedEid(uint32(allConfigs[e].eid)),
                "L0 team required to setup `defaultSendLibrary` and `defaultReceiveLibrary` for EID"
            );
        }
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

        implementation = address(new FraxOFTUpgradeable(broadcastConfig.endpoint));
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
        require(isStringEqual(FraxOFTUpgradeable(proxy).name(), _name), "OFT name incorrect");
        require(isStringEqual(FraxOFTUpgradeable(proxy).symbol(), _symbol), "OFT symbol incorrect");
        require(address(FraxOFTUpgradeable(proxy).endpoint()) == broadcastConfig.endpoint, "OFT endpoint incorrect");
        require(
            EndpointV2(broadcastConfig.endpoint).delegates(proxy) == vm.addr(configDeployerPK),
            "Endpoint delegate incorrect"
        );
        require(FraxOFTUpgradeable(proxy).owner() == vm.addr(configDeployerPK), "OFT owner incorrect");
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
