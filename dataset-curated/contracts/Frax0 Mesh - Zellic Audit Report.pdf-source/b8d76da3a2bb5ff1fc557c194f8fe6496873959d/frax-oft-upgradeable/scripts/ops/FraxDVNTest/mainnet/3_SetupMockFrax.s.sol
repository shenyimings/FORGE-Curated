// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/StdJson.sol";
import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";
import { Constant } from "@fraxfinance/layerzero-v2-upgradeable/messagelib/test/util/Constant.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

contract SetupMockFrax is DeployFraxOFTProtocol {
    using Strings for uint256;
    using stdJson for string;

    function loadJsonConfig() public override {
        delete expectedProxyOfts;

        super.loadJsonConfig();

        if (broadcastConfig.chainid == 59144) {
            // linea, eid = 30183
            connectedOfts[0] = 0x6185334f1542a9966CbaD694577fFbede3DD1f1F;
            proxyOfts.push(0x6185334f1542a9966CbaD694577fFbede3DD1f1F);
            expectedProxyOfts.push(0x6185334f1542a9966CbaD694577fFbede3DD1f1F);
        } else if (broadcastConfig.chainid == 2741) {
            // abstract, eid = 30324
            connectedOfts[0] = 0xBd39033994F5324Fe8D50bB524396A78ff9dFe22;
            proxyOfts.push(0xBd39033994F5324Fe8D50bB524396A78ff9dFe22);
            expectedProxyOfts.push(0xBd39033994F5324Fe8D50bB524396A78ff9dFe22);
        } else if (broadcastConfig.chainid == 324) {
            // zksync, eid = 30165
            connectedOfts[0] = 0x3Fc877008e396FdD7f9Ee3Deb2e8A54d54da705A;
            proxyOfts.push(0x3Fc877008e396FdD7f9Ee3Deb2e8A54d54da705A);
            expectedProxyOfts.push(0x3Fc877008e396FdD7f9Ee3Deb2e8A54d54da705A);
        } else {
            // 1,81457,8453,34443,1329,252,196,146,57073,42161,10,137,43114,56,1101,80094,480,130,98866
            connectedOfts[0] = 0x57558Cb8d6005DE0BAe8a2789d5EfaaE52dba5a8;
            proxyOfts.push(0x57558Cb8d6005DE0BAe8a2789d5EfaaE52dba5a8);
            expectedProxyOfts.push(0x57558Cb8d6005DE0BAe8a2789d5EfaaE52dba5a8);
        }
    }

    function run() public override {
        setupSource();
    }

    function setupNonEvms() public override {}

    function setPeer(L0Config memory _config, address _connectedOft, bytes32 _peerOftAsBytes32) public override {
        if (hasNoPeer(_connectedOft, _config, _peerOftAsBytes32)) {
            super.setPeer(_config, _connectedOft, _peerOftAsBytes32);
        }
    }

    function determinePeer(uint256 _chainid, address, address[] memory) public pure override returns (address peer) {
        if (_chainid == 59144) {
            // linea
            peer = 0x6185334f1542a9966CbaD694577fFbede3DD1f1F;
        } else if (_chainid == 2741) {
            // abstract
            peer = 0xBd39033994F5324Fe8D50bB524396A78ff9dFe22;
        } else if (_chainid == 324) {
            // zksync
            peer = 0x3Fc877008e396FdD7f9Ee3Deb2e8A54d54da705A;
        } else {
            // 1,81457,8453,34443,1329,252,196,146,57073,42161,10,137,43114,56,1101,80094,480,130,98866
            peer = 0x57558Cb8d6005DE0BAe8a2789d5EfaaE52dba5a8;
        }
    }

    function setPriviledgedRoles() public override {}

    function setLib(L0Config memory _connectedConfig, address _connectedOft, L0Config memory _config) public override {
        if (_config.eid == 30168) return;
        if (_config.eid == 30151) return;
        if (_connectedConfig.eid == 30370) {
            // if broadcast config is plumephoenix,
            // skip x-layer (30274), polygon zkevm (30158), worldchain (30319), zksync (30165), movement (30325)
            // and aptos (30108)
            if (
                _config.eid == 30274 ||
                _config.eid == 30158 ||
                _config.eid == 30319 ||
                _config.eid == 30165 ||
                _config.eid == 30325 ||
                _config.eid == 30108
            ) return;
        }
        if (_config.eid != 30370) return;
        // TODO : only set library if it is not same as config
        super.setLib(_connectedConfig, _connectedOft, _config);
    }

    function setConfig(
        L0Config memory _srcConfig,
        L0Config memory _dstConfig,
        address _lib,
        address _oft
    ) public override {
        if (_dstConfig.eid == 30168) return;
        if (_dstConfig.eid == 30151) return;

        if (_srcConfig.eid == 30370) {
            // L0 team has not setup defaultSendLibrary and defaultReceiveLibrary on plumephoenix for
            // 30274 (x-layer), polygon zkevm (30158), worldchain (30319), zksync (30165), movement (30325)
            // and aptos (30108)
            if (
                _dstConfig.eid == 30274 ||
                _dstConfig.eid == 30158 ||
                _dstConfig.eid == 30319 ||
                _dstConfig.eid == 30165 ||
                _dstConfig.eid == 30325 ||
                _dstConfig.eid == 30108
            ) return;
        }

        if (_dstConfig.eid != 30370) return;
        super.setConfig(_srcConfig, _dstConfig, _lib, _oft);
    }

    function getDvnStack(
        uint256 _srcChainId,
        uint256 _dstChainId
    ) public view override returns (DvnStack memory dvnStack) {
        require(_srcChainId != _dstChainId, "_srcChainId == _dstChainId"); // cannot set dvn options to self

        // if (_srcChainId == 1088) return dvnStack;
        // if (_dstChainId == 1088) return dvnStack;
        // if (_srcChainId == 111111111) return dvnStack;
        // if (_dstChainId == 111111111) return dvnStack;
        // if (_srcChainId == 22222222) return dvnStack;
        // if (_dstChainId == 22222222) return dvnStack;
        // if (_srcChainId == 33333333) return dvnStack;
        // if (_dstChainId == 33333333) return dvnStack;
        // if (_dstChainId != 98866) return dvnStack;

        // craft path
        string memory root = vm.projectRoot();
        root = string.concat(root, "/config/dvn/");
        string memory name = string.concat(_srcChainId.toString(), ".json");
        string memory path = string.concat(root, name);

        // load json
        string memory jsonFile = vm.readFile(path);

        // NOTE: a missing key will cause this decoding to revert
        string memory key = string.concat(".", _dstChainId.toString());
        dvnStack = abi.decode(jsonFile.parseRaw(key), (DvnStack));
    }

    function hasNoPeer(
        address _oft,
        L0Config memory _dstConfig,
        bytes32 _peerOftAsBytes32
    ) internal view returns (bool) {
        bytes32 peer = IOAppCore(_oft).peers(uint32(_dstConfig.eid));
        return peer != _peerOftAsBytes32;
    }
}
