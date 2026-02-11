// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

/**
 * @title Test Arrays
 * @author @ShaneDuncan602 @oscarsernarosero @TJ-Everett
 * @dev This contract is an abstract template to be reused by all the tests.
 * This contract holds the functions for setting up arrays for each type. Functions create various sized array for each type.
 */

abstract contract TestArrays {
    /****************** UINT256 ARRAY CREATION ******************
    /**
    * @dev This function creates a uint256 array to be used in tests 
    * @notice This function creates a uint256 array size of 1 
    * @return array uint256[] 
    */
    function createUint256Array(uint256 arg1) internal pure returns (uint256[] memory array) {
        array = new uint256[](1);
        array[0] = arg1;
    }

    /**
     * @dev This function creates a uint256 array to be used in tests
     * @notice This function creates a uint256 array size of 2
     * @return array uint256[]
     */
    function createUint256Array(uint256 arg1, uint256 arg2) internal pure returns (uint256[] memory array) {
        array = new uint256[](2);
        array[0] = arg1;
        array[1] = arg2;
    }

    /**
     * @dev This function creates a uint256 array to be used in tests
     * @notice This function creates a uint256 array size of 3
     * @return array uint256[]
     */
    function createUint256Array(uint256 arg1, uint256 arg2, uint256 arg3) internal pure returns (uint256[] memory array) {
        array = new uint256[](3);
        array[0] = arg1;
        array[1] = arg2;
        array[2] = arg3;
    }

    function createUint256Array(uint256 arg1, uint256 arg2, uint256 arg3, uint256 arg4) internal pure returns (uint256[] memory array) {
        array = new uint256[](4);
        array[0] = arg1;
        array[1] = arg2;
        array[2] = arg3;
        array[3] = arg4;
    }

    function createUint256Array(
        uint256 arg1,
        uint256 arg2,
        uint256 arg3,
        uint256 arg4,
        uint256 arg5
    ) internal pure returns (uint256[] memory array) {
        array = new uint256[](5);
        array[0] = arg1;
        array[1] = arg2;
        array[2] = arg3;
        array[3] = arg4;
        array[4] = arg5;
    }

    function createUint256Array(
        uint256 arg1,
        uint256 arg2,
        uint256 arg3,
        uint256 arg4,
        uint256 arg5,
        uint256 arg6
    ) internal pure returns (uint256[] memory array) {
        array = new uint256[](6);
        array[0] = arg1;
        array[1] = arg2;
        array[2] = arg3;
        array[3] = arg4;
        array[4] = arg5;
        array[5] = arg6;
    }

    function createUint256Array(
        uint256 arg1,
        uint256 arg2,
        uint256 arg3,
        uint256 arg4,
        uint256 arg5,
        uint256 arg6,
        uint256 arg7
    ) internal pure returns (uint256[] memory array) {
        array = new uint256[](7); 
        array[0] = arg1;
        array[1] = arg2;
        array[2] = arg3;
        array[3] = arg4;
        array[4] = arg5;
        array[5] = arg6;
        array[6] = arg7;
    }

    function createUint256Array(
        uint256 arg1,
        uint256 arg2,
        uint256 arg3,
        uint256 arg4,
        uint256 arg5,
        uint256 arg6,
        uint256 arg7,
        uint256 arg8
    ) internal pure returns (uint256[] memory array) {
        array = new uint256[](8);
        array[0] = arg1;
        array[1] = arg2;
        array[2] = arg3;
        array[3] = arg4;
        array[4] = arg5;
        array[5] = arg6;
        array[6] = arg7;
        array[7] = arg8;
    }

    function createUint256Array(
        uint256 arg1,
        uint256 arg2,
        uint256 arg3,
        uint256 arg4,
        uint256 arg5,
        uint256 arg6,
        uint256 arg7,
        uint256 arg8,
        uint256 arg9
    ) internal pure returns (uint256[] memory array) {
        array = new uint256[](9);
        array[0] = arg1;
        array[1] = arg2;
        array[2] = arg3;
        array[3] = arg4;
        array[4] = arg5;
        array[5] = arg6;
        array[6] = arg7;
        array[7] = arg8;
        array[8] = arg9;
    }

}
