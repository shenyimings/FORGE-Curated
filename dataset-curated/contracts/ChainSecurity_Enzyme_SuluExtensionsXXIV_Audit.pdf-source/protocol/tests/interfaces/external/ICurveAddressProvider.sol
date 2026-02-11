// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.6.0 <0.9.0;

interface ICurveAddressProvider {
    function get_address(uint256 _id) external view returns (address contractAddress_);
}
