// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { StdCheats } from "forge-std/StdCheats.sol";
import { StdUtils } from "forge-std/StdUtils.sol";

contract RandomAssetUtils is StdUtils, StdCheats {
    address[] private assets;

    constructor(address[] memory _assets) {
        if (_assets.length == 0) {
            revert("No assets provided");
        }
        assets = _assets;
    }

    function randomAsset(uint256 assetIndexSeed) public view returns (address) {
        if (assets.length == 0) {
            return address(0);
        }
        return assets[bound(assetIndexSeed, 0, assets.length - 1)];
    }

    function randomAsset(address[] memory _assets, uint256 assetIndexSeed) public pure returns (address) {
        if (_assets.length == 0) {
            return address(0);
        }
        return _assets[bound(assetIndexSeed, 0, _assets.length - 1)];
    }

    function allAssets() public view returns (address[] memory) {
        return assets;
    }
}
