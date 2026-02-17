// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { ILayerZeroEndpointV2 } from "@layerzerolabs/interfaces/ILayerZeroEndpointV2.sol";

import { stdJson } from "forge-std/StdJson.sol";
import { Vm } from "forge-std/Vm.sol";
import { console } from "forge-std/console.sol";

struct LzAddressbook {
    uint32 eid;
    ILayerZeroEndpointV2 endpointV2;
    address executor;
    uint32 nativeChainId;
    address receiveUln301;
    address receiveUln302;
    address sendUln301;
    address sendUln302;
}

contract LzUtils {
    using stdJson for string;

    string public constant LZ_CONFIG_PATH_FROM_PROJECT_ROOT = "config/layerzero-v2-deployments.json";

    /**
     * @dev Converts an address to bytes32.
     * @param _addr The address to convert.
     * @return The bytes32 representation of the address.
     */
    function addressToBytes32(address _addr) public pure returns (bytes32) {
        return bytes32(uint256(uint160(_addr)));
    }

    /**
     * @dev Constructs a key for accessing a field in a JSON object.
     * @param vm The Vm instance.
     * @param chainId The chain ID.
     * @param _field The field name.
     * @return key The constructed key.
     */
    function _fieldKey(Vm vm, uint chainId, string memory _field) private pure returns (string memory key) {
        key = string.concat("$['", vm.toString(chainId), "'].", _field);
    }

    /**
     * @dev Retrieves the LayerZero configuration for the current chain ID.
     * @return addressbook The LayerZero addressbook.
     */
    function _getLzAddressbook() internal view returns (LzAddressbook memory addressbook) {
        addressbook = _getLzAddressbook(block.chainid);
    }

    /**
     * @dev Retrieves the LayerZero configuration for a given chain ID.
     * @param chainId The chain ID.
     * @return addressbook The LayerZero addressbook.
     */
    function _getLzAddressbook(uint chainId) internal view returns (LzAddressbook memory addressbook) {
        Vm vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/", LZ_CONFIG_PATH_FROM_PROJECT_ROOT);
        string memory json = vm.readFile(path);

        addressbook.eid = uint32(json.readUint(_fieldKey(vm, chainId, "eid")));
        addressbook.endpointV2 = ILayerZeroEndpointV2(json.readAddress(_fieldKey(vm, chainId, "endpointV2")));
        addressbook.executor = json.readAddress(_fieldKey(vm, chainId, "executor"));
        addressbook.nativeChainId = uint32(json.readUint(_fieldKey(vm, chainId, "nativeChainId")));
        addressbook.receiveUln301 = json.readAddress(_fieldKey(vm, chainId, "receiveUln301"));
        addressbook.receiveUln302 = json.readAddress(_fieldKey(vm, chainId, "receiveUln302"));
        addressbook.sendUln301 = json.readAddress(_fieldKey(vm, chainId, "sendUln301"));
        addressbook.sendUln302 = json.readAddress(_fieldKey(vm, chainId, "sendUln302"));
    }
}
