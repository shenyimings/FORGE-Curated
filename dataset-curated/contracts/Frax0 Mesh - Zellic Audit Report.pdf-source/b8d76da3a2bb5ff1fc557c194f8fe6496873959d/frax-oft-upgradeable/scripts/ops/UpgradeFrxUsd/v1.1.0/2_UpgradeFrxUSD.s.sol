// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";

contract UpgradeFrxUSD is DeployFraxOFTProtocol {
    using stdJson for string;
    using Strings for uint256;

    constructor() {
        
    }
}