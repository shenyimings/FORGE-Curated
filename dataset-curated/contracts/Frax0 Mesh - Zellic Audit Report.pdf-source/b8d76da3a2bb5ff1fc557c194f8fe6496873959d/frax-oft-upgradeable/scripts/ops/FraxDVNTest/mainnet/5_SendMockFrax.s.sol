// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "scripts/BaseL0Script.sol";
import { FraxOFTWalletUpgradeable } from "contracts/FraxOFTWalletUpgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SendParam, OFTReceipt, MessagingFee, IOFT } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oft/interfaces/IOFT.sol";
import { FraxOFTUpgradeable } from "contracts/FraxOFTUpgradeable.sol";

// fraxtal : forge script scripts/ops/FraxDVNTest/mainnet/5_SendMockFrax.s.sol --rpc-url https://rpc.frax.com --broadcast
// ethereum : forge script scripts/ops/FraxDVNTest/mainnet/5_SendMockFrax.s.sol --rpc-url https://ethereum-rpc.publicnode.com --broadcast
// blast : forge script scripts/ops/FraxDVNTest/mainnet/5_SendMockFrax.s.sol --rpc-url https://rpc.blast.io --broadcast
// base : forge script scripts/ops/FraxDVNTest/mainnet/5_SendMockFrax.s.sol --rpc-url https://mainnet.base.org --broadcast
// mode : forge script scripts/ops/FraxDVNTest/mainnet/5_SendMockFrax.s.sol --rpc-url https://mainnet.mode.network/ --broadcast
// sei : forge script scripts/ops/FraxDVNTest/mainnet/5_SendMockFrax.s.sol --rpc-url https://evm-rpc.sei-apis.com --broadcast
// TODO: pending txn, xlayer : forge script scripts/ops/FraxDVNTest/mainnet/5_SendMockFrax.s.sol --rpc-url https://mainnet.xlayer-rpc.com --legacy --broadcast
// sonic : forge script scripts/ops/FraxDVNTest/mainnet/5_SendMockFrax.s.sol --rpc-url https://rpc.soniclabs.com/ --broadcast
// ink : forge script scripts/ops/FraxDVNTest/mainnet/5_SendMockFrax.s.sol --rpc-url https://rpc-gel.inkonchain.com --broadcast
// arbitrum : forge script scripts/ops/FraxDVNTest/mainnet/5_SendMockFrax.s.sol --rpc-url https://arb1.arbitrum.io/rpc --broadcast
// op : forge script scripts/ops/FraxDVNTest/mainnet/5_SendMockFrax.s.sol --rpc-url https://optimism-mainnet.public.blastapi.io --broadcast
// polygon : forge script scripts/ops/FraxDVNTest/mainnet/5_SendMockFrax.s.sol --rpc-url https://polygon-rpc.com --broadcast
// avalanche : forge script scripts/ops/FraxDVNTest/mainnet/5_SendMockFrax.s.sol --rpc-url https://api.avax.network/ext/bc/C/rpc --broadcast
// bnb : forge script scripts/ops/FraxDVNTest/mainnet/5_SendMockFrax.s.sol --rpc-url https://neat-lingering-orb.bsc.quiknode.pro/a9e1547db6f8261bf94f92603eec0cc3d0c66605 --broadcast
// zkpolygon : forge script scripts/ops/FraxDVNTest/mainnet/5_SendMockFrax.s.sol --rpc-url https://zkevm-rpc.com --broadcast
// berachain : forge script scripts/ops/FraxDVNTest/mainnet/5_SendMockFrax.s.sol --rpc-url https://rpc.berachain.com --broadcast
// linea : forge script scripts/ops/FraxDVNTest/mainnet/5_SendMockFrax.s.sol --rpc-url https://rpc.linea.build --broadcast --evm-version paris
// worldchain : forge script scripts/ops/FraxDVNTest/mainnet/5_SendMockFrax.s.sol --rpc-url https://worldchain-mainnet.g.alchemy.com/public --broadcast
// zksync era : forge script scripts/ops/FraxDVNTest/mainnet/5_SendMockFrax.s.sol --rpc-url https://mainnet.era.zksync.io --zksync // Note: this was performed directly on etherscan
// abstract : forge script scripts/ops/FraxDVNTest/mainnet/5_SendMockFrax.s.sol --rpc-url https://api.mainnet.abs.xyz --zksync  // Note: this was performed directly on etherscan
// unichain : forge script scripts/ops/FraxDVNTest/mainnet/5_SendMockFrax.s.sol --rpc-url https://mainnet.unichain.org --broadcast
// plumephoenix : forge script scripts/ops/FraxDVNTest/mainnet/5_SendMockFrax.s.sol --rpc-url https://rpc.plume.org --broadcast

contract SendMockFrax is BaseL0Script {
    // 1,81457,8453,34443,1329,252,196,146,57073,42161,10,137,43114,56,1101,80094,480,130
    address public constant mockFrax = 0x57558Cb8d6005DE0BAe8a2789d5EfaaE52dba5a8;
    address public constant mockFraxWallet = 0x741F0d8Bde14140f62107FC60A0EE122B37D4630;
    // 324, zksync, 30165
    address public constant mockFraxZkSync = 0x3Fc877008e396FdD7f9Ee3Deb2e8A54d54da705A;
    address public constant mockFraxZkSyncWallet = 0x0065435a2FcC4D4D5CD2c284C5daA9588E6fe03d;
    // 2741, abstract, 30324
    address public constant mockFraxAbstract = 0xBd39033994F5324Fe8D50bB524396A78ff9dFe22;
    address public constant mockFraxAbstractWallet = 0x72018C396221e5919c856a809E3Be54CbfDb1fa2;
    // 59144,linea, 30183
    address public constant mockFraxLinea = 0x6185334f1542a9966CbaD694577fFbede3DD1f1F;
    address public constant mockFraxLineaWallet = 0xD555D90A6b23B285575cd6192D972e35F70b5B89;

    uint256 amount = 1 ether;

    SendParam[] public sendParams;
    IOFT[] public ofts;
    address[] public destinations;

    function run() public broadcastAs(configDeployerPK) {
        uint256 _totalEthFee;
        address sourceOFT;
        address senderWallet;
        for (uint256 _i; _i < allConfigs.length; _i++) {
            if (allConfigs[_i].eid == 30151) continue;
            if (allConfigs[_i].eid == 30376) continue;
            if (broadcastConfig.eid == 30370) {
                // if broadcast config is plumephoenix,
                // skip x-layer (30274), polygon zkevm (30158), worldchain (30319), zksync (30165), movement (30325)
                // and aptos (30108)
                if (
                    allConfigs[_i].eid == 30274 ||
                    allConfigs[_i].eid == 30158 ||
                    allConfigs[_i].eid == 30319 ||
                    allConfigs[_i].eid == 30165 ||
                    allConfigs[_i].eid == 30325 ||
                    allConfigs[_i].eid == 30108
                ) continue;
            }
            if (broadcastConfig.chainid == allConfigs[_i].chainid) {
                if (allConfigs[_i].chainid == 59144) {
                    // linea
                    sourceOFT = mockFraxLinea;
                    senderWallet = mockFraxLineaWallet;
                } else if (allConfigs[_i].chainid == 2741) {
                    // abstract
                    sourceOFT = mockFraxAbstract;
                    senderWallet = mockFraxAbstractWallet;
                } else if (allConfigs[_i].chainid == 324) {
                    // zksync
                    sourceOFT = mockFraxZkSync;
                    senderWallet = mockFraxZkSyncWallet;
                } else {
                    // 1,81457,8453,34443,1329,252,196,146,57073,42161,10,137,43114,56,1101,80094,480,130,98866
                    sourceOFT = mockFrax;
                    senderWallet = mockFraxWallet;
                }
                break;
            }
        }
        require(sourceOFT != address(0), "SendMockFrax: sourceOFT should not be zero");
        require(senderWallet != address(0), "SendMockFrax: senderWallet should not be zero");
        for (uint256 _i; _i < allConfigs.length; _i++) {
            if (broadcastConfig.chainid == allConfigs[_i].chainid) continue;
            if (allConfigs[_i].eid == 30151) continue;
            if (allConfigs[_i].eid == 30376) continue;
            if (broadcastConfig.eid == 30370) {
                // if broadcast config is plumephoenix,
                // skip x-layer (30274), polygon zkevm (30158), worldchain (30319), zksync (30165), movement (30325)
                // and aptos (30108)
                if (
                    allConfigs[_i].eid == 30274 ||
                    allConfigs[_i].eid == 30158 ||
                    allConfigs[_i].eid == 30319 ||
                    allConfigs[_i].eid == 30165 ||
                    allConfigs[_i].eid == 30325 ||
                    allConfigs[_i].eid == 30108
                ) continue;
            }
            bytes32 recipientWallet;
            if (allConfigs[_i].eid == 30168) {
                // solana
                recipientWallet = 0x3c1b094729102e0c095ee2417e5940ee4f1eab4763f6113fe75281ab74c62398;
            } else if (allConfigs[_i].chainid == 59144) {
                // linea
                recipientWallet = addressToBytes32(mockFraxLineaWallet);
            } else if (allConfigs[_i].chainid == 2741) {
                // abstract
                recipientWallet = addressToBytes32(mockFraxAbstractWallet);
            } else if (allConfigs[_i].chainid == 324) {
                // zksync
                recipientWallet = addressToBytes32(mockFraxZkSyncWallet);
            } else {
                // 1,81457,8453,34443,1329,252,196,146,57073,42161,10,137,43114,56,1101,80094,480,130
                recipientWallet = addressToBytes32(mockFraxWallet);
            }
            SendParam memory _sendParam = SendParam({
                dstEid: uint32(allConfigs[_i].eid),
                to: recipientWallet,
                amountLD: amount,
                minAmountLD: 0,
                extraOptions: "",
                composeMsg: "",
                oftCmd: ""
            });
            sendParams.push(_sendParam);
            MessagingFee memory _fee = IOFT(sourceOFT).quoteSend(_sendParam, false);
            _totalEthFee += _fee.nativeFee;
            ofts.push(IOFT(sourceOFT));
            destinations.push(senderWallet);
        }
        FraxOFTWalletUpgradeable(senderWallet).batchBridgeWithEthFeeFromWallet{ value: _totalEthFee }(
            sendParams,
            ofts,
            destinations
        );
    }
}
