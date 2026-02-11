// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import { Usds } from "../mocks/Usds.sol";
import { SkyOFTAdapterMintBurnTest } from "./SkyOFTAdapterMintBurn.t.sol";

contract SkyOFTAdapterMintBurnUSDSTest is SkyOFTAdapterMintBurnTest {
    function setUpTokens() public override {
        aToken = IERC20(address(new ERC1967Proxy(address(new Usds()), abi.encodeCall(Usds.initialize, ()))));
        bToken = IERC20(address(new ERC1967Proxy(address(new Usds()), abi.encodeCall(Usds.initialize, ()))));
        cToken = IERC20(address(new ERC1967Proxy(address(new Usds()), abi.encodeCall(Usds.initialize, ()))));
    }

    function assignMintingRights() public override {
        // Grant minting permissions to the adapters for USDS tokens
        Usds(address(aToken)).rely(address(aOFT));
        Usds(address(bToken)).rely(address(bOFT));
        Usds(address(cToken)).rely(address(cOFT));
    }
}
