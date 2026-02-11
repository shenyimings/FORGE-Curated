// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IBeaconBase } from '../../lib/proxy/IBeaconBase.sol';

interface IHubAssetFactory is IBeaconBase {
  function create(address owner_, address supplyManager, string memory name, string memory symbol, uint8 decimals)
    external
    returns (address);

  function callBeacon(bytes calldata data) external returns (bytes memory);
}
