// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.6.0 <0.9.0;

interface IMorphoMorpho {
    function owner() external view returns (address owner_);

    function setIsSupplyPaused(address _poolToken, bool _isPaused) external;
}
