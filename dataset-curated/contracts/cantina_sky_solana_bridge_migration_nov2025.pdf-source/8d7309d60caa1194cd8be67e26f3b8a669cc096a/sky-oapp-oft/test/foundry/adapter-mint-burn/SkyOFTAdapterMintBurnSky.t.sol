// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { Sky } from "../mocks/Sky.sol";
import { SkyOFTAdapterMintBurnTest } from "./SkyOFTAdapterMintBurn.t.sol";

contract SkyOFTAdapterMintBurnSkyTest is SkyOFTAdapterMintBurnTest {
    function setUpTokens() public override {
        aToken = IERC20(address(new Sky()));
        bToken = IERC20(address(new Sky()));
        cToken = IERC20(address(new Sky()));
    }

    function assignMintingRights() public override {
        // Grant minting permissions to the adapters for Sky tokens
        Sky(address(aToken)).rely(address(aOFT));
        Sky(address(bToken)).rely(address(bOFT));
        Sky(address(cToken)).rely(address(cOFT));
    }
}
