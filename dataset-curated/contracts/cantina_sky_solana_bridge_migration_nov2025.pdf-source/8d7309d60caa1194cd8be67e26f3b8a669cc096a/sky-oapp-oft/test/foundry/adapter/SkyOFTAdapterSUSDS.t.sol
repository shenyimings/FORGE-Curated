// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import { SkyOFTAdapterTest } from "./SkyOFTAdapter.t.sol";
import { SUsds } from "../mocks/SUsds.sol";
import { Vat } from "../mocks/vat.sol";
import { UsdsJoin } from "../mocks/UsdsJoin.sol";

contract SkyOFTAdapterSUSDSTest is SkyOFTAdapterTest {
    function setUpTokens() public override {
        Vat vat = new Vat();
        UsdsJoin usdsJoin = new UsdsJoin(address(vat), address(0));

        aToken = IERC20(address(new ERC1967Proxy(address(new SUsds(address(usdsJoin), address(0))), abi.encodeCall(SUsds.initialize, ()))));
        bToken = IERC20(address(new ERC1967Proxy(address(new SUsds(address(usdsJoin), address(0))), abi.encodeCall(SUsds.initialize, ()))));
        cToken = IERC20(address(new ERC1967Proxy(address(new SUsds(address(usdsJoin), address(0))), abi.encodeCall(SUsds.initialize, ()))));
    }
}
