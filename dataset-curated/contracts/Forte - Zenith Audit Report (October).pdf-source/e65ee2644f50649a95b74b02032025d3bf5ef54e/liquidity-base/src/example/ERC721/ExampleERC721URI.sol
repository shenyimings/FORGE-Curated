// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Descriptor} from "../../common/SVG/NFTSVG.sol";

contract ExampleERC721URI is ERC721 {
    address constant XTOKEN = address(0x2B0974b96511a728CA6342597471366D3444Aa2a); // USDC
    address constant YTOKEN = address(0x09D28d92a57a85aE4F49Fc8c7bA8893E1DbD612d); // WSTETH
    uint16 constant FEE = 100;
    address immutable POOL_MANAGER;

    uint256 public tokenId;
    constructor(string memory name, string memory symbol) ERC721(name, symbol) {
        POOL_MANAGER = address(this);
    }

    function mint(address to) public {
        tokenId++;
        _safeMint(to, tokenId);
    }

    function tokenURI(uint256 _tokenId) public view override returns (string memory) {
        return Descriptor.constructTokenURI(_tokenId, address(0xBABE666), false);
    }
}
