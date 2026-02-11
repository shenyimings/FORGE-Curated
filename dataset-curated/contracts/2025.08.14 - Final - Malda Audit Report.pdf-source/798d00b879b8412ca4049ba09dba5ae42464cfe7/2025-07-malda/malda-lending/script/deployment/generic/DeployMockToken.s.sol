// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {Deployer} from "src/utils/Deployer.sol";
import {ERC20Mock} from "test/mocks/ERC20Mock.sol";

/**
 * forge script DeployMockToken  \
 *     --slow \
 *     --verify \
 *     --verifier-url <url> \
 *     --rpc-url <url> \
 *     --etherscan-api-key <key> \
 *     --broadcast
 */
contract DeployMockToken is Script {
    string constant NAME = "wstETH Mock";
    string constant SYMBOL = "wstETH-M";
    uint8 constant DECIMALS = 18;
    address constant OWNER = 0xCde13fF278bc484a09aDb69ea1eEd3cAf6Ea4E00;
    address constant POH_VERIFY = 0xBf14cFAFD7B83f6de881ae6dc10796ddD7220831; //linea
    uint256 constant LIMIT = 1000e6;

    function run(Deployer deployer) public returns (address) {
        bytes32 salt = keccak256(abi.encodePacked(msg.sender, bytes(vm.envString("DEPLOY_SALT")), bytes("Mock-wstETH")));

        uint256 key = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(key);

        address created = deployer.create(
            salt,
            abi.encodePacked(type(ERC20Mock).creationCode, abi.encode(NAME, SYMBOL, DECIMALS, OWNER, POH_VERIFY, LIMIT))
        );

        console.log(" ERC20Mock deployed at: %s", created);

        vm.stopBroadcast();

        return created;
    }
}
