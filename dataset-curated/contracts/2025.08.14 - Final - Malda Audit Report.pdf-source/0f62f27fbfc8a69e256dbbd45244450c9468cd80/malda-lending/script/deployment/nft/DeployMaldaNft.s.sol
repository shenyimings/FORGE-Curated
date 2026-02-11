// SPDX-License-Identifier: BSL-1.1
pragma solidity =0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {DeployBase} from "script/deployers/DeployBase.sol";
import {MaldaNft} from "src/nft/MaldaNft.sol";
import {Deployer} from "src/utils/Deployer.sol";

contract DeployMaldaNft is Script {
    function run() public returns (address) {
    //function run(Deployer deployer, string memory name, string memory symbol, string memory baseURI, address owner) public returns (address) {
        uint256 key = vm.envUint("OWNER_PRIVATE_KEY");

        Deployer deployer = Deployer(payable(0x7DE862D3f944b5BCbE30C43aa5434eE964a31a8C));
        string memory name = "Malda NFT Tier 1";
        string memory symbol = "MNFT-1";
        string memory baseURI = "https://malda.xyz/";
        address owner = 0xCde13fF278bc484a09aDb69ea1eEd3cAf6Ea4E00;

        bytes32 salt = getSalt("MaldaNftV1.0.0");

        console.log("Deploying MaldaNft");

        address created = deployer.precompute(salt);

        // Deploy only if not already deployed
        if (created.code.length == 0) {
            vm.startBroadcast(key);
            created =
                deployer.create(salt, abi.encodePacked(type(MaldaNft).creationCode, abi.encode(name, symbol, baseURI, owner)));
            vm.stopBroadcast();
            console.log("MaldaNft deployed at: %s", created);
        } else {
            console.log("Using existing MaldaNft at: %s", created);
        }

        return created;
    }

    function getSalt(string memory name) internal view returns (bytes32) {
        return keccak256(
            abi.encodePacked(msg.sender, bytes(vm.envString("DEPLOY_SALT")), bytes(string.concat(name, "-v1")))
        );
    }
}