// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { VaultConfig, VaultLzPeriphery } from "../../contracts/deploy/interfaces/DeployConfigs.sol";
import { TokenSerializer } from "./TokenSerializer.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { Vm } from "forge-std/Vm.sol";
import { console } from "forge-std/console.sol";

contract VaultConfigSerializer is TokenSerializer {
    using stdJson for string;

    function _capVaultsFilePath() private view returns (string memory) {
        return _capVaultsFilePath(block.chainid);
    }

    function _capVaultsFilePath(uint256 srcChainId) private view returns (string memory) {
        Vm vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
        return string.concat(vm.projectRoot(), "/config/cap-vaults-", Strings.toString(srcChainId), ".json");
    }

    function _saveVaultConfig(VaultConfig memory vault) internal {
        string memory vaultJson = "vault";

        string[] memory assetsJson = new string[](vault.assets.length);
        for (uint256 i = 0; i < vault.assets.length; i++) {
            string memory assetJson = string.concat("assets[", Strings.toString(i), "]");
            assetJson.serialize("asset", _serializeToken(vault.assets[i]));
            assetJson.serialize("principalDebtToken", _serializeToken(vault.principalDebtTokens[i]));
            assetJson.serialize("restakerDebtToken", _serializeToken(vault.restakerDebtTokens[i]));
            assetJson = assetJson.serialize("interestDebtToken", _serializeToken(vault.interestDebtTokens[i]));
            console.log(assetJson);
            assetsJson[i] = assetJson;
        }

        vaultJson.serialize("assets", assetsJson);
        vaultJson.serialize("capToken", _serializeToken(vault.capToken));
        vaultJson.serialize("restakerInterestReceiver", vault.restakerInterestReceiver);
        vaultJson.serialize("capOFTLockbox", vault.lzperiphery.capOFTLockbox);
        vaultJson.serialize("capZapComposer", vault.lzperiphery.capZapComposer);
        vaultJson.serialize("stakedCapToken", _serializeToken(vault.stakedCapToken));
        vaultJson = vaultJson.serialize("stakedCapOFTLockbox", vault.lzperiphery.stakedCapOFTLockbox);
        vaultJson = vaultJson.serialize("stakedCapZapComposer", vault.lzperiphery.stakedCapZapComposer);
        console.log(vaultJson);

        Vm vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
        string memory previousJson = vm.readFile(_capVaultsFilePath());
        string memory capTokenSymbol = IERC20Metadata(vault.capToken).symbol();
        string memory mergedJson = "merged";
        mergedJson.serialize(previousJson);
        mergedJson = mergedJson.serialize(capTokenSymbol, vaultJson);
        vm.writeFile(_capVaultsFilePath(), mergedJson);
    }

    function _readVaultConfig(string memory srcCapToken) internal view returns (VaultConfig memory vault) {
        return _readVaultConfig(block.chainid, srcCapToken);
    }

    function _readVaultConfig(string memory srcChainId, string memory srcCapToken)
        internal
        view
        returns (VaultConfig memory vault)
    {
        Vm vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
        return _readVaultConfig(vm.parseUint(srcChainId), srcCapToken);
    }

    function _readVaultConfig(uint256 srcChainId, string memory srcCapToken)
        internal
        view
        returns (VaultConfig memory vault)
    {
        Vm vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
        string memory json = vm.readFile(_capVaultsFilePath(srcChainId));
        string memory tokenPrefix = string.concat("$.", srcCapToken, ".");

        // FIXME: .length() doesn't seem to work
        //        https://crates.io/crates/jsonpath-rust

        address[] memory assets = new address[](100);
        address[] memory principalDebtTokens = new address[](100);
        address[] memory restakerDebtTokens = new address[](100);
        address[] memory interestDebtTokens = new address[](100);
        uint256 count = 0;
        for (uint256 i = 0; i < 100; i++) {
            string memory prefix = string.concat(tokenPrefix, "assets[", Strings.toString(i), "].");
            address asset = json.readAddressOr(string.concat(prefix, "asset.address"), address(0));
            if (asset == address(0)) {
                break;
            }
            assets[i] = asset;
            principalDebtTokens[i] = json.readAddress(string.concat(prefix, "principalDebtToken.address"));
            restakerDebtTokens[i] = json.readAddress(string.concat(prefix, "restakerDebtToken.address"));
            interestDebtTokens[i] = json.readAddress(string.concat(prefix, "interestDebtToken.address"));
            count = count + 1;
        }

        address[] memory trueAssets = new address[](count);
        address[] memory truePrincipalDebtTokens = new address[](count);
        address[] memory trueRestakerDebtTokens = new address[](count);
        address[] memory trueInterestDebtTokens = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            trueAssets[i] = assets[i];
            truePrincipalDebtTokens[i] = principalDebtTokens[i];
            trueRestakerDebtTokens[i] = restakerDebtTokens[i];
            trueInterestDebtTokens[i] = interestDebtTokens[i];
        }

        vault = VaultConfig({
            capToken: json.readAddress(string.concat(tokenPrefix, "['capToken'].address")),
            stakedCapToken: json.readAddress(string.concat(tokenPrefix, "['stakedCapToken'].address")),
            restakerInterestReceiver: json.readAddress(string.concat(tokenPrefix, "restakerInterestReceiver")),
            lzperiphery: VaultLzPeriphery({
                capOFTLockbox: json.readAddress(string.concat(tokenPrefix, "capOFTLockbox")),
                stakedCapOFTLockbox: json.readAddress(string.concat(tokenPrefix, "stakedCapOFTLockbox")),
                capZapComposer: json.readAddress(string.concat(tokenPrefix, "capZapComposer")),
                stakedCapZapComposer: json.readAddress(string.concat(tokenPrefix, "stakedCapZapComposer"))
            }),
            assets: trueAssets,
            principalDebtTokens: truePrincipalDebtTokens,
            restakerDebtTokens: trueRestakerDebtTokens,
            interestDebtTokens: trueInterestDebtTokens
        });
    }
}
