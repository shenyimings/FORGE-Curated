// SPDX-License-Identifier: GPL-3
pragma solidity 0.8.23;

import {ISAMM} from "../../src/interfaces/ISAMM.sol";

library ArrHelper {
    function _proofArr() internal pure returns (ISAMM.Proof[] memory arr) {
        arr = new ISAMM.Proof[](0);
    }

    function _proofArr(ISAMM.Proof memory proof) internal pure returns (ISAMM.Proof[] memory arr) {
        arr = new ISAMM.Proof[](1);
        arr[0] = proof;
    }

    function _proofArr(ISAMM.Proof memory a, ISAMM.Proof memory b) internal pure returns (ISAMM.Proof[] memory arr) {
        arr = new ISAMM.Proof[](2);
        arr[0] = a;
        arr[1] = b;
    }

    function _proofArr(ISAMM.Proof memory a, ISAMM.Proof memory b, ISAMM.Proof memory c)
        internal
        pure
        returns (ISAMM.Proof[] memory arr)
    {
        arr = new ISAMM.Proof[](3);
        arr[0] = a;
        arr[1] = b;
        arr[2] = c;
    }

    function _arr(uint256 a, uint256 b) internal pure returns (uint256[2] memory arr) {
        arr[0] = a;
        arr[1] = b;
    }

    function _arr(uint256 a, uint256 b, uint256 c, uint256 d) internal pure returns (uint256[2][2] memory arr) {
        arr[0][0] = a;
        arr[0][1] = b;
        arr[1][0] = c;
        arr[1][1] = d;
    }

    function _arr(address a) internal pure returns (address[] memory arr) {
        arr = new address[](1);
        arr[0] = a;
    }
}
