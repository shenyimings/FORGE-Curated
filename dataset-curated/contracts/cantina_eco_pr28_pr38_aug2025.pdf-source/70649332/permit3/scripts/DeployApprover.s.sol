pragma solidity ^0.8.0;

import {ERC7702TokenApprover} from "../src/modules/ERC7702TokenApprover.sol";
import {CommonBase} from "forge-std/Base.sol";
import {Script} from "forge-std/Script.sol";
import {StdChains} from "forge-std/StdChains.sol";
import {StdCheatsSafe} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {console} from "forge-std/console.sol";

contract DeployApprover is Script {
    address public constant create2Factory = 0xce0042B868300000d44A59004Da54A005ffdcf9f;

    function run() external {
        bytes32 salt = vm.envBytes32("SALT");
        address permit3Address = vm.envAddress("PERMIT3_ADDRESS");
        vm.rememberKey(vm.envUint("PRIVATE_KEY"));

        vm.startBroadcast();

        // Deploy ERC7702TokenApprover with provided Permit3 address
        bytes memory erc7702Code = abi.encodePacked(
            type(ERC7702TokenApprover).creationCode,
            abi.encode(permit3Address)
        );
        address erc7702Approver = deploy(erc7702Code, salt);
        console.log("ERC7702TokenApprover:", erc7702Approver);

        vm.stopBroadcast();
    }

    /**
     * @notice Deploy a contract using CREATE2 factory
     * @param initCode The bytecode of the contract to deploy
     * @param salt Unique salt for deterministic address generation
     * @return The address of the deployed contract
     */
    function deploy(bytes memory initCode, bytes32 salt) public returns (address) {
        bytes4 selector = bytes4(keccak256("deploy(bytes,bytes32)"));
        bytes memory args = abi.encode(initCode, salt);
        bytes memory data = abi.encodePacked(selector, args);
        (bool success, bytes memory returnData) = create2Factory.call(data);
        require(success, "Failed to deploy contract");
        return abi.decode(returnData, (address));
    }
}