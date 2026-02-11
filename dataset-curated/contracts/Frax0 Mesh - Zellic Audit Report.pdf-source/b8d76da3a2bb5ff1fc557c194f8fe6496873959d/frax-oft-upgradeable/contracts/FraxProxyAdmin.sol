// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { ProxyAdmin } from "@fraxfinance/layerzero-v2-upgradeable/messagelib/contracts/upgradeable/proxy/ProxyAdmin.sol";

contract FraxProxyAdmin is ProxyAdmin {
    constructor(address _admin) ProxyAdmin(_admin) {}
}