/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {PoolFOTTokenTest} from "liquidity-base/test/amm/PoolFOTToken.t.sol";
import {ALTBCPoolCommonImpl} from "test/amm/common/ALTBCPoolCommonImpl.sol";

/**
 * @title Test ALTBC FOT Pool functionality
 * @dev unit test
 * @author @oscarsernarosero @mpetersoCode55 @cirsteve @palmerg4
 */
contract ALTBCPoolFOTTest is PoolFOTTokenTest, ALTBCPoolCommonImpl {}
