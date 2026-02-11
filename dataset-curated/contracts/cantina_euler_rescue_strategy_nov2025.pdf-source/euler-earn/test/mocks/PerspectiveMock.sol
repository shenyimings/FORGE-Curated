// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.26;

import {IPerspective} from "../../src/interfaces/IPerspective.sol";

import "forge-std/Test.sol";

contract PerspectiveMock is IPerspective {
    mapping(address => bool) lookup;

    function name() external pure returns (string memory) {
        return "PerspectiveMock";
    }

    function perspectiveVerify(address vault) external {
        lookup[vault] = true;
    }

    function perspectiveUnverify(address vault) external {
        lookup[vault] = false;
    }

    function isVerified(address vault) external view returns (bool) {
        return lookup[vault];
    }
}
