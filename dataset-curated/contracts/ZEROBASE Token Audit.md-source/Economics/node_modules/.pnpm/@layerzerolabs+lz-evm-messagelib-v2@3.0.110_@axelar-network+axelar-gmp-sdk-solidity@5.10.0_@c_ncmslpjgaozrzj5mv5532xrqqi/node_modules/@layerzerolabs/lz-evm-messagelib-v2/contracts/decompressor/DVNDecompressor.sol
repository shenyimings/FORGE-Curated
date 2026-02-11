// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.22;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { DVN, ExecuteParam } from "../uln/dvn/DVN.sol";
import { DVNDecoder } from "./DVNDecoder.sol";
import { DecompressorExtension } from "./DecompressorExtension.sol";

struct TargetParam {
    uint8 idx;
    address addr;
}

struct DVNParam {
    uint16 idx;
    address addr;
}

contract DVNDecompressor is Ownable, DecompressorExtension {
    uint32 public immutable vid;

    mapping(uint16 index => address dvn) public dvns;
    mapping(uint8 index => address target) public targets;

    constructor(uint32 _vid, DVNParam[] memory _dvns, TargetParam[] memory _targets) {
        vid = _vid;

        for (uint256 i = 0; i < _dvns.length; i++) {
            DVNParam memory param = _dvns[i];
            dvns[param.idx] = param.addr;
        }

        for (uint256 i = 0; i < _targets.length; i++) {
            TargetParam memory param = _targets[i];
            targets[param.idx] = param.addr;
        }
    }

    function addTargets(TargetParam[] memory _targets) external onlyOwner {
        for (uint256 i = 0; i < _targets.length; i++) {
            targets[_targets[i].idx] = _targets[i].addr;
        }
    }

    function removeTargets(uint8[] memory _idx) external onlyOwner {
        for (uint256 i = 0; i < _idx.length; i++) {
            delete targets[_idx[i]];
        }
    }

    function addDVNs(DVNParam[] memory _dvns) external onlyOwner {
        for (uint256 i = 0; i < _dvns.length; i++) {
            dvns[_dvns[i].idx] = _dvns[i].addr;
        }
    }

    function removeDVNs(uint16[] memory _idx) external onlyOwner {
        for (uint256 i = 0; i < _idx.length; i++) {
            delete dvns[_idx[i]];
        }
    }

    function execute(bytes calldata _encoded) external onlyOwner {
        (uint16 dvnIndex, ExecuteParam[] memory params) = DVNDecoder.execute(_encoded, vid, targets);

        DVN(dvns[dvnIndex]).execute(params);
    }
}
