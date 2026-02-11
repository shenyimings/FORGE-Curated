// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import { Script } from "forge-std/Script.sol";
import "forge-std/StdJson.sol";
import "frax-template/src/Constants.sol";
import { console } from "frax-std/FraxTest.sol";

import { L0Constants, L0Config } from "scripts/L0Constants.sol";
import { SerializedTx, SafeTxUtil } from "scripts/SafeBatchSerialize.sol";
import { FraxOFTUpgradeable } from "contracts/FraxOFTUpgradeable.sol";
import { FrxUSDOFTUpgradeable } from "contracts/frxUsd/FrxUSDOFTUpgradeable.sol";
import { FraxProxyAdmin } from "contracts/FraxProxyAdmin.sol";
import { ImplementationMock } from "contracts/mocks/ImplementationMock.sol";

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { EndpointV2 } from "@fraxfinance/layerzero-v2-upgradeable/protocol/contracts/EndpointV2.sol";
import { SetConfigParam, IMessageLibManager} from "@fraxfinance/layerzero-v2-upgradeable/protocol/contracts/interfaces/IMessageLibManager.sol";

import { OptionsBuilder } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oapp/libs/OptionsBuilder.sol";
import { EnforcedOptionParam, IOAppOptionsType3 } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oapp/interfaces/IOAppOptionsType3.sol";
import { IOAppCore } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oapp/interfaces/IOAppCore.sol";
import { SendParam, OFTReceipt, MessagingFee, IOFT } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oft/interfaces/IOFT.sol";

import { ProxyAdmin, TransparentUpgradeableProxy } from "@fraxfinance/layerzero-v2-upgradeable/messagelib/contracts/upgradeable/proxy/ProxyAdmin.sol";


contract BaseL0Script is L0Constants, Script {

    using OptionsBuilder for bytes;
    using stdJson for string;
    using Strings for uint256;

    uint256 public oftDeployerPK = vm.envUint("PK_OFT_DEPLOYER");
    uint256 public configDeployerPK = vm.envUint("PK_CONFIG_DEPLOYER");
    uint256 public senderDeployerPK = vm.envUint("PK_SENDER_DEPLOYER");

    L0Config[] public legacyConfigs;
    L0Config[] public proxyConfigs;
    L0Config[] public evmConfigs;
    L0Config[] public nonEvmConfigs;
    L0Config[] public allConfigs; // legacy, proxy, and non-evm allConfigs
    L0Config[] public testnetConfigs;
    L0Config public broadcastConfig; // config of actively-connected (broadcasting) chain
    L0Config public simulateConfig;  // Config of the simulated chain
    L0Config[] public broadcastConfigArray; // length of 1 of broadcastConfig

    // assume we're deploying to mainnet unless the broadcastConfig is set to a testnet
    bool public isMainnet = true;

    /// @dev alphabetical order as json is read in by keys alphabetically.
    struct NonEvmPeer {
        bytes32 fpi;
        bytes32 frxEth;
        bytes32 frxUSD;
        bytes32 sfrxEth;
        bytes32 sfrxUSD;
        bytes32 wfrax;
    }
    bytes32[][] public nonEvmPeersArrays;

    // Mock implementation used to enable pre-determinsitic proxy creation
    address public implementationMock;

    // Deployed proxies
    address public proxyAdmin;
    address public wfraxOft;
    address public sfrxUsdOft;
    address public sfrxEthOft;
    address public frxUsdOft;
    address public frxEthOft;
    address public fpiOft;
    uint256 public numOfts;

    // 1:1 match between these arrays for setting peers
    address[] public legacyOfts;
    address[] public proxyOfts; // the OFTs deployed through `DeployFraxOFTProtocol.s.sol`

    // temporary storage
    EnforcedOptionParam[] public enforcedOptionParams;
    SerializedTx[] public serializedTxs;

    string public json;

    function version() public virtual pure returns (uint256, uint256, uint256) {
        return (1, 3, 2);
    }

    modifier broadcastAs(uint256 privateKey) {
        vm.startBroadcast(privateKey);
        _;
        vm.stopBroadcast();
    }

    modifier simulateAndWriteTxs(
        L0Config memory _simulateConfig
    ) virtual {
        // Clear out any previous txs
        delete enforcedOptionParams;
        delete serializedTxs;

        // store for later referencing
        simulateConfig = _simulateConfig;

        // Use the correct OFT addresses given the chain we're simulating
        _populateConnectedOfts();

        // Simulate fork as delegate (aka msig) as we're crafting txs within the modified function
        vm.createSelectFork(_simulateConfig.RPC);
        vm.startPrank(_simulateConfig.delegate);
        _;
        vm.stopPrank();

        // serialized txs were pushed within the modified function- write to storage
        if (serializedTxs.length > 0) {
            new SafeTxUtil().writeTxs(serializedTxs, filename());
        }
    }

    // Configure destination OFT addresses as they may be different per chain
    // `connectedOfts` is used within DeployfraxOFTProtocol.setupDestination()
    function _populateConnectedOfts() public virtual {
        isMainnet ?
            _validateAndPopulateMainnetOfts() :
            _validateAndPopulateTestnetOfts();
    }

    function _validateAndPopulateMainnetOfts() internal virtual {
        // @dev check to prevent array mismatch.  This will trigger when, for example, managing peers of 2 of 6 OFTs as
        // this method asumes we're managing all 6 OFTs
        // @dev if proxyOfts are empty, pre-populate
        if (proxyOfts.length == 0) {
            for (uint256 i=0; i<expectedProxyOfts.length; i++) {
                proxyOfts.push(expectedProxyOfts[i]);
            }
        } else {
            require (proxyOfts.length == 6, "proxyOfts.length != 6");
        }

        connectedOfts = new address[](6);

        /// @dev order maintained through L0Constants.sol `constructor()` and DeployFraxOFTProtocol.s.sol `deployFraxOFTUpgradeablesAndProxies()`
        if (simulateConfig.chainid == 1) {
            connectedOfts[0] = ethLockboxes[0];
            connectedOfts[1] = ethLockboxes[1];
            connectedOfts[2] = ethLockboxes[2];
            connectedOfts[3] = ethLockboxes[3];
            connectedOfts[4] = ethLockboxes[4];
            connectedOfts[5] = ethLockboxes[5];
        } else if (simulateConfig.chainid == 252) {
            // TODO: modify this readme to "Fraxtal Lockboxes"
            // https://github.com/FraxFinance/frax-oft-upgradeable?tab=readme-ov-file#fraxtal-standalone-frxusdsfrxusd-lockboxes
            connectedOfts[0] = fraxtalLockboxes[0];
            connectedOfts[1] = fraxtalLockboxes[1];
            connectedOfts[2] = fraxtalLockboxes[2];
            connectedOfts[3] = fraxtalLockboxes[3];
            connectedOfts[4] = fraxtalLockboxes[4];
            connectedOfts[5] = fraxtalLockboxes[5];
        } else if (simulateConfig.chainid == 8453) {
            connectedOfts[0] = baseProxyOfts[0];
            connectedOfts[1] = baseProxyOfts[1];
            connectedOfts[2] = baseProxyOfts[2];
            connectedOfts[3] = baseProxyOfts[3];
            connectedOfts[4] = baseProxyOfts[4];
            connectedOfts[5] = baseProxyOfts[5];
        } else if (simulateConfig.chainid == 59144) {
            connectedOfts[0] = lineaProxyOfts[0];
            connectedOfts[1] = lineaProxyOfts[1];
            connectedOfts[2] = lineaProxyOfts[2];
            connectedOfts[3] = lineaProxyOfts[3];
            connectedOfts[4] = lineaProxyOfts[4];
            connectedOfts[5] = lineaProxyOfts[5];
        } else if (simulateConfig.chainid == 8453) {
            connectedOfts[0] = baseProxyOfts[0];
            connectedOfts[1] = baseProxyOfts[1];
            connectedOfts[2] = baseProxyOfts[2];
            connectedOfts[3] = baseProxyOfts[3];
            connectedOfts[4] = baseProxyOfts[4];
            connectedOfts[5] = baseProxyOfts[5];
        } else if (simulateConfig.chainid == 2741 || simulateConfig.chainid == 324) {
            connectedOfts[0] = zkEraProxyOfts[0];
            connectedOfts[1] = zkEraProxyOfts[1];
            connectedOfts[2] = zkEraProxyOfts[2];
            connectedOfts[3] = zkEraProxyOfts[3];
            connectedOfts[4] = zkEraProxyOfts[4];
            connectedOfts[5] = zkEraProxyOfts[5];
        } else {
            // https://github.com/FraxFinance/frax-oft-upgradeable?tab=readme-ov-file#proxy-upgradeable-ofts
            connectedOfts[0] = expectedProxyOfts[0];
            connectedOfts[1] = expectedProxyOfts[1];
            connectedOfts[2] = expectedProxyOfts[2];
            connectedOfts[3] = expectedProxyOfts[3];
            connectedOfts[4] = expectedProxyOfts[4];
            connectedOfts[5] = expectedProxyOfts[5];
        }
    }

    function _validateAndPopulateTestnetOfts() internal virtual {
        if (proxyOfts.length == 0) {
            proxyOfts.push(expectedProxyOfts[3]); // frxUSD OFT
        } else {
            require(proxyOfts.length == 1, "proxyOfts[0] != frxUSD"); // only frxUSD OFT
        }

        connectedOfts = new address[](1);

        if (simulateConfig.chainid == 11155111) {
            connectedOfts[0] = ethSepoliaLockboxes[0];
        } else if (simulateConfig.chainid == 421614) {
            connectedOfts[0] = arbitrumSepoliaOfts[0];
        } else if (simulateConfig.chainid == 2522) {
            connectedOfts[0] = fraxtalTestnetLockboxes[0];
        } else {
            revert("Testnet mismatch. Configure _validateAndPopulateTestnetOfts() for this chain");
        }
    }

    function filename() public view virtual returns (string memory) {
        string memory root = vm.projectRoot();
        root = string.concat(root, '/scripts/DeployFraxOFTProtocol/txs/');

        string memory name = string.concat(broadcastConfig.chainid.toString(), "-");
        name = string.concat(name, simulateConfig.chainid.toString());
        name = string.concat(name, ".json");
        return string.concat(root, name);
    }

    function setUp() public virtual {
        // Set constants based on deployment chain id
        loadJsonConfig();
    }

    function loadJsonConfig() public virtual {
        string memory root = vm.projectRoot();
        
        // L0Config.json

        string memory path = string.concat(root, "/scripts/L0Config.json");
        json = vm.readFile(path);

        // legacy
        L0Config[] memory legacyConfigs_ = abi.decode(json.parseRaw(".Legacy"), (L0Config[]));
        for (uint256 i=0; i<legacyConfigs_.length; i++) {
            L0Config memory config_ = legacyConfigs_[i];
            if (config_.chainid == block.chainid) {
                broadcastConfig = config_;
                broadcastConfigArray.push(config_);
            }
            legacyConfigs.push(config_);
            allConfigs.push(config_);
            evmConfigs.push(config_);
        }

        // proxy (active deployment loaded as broadcastConfig)
        L0Config[] memory proxyConfigs_ = abi.decode(json.parseRaw(".Proxy"), (L0Config[]));
        for (uint256 i=0; i<proxyConfigs_.length; i++) {
            L0Config memory config_ = proxyConfigs_[i];
            // broadcast config could have already been set if dealing with a legacy chain
            if (config_.chainid == block.chainid && broadcastConfigArray.length == 0) {
                broadcastConfig = config_;
                broadcastConfigArray.push(config_);
            }
            proxyConfigs.push(config_);
            // do not push legacy configs which have also been deployed as proxy configs
            if (
                config_.chainid != 1 && config_.chainid != 81457 &&
                config_.chainid != 1088 && config_.chainid != 8453
            ) {
                allConfigs.push(config_);
                evmConfigs.push(config_);
            }
        }

        // Non-EVM allConfigs
        /// @dev as foundry cannot deploy to non-evm, a non-evm chain will never be the active/connected chain
        L0Config[] memory nonEvmConfigs_ = abi.decode(json.parseRaw(".Non-EVM"), (L0Config[]));
        for (uint256 i=0; i<nonEvmConfigs_.length; i++) {
            L0Config memory config_ = nonEvmConfigs_[i];
            nonEvmConfigs.push(config_);
            allConfigs.push(config_);
        }

        // testnet
        L0Config[] memory testnetConfigs_ = abi.decode(json.parseRaw(".Testnet"), (L0Config[]));
        for (uint256 i=0; i<testnetConfigs_.length; i++) {
            L0Config memory config_ = testnetConfigs_[i];
            if (config_.chainid == block.chainid) {
                isMainnet = false; // validate we're on testnet
                broadcastConfig = config_;
                broadcastConfigArray.push(config_);
            }
            testnetConfigs.push(config_);
        }

        // NonEvmPeers.json

        path = string.concat(root, "/scripts/NonEvmPeers.json");
        json = vm.readFile(path);

        NonEvmPeer[] memory nonEvmPeers = abi.decode(json.parseRaw(".Peers"), (NonEvmPeer[]));
        
        // As json has to be ordered alphabetically, sort the peer addresses in the order of OFT deployment
        for (uint256 i=0; i<nonEvmPeers.length; i++) {
            NonEvmPeer memory peer = nonEvmPeers[i];
            bytes32[] memory peerArray = new bytes32[](6);
            peerArray[0] = peer.wfrax;
            peerArray[1] = peer.sfrxUSD;
            peerArray[2] = peer.sfrxEth;
            peerArray[3] = peer.frxUSD;
            peerArray[4] = peer.frxEth;
            peerArray[5] = peer.fpi;

            nonEvmPeersArrays.push(peerArray);
        }

    }

    function isStringEqual(string memory _a, string memory _b) public pure returns (bool) {
        return keccak256(abi.encodePacked(_a)) == keccak256(abi.encodePacked(_b));
    }

    function addressToBytes32(address _addr) public pure returns (bytes32) {
        return bytes32(uint256(uint160(_addr)));
    }

}