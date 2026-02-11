// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

interface IAllocationResolver {
    function setAllocation(address basket, bytes32[] calldata newAllocation) external;
    function getTargetWeight(address basket) external view returns (bytes32[] memory);
    function getAllocationLength(address basket) external view returns (uint256);
    function getAllocationElement(address basket, uint256 index) external view returns (bytes32);
    function setBasketResolver(address basket, address resolver) external;
    function enroll(address basket, address resolver, uint256 selectionsLength) external;
    function isEnrolled(address basket) external view returns (bool);
    function isSubscribed(address basket, address proposer) external view returns (bool);
}
