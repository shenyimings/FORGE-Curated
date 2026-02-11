// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { SkyOFTAdapterTest } from "./SkyOFTAdapter.t.sol";
import { SDAO } from "../mocks/SDAO.sol";

contract SkyOFTAdapterSDAOTest is SkyOFTAdapterTest {
    function setUpTokens() public override {
        aToken = IERC20(address(new SDAO("SDAO", "SDAO")));
        bToken = IERC20(address(new SDAO("SDAO", "SDAO")));
        cToken = IERC20(address(new SDAO("SDAO", "SDAO")));
    }
}
