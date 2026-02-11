// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { Sky } from "../mocks/Sky.sol";
import { SkyOFTAdapterTest } from "./SkyOFTAdapter.t.sol";

contract SkyOFTAdapterSkyTest is SkyOFTAdapterTest {
    function setUpTokens() public override {
        aToken = IERC20(address(new Sky()));
        bToken = IERC20(address(new Sky()));
        cToken = IERC20(address(new Sky()));
    }
}
