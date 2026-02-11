// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.20;

contract PermissionControl {
    address private administrator_;
    // todo add grants admin
    address [] private grantees_;

    constructor() {
        administrator_ = msg.sender;
    }

    function checkSuperPermission(address _addr) internal view returns(bool) {
        if (_addr == administrator_ || _addr == address(0)) {
            return true;
        }

        return false;
    }

    function checkAdminPermission(address _addr) internal view returns(bool) {
        if (checkSuperPermission(_addr) || checkGrantPermission(_addr)) {
            return true;
        }

        return false;
    }

    function checkGrantPermission(address _addr) internal view returns(bool) {
        for (uint256 i = 0; i < grantees_.length; i++) {
            if (grantees_[i] == _addr) {
                return true;
            }
        }

        return false;
    }

    event SuperTransferred(
        address old_administrator_,
        address new_administrator_
    );
    function tranferSuperAdmin(address _new_admin) external {
        require(checkSuperPermission(msg.sender), "Permission denied");
        require(administrator_ != _new_admin, "Permission denied, same address");

        address old_admin = administrator_;
        administrator_ = _new_admin;
        emit SuperTransferred(old_admin, _new_admin);
    }

    // return administrator_
    function getSuperAdmin() public view returns (address) {
        return administrator_;
    }

    // return administrator_
    function getGranteeAdmin() public view returns ( address[] memory) {
        return grantees_;
    }

    event AdminGranted(
        address grantee
    );
    function grantAdmin(address _addr) external {
        require(checkSuperPermission(msg.sender), "Permission denied");
        require(!checkGrantPermission(_addr), "Address already exist in grantees");

        grantees_.push(_addr);
        emit AdminGranted(_addr);
    }
    event AdminRevoked(
        address revoker
    );
    function revokeAdmin(address _addr) external {
        require(checkSuperPermission(msg.sender), "Permission denied");
        require(checkGrantPermission(_addr), "Address not exist in grantees");

        for (uint256 i = 0; i < grantees_.length; i++) {
            if (grantees_[i] == _addr) {
                grantees_[i] = grantees_[grantees_.length - 1];
                grantees_.pop();
                break;
            }
        }

        emit AdminRevoked(_addr);
    }
}