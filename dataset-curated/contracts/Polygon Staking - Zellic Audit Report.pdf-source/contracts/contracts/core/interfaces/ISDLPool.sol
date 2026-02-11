// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

import "./IRewardsPoolController.sol";

interface ISDLPool is IRewardsPoolController {
    struct RESDLToken {
        uint256 amount;
        uint256 boostAmount;
        uint64 startTime;
        uint64 duration;
        uint64 expiry;
    }

    function effectiveBalanceOf(address _account) external view returns (uint256);

    function ownerOf(uint256 _lockId) external view returns (address);

    function getLockIdsByOwner(address _owner) external view returns (uint256[] memory);

    function supportedTokens() external view returns (address[] memory);
}
