// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.7.6;
pragma abicoder v2;

import "../../PreCrimeView.sol";
import "./CounterView.sol";
import "./CounterV.sol";

contract CounterPrecrimeView is PreCrimeView {
    CounterView public counterView;

    uint16[] public remoteChainIds;
    bytes32[] public remotePrecrimeAddresses;

    struct SimulationResult {
        uint16 chainId;
        CounterView.CountState countState;
    }

    constructor(uint16 _localChainId, address _counterView) PreCrimeView(_localChainId) {
        counterView = CounterView(_counterView);
        maxBatchSize = 10;
    }

    function setRemotePrecrimeAddresses(
        uint16[] memory _remoteChainIds,
        bytes32[] memory _remotePrecrimeAddresses
    ) public onlyPrecrimeAdmin {
        require(_remoteChainIds.length == _remotePrecrimeAddresses.length, "Precrime: invalid size");
        remoteChainIds = _remoteChainIds;
        remotePrecrimeAddresses = _remotePrecrimeAddresses;
    }

    function setCounterView(address _counterView) public onlyPrecrimeAdmin {
        counterView = CounterView(_counterView);
    }

    function _simulate(Packet[] calldata _packets) internal view override returns (uint16 code, bytes memory data) {
        // get state from counter
        CounterView.CountState memory countState = counterView.getCountState(remoteChainIds);

        // simulate
        for (uint256 i = 0; i < _packets.length; i++) {
            Packet memory packet = _packets[i];
            countState = counterView.lzReceive(countState, packet.srcChainId);
        }

        // return simulation result
        return (CODE_SUCCESS, abi.encode(SimulationResult({chainId: localChainId, countState: countState})));
    }

    function _precrime(
        bytes[] memory _simulation
    ) internal view virtual override returns (uint16 code, bytes memory reason) {
        (SimulationResult memory localResult, SimulationResult[] memory results) = _getLocalSimulateResult(_simulation);

        uint sumOutboundCount = 0;
        // for each chainPathCount, find the chainPathCount and check the counts
        for (uint256 j = 0; j < localResult.countState.chainPathCounts.length; j++) {
            CounterView.ChainPathCount memory cpCount = localResult.countState.chainPathCounts[j];
            // find remote to local count state
            // should provide all peers simulated results
            CounterView.ChainPathCount memory remoteCp = _getRemoteCpCount(results, cpCount.eid);
            (code, reason) = _assertChainPathCount(cpCount, remoteCp);
            if (code != CODE_SUCCESS) {
                return (code, reason);
            }
            sumOutboundCount += remoteCp.outboundCount; // remote to local outbound count
        }
        (code, reason) = _assertTotalCount(localResult.countState, sumOutboundCount);
        if (code != CODE_SUCCESS) {
            return (code, reason);
        }

        return (CODE_SUCCESS, "");
    }

    function _getRemoteCpCount(
        SimulationResult[] memory _results,
        uint16 _remoteId
    ) internal view returns (CounterView.ChainPathCount memory) {
        uint localEid = localChainId;
        for (uint256 i = 0; i < _results.length; i++) {
            SimulationResult memory remoteResult = _results[i];
            if (remoteResult.chainId == _remoteId) {
                for (uint256 j = 0; j < remoteResult.countState.chainPathCounts.length; j++) {
                    CounterView.ChainPathCount memory cpCount = remoteResult.countState.chainPathCounts[j];
                    if (cpCount.eid == localEid) {
                        // find to localEid path
                        return cpCount;
                    }
                }
            }
        }
        revert("Precrime: count state not found");
    }

    function _getLocalSimulateResult(
        bytes[] memory _simulation
    ) internal view returns (SimulationResult memory localResult, SimulationResult[] memory results) {
        // decode results
        results = new SimulationResult[](_simulation.length);
        for (uint256 i = 0; i < _simulation.length; i++) {
            results[i] = abi.decode(_simulation[i], (SimulationResult));
            if (results[i].chainId == localChainId) {
                localResult = results[i];
            }
        }
    }

    function _assertChainPathCount(
        CounterView.ChainPathCount memory _localCpCount,
        CounterView.ChainPathCount memory _remoteCpCount
    ) internal pure returns (uint16 code, bytes memory reason) {
        if (_localCpCount.inboundCount > _remoteCpCount.outboundCount) {
            return (CODE_PRECRIME_FAILURE, "Precrime: inboundCount > outboundCount");
        }
        if (_localCpCount.outboundCount > _remoteCpCount.inboundCount) {
            return (CODE_PRECRIME_FAILURE, "Precrime: outboundCount > inboundCount");
        }
        return (CODE_SUCCESS, "");
    }

    function _assertTotalCount(
        CounterView.CountState memory _localCount,
        uint _sumOutbound
    ) internal pure returns (uint16 code, bytes memory reason) {
        if (_localCount.totalCount > _sumOutbound) {
            return (CODE_PRECRIME_FAILURE, "Precrime: totalCount > sum outboundCount");
        }
        return (CODE_SUCCESS, "");
    }

    function _remotePrecrimeAddress(
        Packet[] calldata _packets
    ) internal view override returns (uint16[] memory chainIds, bytes32[] memory precrimeAddresses) {
        if (_packets.length == 0) {
            return (remoteChainIds, remotePrecrimeAddresses);
        }

        // only return related remotes
        uint16 size = _getRelatedRemoteSize(_packets);
        if (size > 0) {
            chainIds = new uint16[](size);
            uint256 k = 0;
            precrimeAddresses = new bytes32[](size);
            for (uint16 i = 0; i < remoteChainIds.length; i++) {
                for (uint16 j = 0; j < _packets.length; j++) {
                    uint16 srcChainId = _packets[j].srcChainId;
                    if (remoteChainIds[i] == srcChainId) {
                        chainIds[k] = srcChainId;
                        precrimeAddresses[k] = remotePrecrimeAddresses[i];
                        k++;
                        break;
                    }
                }
            }
        }
    }

    function _getRelatedRemoteSize(Packet[] memory _packets) internal view returns (uint16 size) {
        for (uint16 i = 0; i < remoteChainIds.length; i++) {
            for (uint16 j = 0; j < _packets.length; j++) {
                if (remoteChainIds[i] == _packets[j].srcChainId) {
                    size++;
                    break;
                }
            }
        }
    }

    function _getInboundNonce(Packet memory packet) internal view override returns (uint64) {
        CounterV counter = counterView.counter();
        return counter.getInboundNonce(packet.srcChainId);
    }
}
