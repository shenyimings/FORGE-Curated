// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";

import { WFRAXTokenOFTUpgradeable } from "contracts/WFRAXTokenOFTUpgradeable.sol";

/*
Scripts to deploy the upgrade FRAX OFT implementation

Mode (routescan)
forge script scripts/ops/UpgradeFrax/1_DeployUpgradedImplementation.s.sol --rpc-url https://mainnet.mode.network --broadcast --verify --verifier-url 'https://api.routescan.io/v2/network/mainnet/evm/34443/etherscan' --etherscan-api-key "verifyContract" --verifier etherscan

Sei (seitrace)
forge script scripts/ops/UpgradeFrax/1_DeployUpgradedImplementation.s.sol --rpc-url https://evm-rpc.sei-apis.com --broadcast --verify --verifier-url https://seitrace.com/pacific-1/api --verifier custom --verifier-api-key $SEITRACE_API_KEY 

X-Layer (oklink)
forge script scripts/ops/UpgradeFrax/1_DeployUpgradedImplementation.s.sol --rpc-url https://xlayerrpc.okx.com --legacy --broadcast --verify --verifier-url https://www.oklink.com/api/v5/explorer/contract/verify-source-code-plugin/XLAYER --verifier oklink --verifier-api-key $OKLINK_API_KEY

Sonic (etherscan)
forge script scripts/ops/UpgradeFrax/1_DeployUpgradedImplementation.s.sol --rpc-url https://rpc.soniclabs.com --broadcast --verify --verifier etherscan --etherscan-api-key $SONICSCAN_API_KEY

Ink (blockscout)
forge script scripts/ops/UpgradeFrax/1_DeployUpgradedImplementation.s.sol --rpc-url https://rpc-gel.inkonchain.com --broadcast --verify --verifier blockscout --verifier-url https://explorer.inkonchain.com/api/

Arbitrum (etherscan)
forge script scripts/ops/UpgradeFrax/1_DeployUpgradedImplementation.s.sol --rpc-url https://arb1.arbitrum.io/rpc --broadcast --verify --verifier etherscan --etherscan-api-key $ARBISCAN_API_KEY

Optimism (etherscan)
forge script scripts/ops/UpgradeFrax/1_DeployUpgradedImplementation.s.sol --rpc-url https://optimism-mainnet.public.blastapi.io --broadcast --verify --verifier etherscan --etherscan-api-key $OPTIMISM_API_KEY

Polygon (etherscan)
forge script scripts/ops/UpgradeFrax/1_DeployUpgradedImplementation.s.sol --rpc-url https://polygon-rpc.com --broadcast --verify --verifier etherscan --etherscan-api-key $POLYGONSCAN_API_KEY

Avalanche (routescan)
forge script scripts/ops/UpgradeFrax/1_DeployUpgradedImplementation.s.sol --rpc-url https://api.avax.network/ext/bc/C/rpc --broadcast --verify --verifier-url 'https://api.routescan.io/v2/network/mainnet/evm/43114/etherscan' --etherscan-api-key "verifyContract" --verifier etherscan

BSC (etherscan)
forge script scripts/ops/UpgradeFrax/1_DeployUpgradedImplementation.s.sol --rpc-url https://bsc-mainnet.public.blastapi.io --broadcast --verify --verifier etherscan --etherscan-api-key $BSC_SCAN_API_KEY

Polygon zkEvm (etherscan)
forge script scripts/ops/UpgradeFrax/1_DeployUpgradedImplementation.s.sol --rpc-url https://zkevm-rpc.com --broadcast --verify --verifier etherscan --etherscan-api-key $ZKEVM_API_KEY

Blast (etherscan)
forge script scripts/ops/UpgradeFrax/1_DeployUpgradedImplementation.s.sol --rpc-url https://rpc.blast.io --broadcast --verify --verifier etherscan --etherscan-api-key $BLASTSCAN_API_KEY

Base (etherscan) (needed to manually verify)
forge script scripts/ops/UpgradeFrax/1_DeployUpgradedImplementation.s.sol --rpc-url https://mainnet.base.org --broadcast

Berachain (etherscan)
forge script scripts/ops/UpgradeFrax/1_DeployUpgradedImplementation.s.sol --rpc-url https://rpc.berachain.com --broadcast --verify --verifier etherscan --etherscan-api-key $BERACHAIN_API_KEY

Linea (etherscan) (NOTE: needs evm-version paris)
forge script scripts/ops/UpgradeFrax/1_DeployUpgradedImplementation.s.sol --rpc-url https://rpc.linea.build --broadcast --legacy --verify --verifier etherscan --etherscan-api-key $LINEASCAN_API_KEY

Abstract
forge script scripts/ops/UpgradeFrax/1_DeployUpgradedImplementation.s.sol --rpc-url https://api.mainnet.abs.xyz  --zksync --broadcast --verify --verifier etherscan --etherscan-api-key $ABSTRACT_ETHERSCAN_API_KEY

ZkSync
forge script scripts/ops/UpgradeFrax/1_DeployUpgradedImplementation.s.sol --rpc-url https://rpc.ankr.com/zksync_era  --zksync --broadcast --verify --verifier etherscan --etherscan-api-key $ZKSYNC_ERA_ETHERSCAN_API_KEY
*/

contract DeployUpgradedImplementation is DeployFraxOFTProtocol {
    function run() public override broadcastAs(configDeployerPK) {
        address fraxImplementation = address(new WFRAXTokenOFTUpgradeable(broadcastConfig.endpoint));
        console.log("FRAX Imp. @ ", fraxImplementation);
    }
}