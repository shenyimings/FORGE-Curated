// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.29;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {BuilderCodes} from "../src/BuilderCodes.sol";

/// @notice Script for deploying the BuilderCodes contract
contract DeployBuilderCodes is Script {
    /// @notice Deploys the BuilderCodes with proxy
    /// @param owner Address that will own the registry contract
    /// @param signerAddress Address authorized to call registerPublisherCustom (can be zero address)
    function run(address owner, address signerAddress, string memory uriPrefix) external returns (address) {
        require(owner != address(0), "Owner cannot be zero address");

        vm.startBroadcast();

        // Deploy the implementation contract
        BuilderCodes implementation = new BuilderCodes();

        // Prepare initialization data
        bytes memory initData = abi.encodeCall(BuilderCodes.initialize, (owner, signerAddress, uriPrefix));

        // Deploy the proxy
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);

        console.log("BuilderCodes implementation deployed at:", address(implementation));
        console.log("BuilderCodes proxy deployed at:", address(proxy));
        console.log("Owner:", owner);
        console.log("Signer address:", signerAddress);

        vm.stopBroadcast();

        return address(proxy);
    }
}
