// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;
 
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {OFT} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/OFT.sol";
 
contract ZEROBASE is OFT {
    uint256 public constant INITIAL_SUPPLY = 1000000000 * 10 ** 18;
    constructor(
        address _lzEndpoint,
        address _owner,
        address _receiver
    ) OFT("ZEROBASE Token", "ZBT", _lzEndpoint, _owner) Ownable(_owner) {
        _mint(_receiver, INITIAL_SUPPLY);
    }
}
