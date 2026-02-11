// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {
    SymbioticNetworkAdapterConfig,
    SymbioticNetworkAdapterImplementationsConfig
} from "../../contracts/deploy/interfaces/SymbioticsDeployConfigs.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { Vm } from "forge-std/Vm.sol";
import { console } from "forge-std/console.sol";

contract SymbioticAdapterConfigSerializer {
    using stdJson for string;

    function _symbioticConfigFilePath() private view returns (string memory) {
        Vm vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
        return string.concat(vm.projectRoot(), "/config/cap-symbiotic.json");
    }

    function _saveSymbioticConfig(
        SymbioticNetworkAdapterImplementationsConfig memory implems,
        SymbioticNetworkAdapterConfig memory adapter
    ) internal {
        string memory implemsJson = "implems";
        implemsJson.serialize("network", implems.network);
        implemsJson = implemsJson.serialize("networkMiddleware", implems.networkMiddleware);
        console.log(implemsJson);

        string memory adapterJson = "adapter";
        adapterJson.serialize("network", adapter.network);
        adapterJson.serialize("networkMiddleware", adapter.networkMiddleware);
        adapterJson = adapterJson.serialize("slashDuration", adapter.slashDuration);
        console.log(adapterJson);

        string memory chainJson = "chain";
        chainJson.serialize("implems", implemsJson);
        chainJson = chainJson.serialize("adapter", adapterJson);
        console.log(chainJson);

        Vm vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
        string memory previousJson = vm.readFile(_symbioticConfigFilePath());
        string memory mergedJson = "merged";
        mergedJson.serialize(previousJson);
        mergedJson = mergedJson.serialize(Strings.toString(block.chainid), chainJson);
        vm.writeFile(_symbioticConfigFilePath(), mergedJson);
    }

    function _readSymbioticConfig()
        internal
        view
        returns (
            SymbioticNetworkAdapterImplementationsConfig memory implems,
            SymbioticNetworkAdapterConfig memory adapter
        )
    {
        Vm vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
        string memory json = vm.readFile(_symbioticConfigFilePath());
        string memory chainPrefix = string.concat("$['", Strings.toString(block.chainid), "'].");

        string memory implemsPrefix = string.concat(chainPrefix, "implems.");
        implems = SymbioticNetworkAdapterImplementationsConfig({
            network: json.readAddress(string.concat(implemsPrefix, "network")),
            networkMiddleware: json.readAddress(string.concat(implemsPrefix, "networkMiddleware"))
        });

        string memory adapterPrefix = string.concat(chainPrefix, "adapter.");
        adapter = SymbioticNetworkAdapterConfig({
            network: json.readAddress(string.concat(adapterPrefix, "network")),
            networkMiddleware: json.readAddress(string.concat(adapterPrefix, "networkMiddleware")),
            slashDuration: uint48(json.readUint(string.concat(adapterPrefix, "slashDuration")))
        });
    }
}
