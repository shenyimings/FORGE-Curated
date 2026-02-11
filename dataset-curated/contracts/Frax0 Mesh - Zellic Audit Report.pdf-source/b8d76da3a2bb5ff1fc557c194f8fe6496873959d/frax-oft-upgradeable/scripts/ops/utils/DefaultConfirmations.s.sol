pragma solidity ^0.8.0;

import "scripts/BaseL0Script.sol";
import "scripts/DeployFraxOFTProtocol/inherited/SetDVNs.s.sol";

interface IULN {
    function getUlnConfig(address _oapp, uint32 _remoteEid) external view returns (UlnConfig memory rtnConfig);
}

contract DefaultConfirmations is Script {

    using Strings for uint256;
    using stdJson for string;

    struct Config {
        string RPC;
        uint256 chainid;
        uint256 eid;
        address oft;
        address receiveLib;
        address sendLib;
    }
    Config[] public configs;
    string json;
    
    function run() external {
        loadJson();

        console.log("Recieve confirmations analyzed.");
        for (uint256 a=0; a<configs.length; a++) {
            printReceiveConfirmations(configs[a]);
        }

        console.log("\n\n Send confirmations analyzed.");
        for (uint256 a=0; a<configs.length; a++) {
            if (configs[a].eid == 30168) continue;
            printSendConfirmations(configs[a]);
        }
    }


    function printReceiveConfirmations(Config memory config) public {
        console.log(string.concat("\nDestination chain analyzed: ", config.chainid.toString()));

        for (uint256 b=0; b<configs.length; b++) {
            Config memory targetConfig = configs[b];
            if (config.chainid == targetConfig.chainid) continue;
            if (targetConfig.eid == 30168) continue; // solana

            vm.createSelectFork(targetConfig.RPC);

            UlnConfig memory ulnConfig = IULN(targetConfig.receiveLib).getUlnConfig(
                targetConfig.oft,
                uint32(config.eid)
            );

            string memory message = string.concat(targetConfig.chainid.toString(), " receiveLib: ");
            message = string.concat(message, uint256(ulnConfig.confirmations).toString());
            console.log(message);
        }
    }

    function printSendConfirmations(Config memory config) public {
        console.log(string.concat("\nSource chain analyzed: ", config.chainid.toString()));
        vm.createSelectFork(config.RPC);

        for (uint256 b=0; b<configs.length; b++) {
            Config memory targetConfig = configs[b];
            if (config.chainid == targetConfig.chainid) continue;

            UlnConfig memory ulnConfig = IULN(config.sendLib).getUlnConfig(
                config.oft,
                uint32(targetConfig.eid)
            );

            string memory message = string.concat(targetConfig.chainid.toString(), " sendLib: ");
            message = string.concat(message, uint256(ulnConfig.confirmations).toString());
            console.log(message);
        }
    }

    function loadJson() internal {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/scripts/ops/utils/json/DefaultConfirmations.json");
        json = vm.readFile(path);

        Config[] memory chains_ = abi.decode(json.parseRaw(".Config"), (Config[]));
        for (uint256 i=0; i<chains_.length; i++) {
            configs.push(chains_[i]);
        }
    }

}