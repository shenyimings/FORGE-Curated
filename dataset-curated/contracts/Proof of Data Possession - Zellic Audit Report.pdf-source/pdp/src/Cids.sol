// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

library Cids {
    // TODO PERF: https://github.com/FILCAT/pdp/issues/16#issuecomment-2329836995
    struct Cid {
        bytes data;
    }

    // Returns the last 32 bytes of a CID payload as a bytes32.
    function digestFromCid(Cid memory cid) internal pure returns (bytes32) {
        require(cid.data.length >= 32, "Cid data is too short");
        bytes memory dataSlice = new bytes(32);
        for (uint i = 0; i < 32; i++) {
            dataSlice[i] = cid.data[cid.data.length - 32 + i];
        }
        return bytes32(dataSlice);
    }

    // Makes a CID from a prefix and a digest.
    // The prefix doesn't matter to these contracts, which only inspect the last 32 bytes (the hash digest).
    function cidFromDigest(bytes memory prefix, bytes32 digest) internal pure returns (Cids.Cid memory) {
        bytes memory byteArray = new bytes(prefix.length + 32);
        for (uint256 i = 0; i < prefix.length; i++) {
            byteArray[i] = prefix[i];
        }
        for (uint256 i = 0; i < 32; i++) {
            byteArray[i+prefix.length] = bytes1(digest << (i * 8));
        }
        return Cids.Cid(byteArray);
    }
}
