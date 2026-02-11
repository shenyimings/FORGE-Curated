// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

interface IAuraBoosterBase {
    function deposit(uint256 _pid, uint256 _amount, bool _stake) external returns(bool);
}

interface IAuraBooster is IAuraBoosterBase {
    function stakerRewards() external view returns(address);
}

interface IAuraBoosterLite is IAuraBoosterBase {
    function crv() external view returns(address);
    function rewards() external view returns(address);
}

interface IAuraRewardPool is IERC4626 {
    function withdrawAndUnwrap(uint256 amount, bool claim) external returns(bool);
    function getReward(address _account, bool _claimExtras) external returns(bool);
    function balanceOf(address _account) external view returns(uint256);
    function pid() external view returns(uint256);
    function operator() external view returns(address);
}

