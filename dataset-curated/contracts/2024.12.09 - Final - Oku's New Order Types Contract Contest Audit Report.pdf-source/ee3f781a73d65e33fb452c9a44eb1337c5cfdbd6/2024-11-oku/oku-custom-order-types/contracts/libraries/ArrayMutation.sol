// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;
import "../interfaces/uniswapV3/UniswapV3Pool.sol";

library ArrayMutation {
    ///@param idx the element to remove from @param inputArray
    function removeFromArray(
        uint96 idx,
        uint96[] memory inputArray
    ) internal pure returns (uint96[] memory newList) {
        // Check that inputArray is not empty and idx is valid
        require(inputArray.length > 0, "inputArray length == 0");
        require(idx < inputArray.length, "index out of bounds");

        // Create a new array of the appropriate size
        newList = new uint96[](inputArray.length - 1);

        // Copy elements before the index
        for (uint96 i = 0; i < idx; i++) {
            newList[i] = inputArray[i];
        }

        // Copy elements after the index
        for (uint96 i = idx + 1; i < inputArray.length; i++) {
            newList[i - 1] = inputArray[i];
        }

        return newList;
    }
}
