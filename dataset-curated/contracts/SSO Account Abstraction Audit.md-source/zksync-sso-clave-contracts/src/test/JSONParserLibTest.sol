// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { JSONParserLib } from "solady/src/utils/JSONParserLib.sol";

contract JSONParserLibTest {
  function parse(string calldata json) external pure returns (JSONParserLib.Item memory) {
    return JSONParserLib.parse(json);
  }
}
