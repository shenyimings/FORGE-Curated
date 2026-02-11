// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import { SUsdsL2 } from "../mocks/SUsdsL2.sol";
import { SkyOFTAdapterMintBurnTest } from "./SkyOFTAdapterMintBurn.t.sol";

contract SkyOFTAdapterMintBurnSUSDSL2Test is SkyOFTAdapterMintBurnTest {
    function setUpTokens() public override {
        aToken = IERC20(address(new ERC1967Proxy(address(new SUsdsL2()), abi.encodeCall(SUsdsL2.initialize, ()))));
        bToken = IERC20(address(new ERC1967Proxy(address(new SUsdsL2()), abi.encodeCall(SUsdsL2.initialize, ()))));
        cToken = IERC20(address(new ERC1967Proxy(address(new SUsdsL2()), abi.encodeCall(SUsdsL2.initialize, ()))));
    }

    function assignMintingRights() public override {
        SUsdsL2(address(aToken)).rely(address(aOFT));
        SUsdsL2(address(bToken)).rely(address(bOFT));
        SUsdsL2(address(cToken)).rely(address(cOFT));
    }
}
