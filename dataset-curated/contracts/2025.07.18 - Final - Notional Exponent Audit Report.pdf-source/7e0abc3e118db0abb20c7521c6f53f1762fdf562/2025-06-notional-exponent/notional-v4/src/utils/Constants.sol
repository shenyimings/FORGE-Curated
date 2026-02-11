// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

import {WETH9} from "../interfaces/IWETH.sol";
import {AddressRegistry} from "../proxy/AddressRegistry.sol";

address constant ETH_ADDRESS = address(0);
address constant ALT_ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
uint256 constant DEFAULT_PRECISION = 1e18;
uint256 constant DEFAULT_DECIMALS = 18;

uint256 constant COOLDOWN_PERIOD = 5 minutes;
uint256 constant YEAR = 365 days;



// TODO: move these to a deployment file
uint256 constant CHAIN_ID_MAINNET = 1;
WETH9 constant WETH = WETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
AddressRegistry constant ADDRESS_REGISTRY = AddressRegistry(0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f);