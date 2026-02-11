// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

interface IOperatorController {
    function initiateKeyPairValidation(address _sender, uint256 _operatorId) external;

    function reportKeyPairValidation(uint256 _operatorId, bool _success) external;

    function queueLength() external view returns (uint256);

    function totalActiveValidators() external view returns (uint256);

    function currentStateHash() external view returns (bytes32);
}
