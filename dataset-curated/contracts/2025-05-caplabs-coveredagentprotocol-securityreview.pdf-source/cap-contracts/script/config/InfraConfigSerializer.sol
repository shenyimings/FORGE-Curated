// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { ImplementationsConfig, InfraConfig, LibsConfig } from "../../contracts/deploy/interfaces/DeployConfigs.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { Vm } from "forge-std/Vm.sol";
import { console } from "forge-std/console.sol";

contract InfraConfigSerializer {
    using stdJson for string;

    function _capInfraFilePath() private view returns (string memory) {
        Vm vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
        return string.concat(vm.projectRoot(), "/config/cap-infra.json");
    }

    function _saveInfraConfig(ImplementationsConfig memory implems, LibsConfig memory libs, InfraConfig memory infra)
        internal
    {
        string memory implemsJson = "implems";
        implemsJson.serialize("accessControl", implems.accessControl);
        implemsJson.serialize("lender", implems.lender);
        implemsJson.serialize("delegation", implems.delegation);
        implemsJson.serialize("capToken", implems.capToken);
        implemsJson.serialize("stakedCap", implems.stakedCap);
        implemsJson.serialize("oracle", implems.oracle);
        implemsJson.serialize("principalDebtToken", implems.principalDebtToken);
        implemsJson.serialize("interestDebtToken", implems.interestDebtToken);
        implemsJson = implemsJson.serialize("restakerDebtToken", implems.restakerDebtToken);
        console.log(implemsJson);

        string memory libsJson = "libs";
        libsJson.serialize("aaveAdapter", libs.aaveAdapter);
        libsJson.serialize("chainlinkAdapter", libs.chainlinkAdapter);
        libsJson.serialize("capTokenAdapter", libs.capTokenAdapter);
        libsJson = libsJson.serialize("stakedCapAdapter", libs.stakedCapAdapter);
        console.log(libsJson);

        string memory infraJson = "infra";
        infraJson.serialize("oracle", infra.oracle);
        infraJson.serialize("accessControl", infra.accessControl);
        infraJson.serialize("lender", infra.lender);
        infraJson = infraJson.serialize("delegation", infra.delegation);
        console.log(infraJson);

        string memory chainJson = "chain";
        chainJson.serialize("implems", implemsJson);
        chainJson.serialize("libs", libsJson);
        chainJson = chainJson.serialize("infra", infraJson);
        console.log(chainJson);

        Vm vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
        string memory previousJson = vm.readFile(_capInfraFilePath());
        string memory mergedJson = "merged";
        mergedJson.serialize(previousJson);
        mergedJson = mergedJson.serialize(Strings.toString(block.chainid), chainJson);
        vm.writeFile(_capInfraFilePath(), mergedJson);
    }

    function _readInfraConfig()
        internal
        view
        returns (ImplementationsConfig memory implems, LibsConfig memory libs, InfraConfig memory infra)
    {
        Vm vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
        string memory json = vm.readFile(_capInfraFilePath());
        string memory chainPrefix = string.concat("$['", Strings.toString(block.chainid), "'].");

        string memory implemsPrefix = string.concat(chainPrefix, "implems.");
        implems = ImplementationsConfig({
            accessControl: json.readAddress(string.concat(implemsPrefix, "accessControl")),
            lender: json.readAddress(string.concat(implemsPrefix, "lender")),
            delegation: json.readAddress(string.concat(implemsPrefix, "delegation")),
            capToken: json.readAddress(string.concat(implemsPrefix, "capToken")),
            stakedCap: json.readAddress(string.concat(implemsPrefix, "stakedCap")),
            oracle: json.readAddress(string.concat(implemsPrefix, "oracle")),
            principalDebtToken: json.readAddress(string.concat(implemsPrefix, "principalDebtToken")),
            interestDebtToken: json.readAddress(string.concat(implemsPrefix, "interestDebtToken")),
            restakerDebtToken: json.readAddress(string.concat(implemsPrefix, "restakerDebtToken"))
        });

        string memory libsPrefix = string.concat(chainPrefix, "libs.");
        libs = LibsConfig({
            aaveAdapter: json.readAddress(string.concat(libsPrefix, "aaveAdapter")),
            chainlinkAdapter: json.readAddress(string.concat(libsPrefix, "chainlinkAdapter")),
            capTokenAdapter: json.readAddress(string.concat(libsPrefix, "capTokenAdapter")),
            stakedCapAdapter: json.readAddress(string.concat(libsPrefix, "stakedCapAdapter"))
        });

        string memory infraPrefix = string.concat(chainPrefix, "infra.");
        infra = InfraConfig({
            oracle: json.readAddress(string.concat(infraPrefix, "oracle")),
            accessControl: json.readAddress(string.concat(infraPrefix, "accessControl")),
            lender: json.readAddress(string.concat(infraPrefix, "lender")),
            delegation: json.readAddress(string.concat(infraPrefix, "delegation"))
        });
    }
}
