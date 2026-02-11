pragma solidity ^0.8.0;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";

contract CheckSolanaPeers is DeployFraxOFTProtocol {
    function run() public override {
        for (uint256 i=0; i<expectedProxyOfts.length; i++) {
            proxyOfts.push(expectedProxyOfts[i]);
        }

        for (uint256 i=0; i<proxyConfigs.length; i++) {
            L0Config memory config = proxyConfigs[i];
            checkPeer(config);
        }
    }

    function checkPeer(L0Config memory _config) public simulateAndWriteTxs(_config) {
        address oft = connectedOfts[0];
        if (hasPeer(oft, uint32(30168))) {
            console.log(
                "Chain ID %s has peer",
                _config.chainid
            );
        }
    }

    function hasPeer(address _oft, uint32 _dstEid) internal view returns (bool) {
        bytes32 peer = IOAppCore(_oft).peers(_dstEid);
        return peer != bytes32(0);
    }
}