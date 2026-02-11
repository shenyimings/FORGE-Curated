// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

interface IERC20MintBurn is IERC20Metadata {
  function mint(address account, uint256 amount) external;
  function burn(address account, uint256 amount) external;
}
