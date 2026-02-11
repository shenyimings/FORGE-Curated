// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

import { Test } from '@std/Test.sol';

import { Strings } from '@oz/utils/Strings.sol';

// https://github.com/Se7en-Seas/boring-vault/blob/main/test/resources/MerkleTreeHelper/MerkleTreeHelper.sol
contract MerkleTreeHelper is Test {
  struct ManageLeaf {
    address target;
    bool canSendValue;
    string signature;
    address[] argumentAddresses;
    string description;
    address decoderAndSanitizer;
  }

  uint256 leafIndex = type(uint256).max;

  function _generateMerkleTree(ManageLeaf[] memory manageLeafs) internal pure returns (bytes32[][] memory tree) {
    uint256 leafsLength = manageLeafs.length;
    bytes32[][] memory leafs = new bytes32[][](1);
    leafs[0] = new bytes32[](leafsLength);
    for (uint256 i; i < leafsLength; ++i) {
      bytes4 selector = bytes4(keccak256(abi.encodePacked(manageLeafs[i].signature)));
      bytes memory rawDigest = abi.encodePacked(
        manageLeafs[i].decoderAndSanitizer, manageLeafs[i].target, manageLeafs[i].canSendValue, selector
      );
      uint256 argumentAddressesLength = manageLeafs[i].argumentAddresses.length;
      for (uint256 j; j < argumentAddressesLength; ++j) {
        rawDigest = abi.encodePacked(rawDigest, manageLeafs[i].argumentAddresses[j]);
      }
      leafs[0][i] = keccak256(rawDigest);
    }
    tree = _buildTrees(leafs);
  }

  function _buildTrees(bytes32[][] memory merkleTreeIn) internal pure returns (bytes32[][] memory merkleTreeOut) {
    // We are adding another row to the merkle tree, so make merkleTreeOut be 1 longer.
    uint256 merkleTreeIn_length = merkleTreeIn.length;
    merkleTreeOut = new bytes32[][](merkleTreeIn_length + 1);
    uint256 layer_length;
    // Iterate through merkleTreeIn to copy over data.
    for (uint256 i; i < merkleTreeIn_length; ++i) {
      layer_length = merkleTreeIn[i].length;
      merkleTreeOut[i] = new bytes32[](layer_length);
      for (uint256 j; j < layer_length; ++j) {
        merkleTreeOut[i][j] = merkleTreeIn[i][j];
      }
    }

    uint256 next_layer_length;
    if (layer_length % 2 != 0) {
      next_layer_length = (layer_length + 1) / 2;
    } else {
      next_layer_length = layer_length / 2;
    }
    merkleTreeOut[merkleTreeIn_length] = new bytes32[](next_layer_length);
    uint256 count;
    for (uint256 i; i < layer_length; i += 2) {
      merkleTreeOut[merkleTreeIn_length][count] =
        _hashPair(merkleTreeIn[merkleTreeIn_length - 1][i], merkleTreeIn[merkleTreeIn_length - 1][i + 1]);
      count++;
    }

    if (next_layer_length > 1) {
      // We need to process the next layer of leaves.
      merkleTreeOut = _buildTrees(merkleTreeOut);
    }
  }

  function _generateLeafs(
    string memory filePath,
    ManageLeaf[] memory leafs,
    bytes32 manageRoot,
    bytes32[][] memory manageTree,
    //
    address strategyExecutor,
    address decoderAndSanitizer,
    address manager
  ) internal {
    if (vm.exists(filePath)) {
      // Need to delete it
      vm.removeFile(filePath);
    }
    vm.writeLine(filePath, '{ \"metadata\": ');
    string[] memory composition = new string[](5);
    composition[0] = 'Bytes20(DECODER_AND_SANITIZER_ADDRESS)';
    composition[1] = 'Bytes20(TARGET_ADDRESS)';
    composition[2] = 'Bytes1(CAN_SEND_VALUE)';
    composition[3] = 'Bytes4(TARGET_FUNCTION_SELECTOR)';
    composition[4] = 'Bytes{N*20}(ADDRESS_ARGUMENT_0,...,ADDRESS_ARGUMENT_N)';
    string memory metadata = 'ManageRoot';
    {
      // Determine how many leafs are used.
      uint256 usedLeafCount;
      for (uint256 i; i < leafs.length; ++i) {
        if (leafs[i].target != address(0)) {
          usedLeafCount++;
        }
      }
      vm.serializeUint(metadata, 'LeafCount', usedLeafCount);
    }
    vm.serializeUint(metadata, 'TreeCapacity', leafs.length);
    vm.serializeAddress(metadata, 'StrategyExecutor', strategyExecutor);
    vm.serializeAddress(metadata, 'DecoderAndSanitizerAddress', decoderAndSanitizer);
    vm.serializeAddress(metadata, 'ManagerAddress', manager);
    string memory finalMetadata = vm.serializeBytes32(metadata, 'ManageRoot', manageRoot);

    vm.writeLine(filePath, finalMetadata);
    vm.writeLine(filePath, ',');
    vm.writeLine(filePath, '\"leafs\": [');

    for (uint256 i; i < leafs.length; ++i) {
      string memory leaf = 'leaf';
      vm.serializeAddress(leaf, 'TargetAddress', leafs[i].target);
      vm.serializeAddress(leaf, 'DecoderAndSanitizerAddress', leafs[i].decoderAndSanitizer);
      vm.serializeBool(leaf, 'CanSendValue', leafs[i].canSendValue);
      vm.serializeString(leaf, 'FunctionSignature', leafs[i].signature);
      bytes4 sel = bytes4(keccak256(abi.encodePacked(leafs[i].signature)));
      string memory selector = Strings.toHexString(uint32(sel), 4);
      vm.serializeString(leaf, 'FunctionSelector', selector);
      bytes memory packedData;
      for (uint256 j; j < leafs[i].argumentAddresses.length; ++j) {
        packedData = abi.encodePacked(packedData, leafs[i].argumentAddresses[j]);
      }
      vm.serializeBytes(leaf, 'PackedArgumentAddresses', packedData);
      vm.serializeAddress(leaf, 'AddressArguments', leafs[i].argumentAddresses);
      bytes32 digest = keccak256(
        abi.encodePacked(leafs[i].decoderAndSanitizer, leafs[i].target, leafs[i].canSendValue, sel, packedData)
      );
      vm.serializeBytes32(leaf, 'LeafDigest', digest);

      string memory finalJson = vm.serializeString(leaf, 'Description', leafs[i].description);

      // vm.writeJson(finalJson, filePath);
      vm.writeLine(filePath, finalJson);
      if (i != leafs.length - 1) {
        vm.writeLine(filePath, ',');
      }
    }
    vm.writeLine(filePath, '],');

    string memory merkleTreeName = 'MerkleTree';
    string[][] memory merkleTree = new string[][](manageTree.length);
    for (uint256 k; k < manageTree.length; ++k) {
      merkleTree[k] = new string[](manageTree[k].length);
    }

    for (uint256 i; i < manageTree.length; ++i) {
      for (uint256 j; j < manageTree[i].length; ++j) {
        merkleTree[i][j] = vm.toString(manageTree[i][j]);
      }
    }

    string memory finalMerkleTree;
    for (uint256 i; i < merkleTree.length; ++i) {
      string memory layer = Strings.toString(merkleTree.length - (i + 1));
      finalMerkleTree = vm.serializeString(merkleTreeName, layer, merkleTree[i]);
    }
    vm.writeLine(filePath, '\"MerkleTree\": ');
    vm.writeLine(filePath, finalMerkleTree);
    vm.writeLine(filePath, '}');
  }

  function _getProofsUsingTree(ManageLeaf[] memory manageLeafs, bytes32[][] memory tree, address decoderAndSanitizer)
    internal
    pure
    returns (bytes32[][] memory proofs)
  {
    proofs = new bytes32[][](manageLeafs.length);
    for (uint256 i; i < manageLeafs.length; ++i) {
      if (manageLeafs[i].decoderAndSanitizer == address(0)) continue;
      // Generate manage proof.
      bytes4 selector = bytes4(keccak256(abi.encodePacked(manageLeafs[i].signature)));
      bytes memory rawDigest =
        abi.encodePacked(decoderAndSanitizer, manageLeafs[i].target, manageLeafs[i].canSendValue, selector);
      uint256 argumentAddressesLength = manageLeafs[i].argumentAddresses.length;
      for (uint256 j; j < argumentAddressesLength; ++j) {
        rawDigest = abi.encodePacked(rawDigest, manageLeafs[i].argumentAddresses[j]);
      }
      bytes32 leaf = keccak256(rawDigest);
      proofs[i] = _generateProof(leaf, tree);
    }
  }

  function _generateProof(bytes32 leaf, bytes32[][] memory tree) internal pure returns (bytes32[] memory proof) {
    // The length of each proof is the height of the tree - 1.
    uint256 tree_length = tree.length;
    proof = new bytes32[](tree_length - 1);

    // Build the proof
    for (uint256 i; i < tree_length - 1; ++i) {
      // For each layer we need to find the leaf.
      for (uint256 j; j < tree[i].length; ++j) {
        if (leaf == tree[i][j]) {
          // We have found the leaf, so now figure out if the proof needs the next leaf or the previous one.
          proof[i] = j % 2 == 0 ? tree[i][j + 1] : tree[i][j - 1];
          leaf = _hashPair(leaf, proof[i]);
          break;
        } else if (j == tree[i].length - 1) {
          // We have reached the end of the layer and have not found the leaf.
          revert('Leaf not found in tree');
        }
      }
    }
  }

  function _hashPair(bytes32 a, bytes32 b) private pure returns (bytes32) {
    return a < b ? _efficientHash(a, b) : _efficientHash(b, a);
  }

  function _efficientHash(bytes32 a, bytes32 b) private pure returns (bytes32 value) {
    /// @solidity memory-safe-assembly
    assembly {
      mstore(0x00, a)
      mstore(0x20, b)
      value := keccak256(0x00, 0x40)
    }
  }
}
