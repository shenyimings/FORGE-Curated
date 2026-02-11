// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.6.0 <0.9.0;

interface ITheGraphController {
    function getContractProxy(bytes32 _id) external view returns (address contractProxyAddress_);

    function getGovernor() external view returns (address governorAddress_);
}
