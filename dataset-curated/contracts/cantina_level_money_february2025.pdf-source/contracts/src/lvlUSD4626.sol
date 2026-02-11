// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract lvlUSD4626 is ERC4626 {
    constructor(ERC20 _lvlusd) ERC4626(_lvlusd) ERC20("Level USD XP Vault", "xplvlUSD") {}
}
