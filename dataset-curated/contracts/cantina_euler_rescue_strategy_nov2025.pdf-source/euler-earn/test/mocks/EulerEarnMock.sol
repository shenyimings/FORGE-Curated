// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.26;

import "../../src/EulerEarn.sol";

contract EulerEarnMock is EulerEarn {
    constructor(
        address owner,
        address evc,
        address permit2,
        uint256 initialTimelock,
        address _asset,
        string memory __name,
        string memory __symbol
    ) EulerEarn(owner, evc, permit2, initialTimelock, _asset, __name, __symbol) {}

    function mockSetCap(IERC4626 id, uint136 supplyCap) external {
        _setCap(id, supplyCap);
    }

    function mockSimulateWithdrawStrategy(uint256 assets) external view returns (uint256) {
        return _simulateWithdrawStrategy(assets);
    }

    function mockSetSupplyQueue(IERC4626[] memory ids) external {
        supplyQueue = ids;
    }
}
