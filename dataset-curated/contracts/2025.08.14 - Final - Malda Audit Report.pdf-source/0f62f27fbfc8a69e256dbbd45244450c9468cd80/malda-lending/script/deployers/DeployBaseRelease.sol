// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {
    DeployNetworksConfigRelease,
    DeployGenericConfigRelease,
    ConnextDomain,
    OracleFeed,
    MarketRelease,
    Role,
    InterestConfig,
    DeployerConfig
} from "./Types.sol";

contract DeployBaseRelease is Script {
    using stdJson for string;

    mapping(uint32 => address) internal spokePoolAddresses;
    mapping(uint32 => address) internal connextAddresses;
    mapping(uint32 => address) internal everclearAddresses;
    mapping(string => DeployNetworksConfigRelease) internal configs;
    DeployGenericConfigRelease internal genericConfig;
    string public configPath;
    string[] public networks;
    uint256 public key;
    mapping(string => uint256) public forks;
    OracleFeed[] internal feeds;

    function setUp() public virtual {
        key = vm.envUint("OWNER_PRIVATE_KEY");
        networks = vm.parseJsonKeys(vm.readFile(configPath), ".networks");

        // parse generic config
        _parseGenericConfig();

        // parse networks configs
        for (uint256 i = 0; i < networks.length; i++) {
            string memory network = networks[i];
            _parseNetworkConfig(network);
        }
    }

    function _parseGenericConfig() internal {
        string memory json = vm.readFile(configPath);
        string memory domainsPath = string.concat(".generic.connextDomains");

        // Parse generic config
        ConnextDomain[] memory connextDomains = abi.decode(json.parseRaw(domainsPath), (ConnextDomain[]));

        for (uint256 i; i < connextDomains.length;) {
            genericConfig.connextDomains.push(connextDomains[i]);
            unchecked {
                ++i;
            }
        }
    }

    function _parseNetworkConfig(string memory network) internal {
        DeployNetworksConfigRelease storage config = configs[network];
        string memory json = vm.readFile(configPath);
        string memory networkPath = string.concat(".networks.", network);

        // Parse basic config
        config.chainId = uint32(abi.decode(json.parseRaw(string.concat(networkPath, ".chainId")), (uint256)));
        config.ownership = address(abi.decode(json.parseRaw(string.concat(networkPath, ".ownership")), (address)));
        config.isHost = abi.decode(json.parseRaw(string.concat(networkPath, ".isHost")), (bool));

        // Parse deployer config
        DeployerConfig memory deployerConfig =
            abi.decode(json.parseRaw(string.concat(networkPath, ".deployer")), (DeployerConfig));
        config.deployer = deployerConfig;

        // Parse roles
        Role[] memory roles = abi.decode(json.parseRaw(string.concat(networkPath, ".roles")), (Role[]));

        for (uint256 i = 0; i < roles.length; i++) {
            config.roles.push(roles[i]);
        }

        // Parse markets
        MarketRelease[] memory markets =
            abi.decode(json.parseRaw(string.concat(networkPath, ".markets")), (MarketRelease[]));
        for (uint256 i = 0; i < markets.length; i++) {
            config.markets.push(markets[i]);
        }

        // Parse zkVerifier config
        config.zkVerifier.verifierAddress =
            abi.decode(json.parseRaw(string.concat(networkPath, ".zkVerifier.verifierAddress")), (address));
        config.zkVerifier.imageId =
            abi.decode(json.parseRaw(string.concat(networkPath, ".zkVerifier.imageId")), (bytes32));

        // Parse host-specific config
        if (config.isHost) {
            _parseHostConfig(json, network, networkPath);
        }
    }

    function _parseHostConfig(string memory json, string memory network, string memory networkPath) internal {
        DeployNetworksConfigRelease storage config = configs[network];

        // Parse oracle config
        string memory oraclePath = string.concat(networkPath, ".oracle");
        config.oracle.oracleType = abi.decode(json.parseRaw(string.concat(oraclePath, ".oracleType")), (string));
        config.oracle.stalenessPeriod =
            abi.decode(json.parseRaw(string.concat(oraclePath, ".stalenessPeriod")), (uint256));

        // Parse allowed chains
        bytes memory allowedChainsRaw = json.parseRaw(string.concat(networkPath, ".allowedChains"));
        config.allowedChains = abi.decode(allowedChainsRaw, (uint32[]));
    }

    function _verifyChain(string memory network) internal view {
        require(block.chainid == configs[network].chainId, "Wrong chain");
    }

    function getSalt(string memory name) internal view returns (bytes32) {
        return keccak256(
            abi.encodePacked(msg.sender, bytes(vm.envString("DEPLOY_SALT")), bytes(string.concat(name, "-v1")))
        );
    }
}
