// SPDX-License-Identifier: BSD-3-Clause-1
pragma solidity 0.8.30;

import "./interfaces/IDepositContract.sol";

contract BatchDepositConsolidation {
    IDepositContract public immutable depositContract;
    
    uint constant private pubkeyLength = 48;
    uint constant private signatureLength = 96;
    uint constant private depositDataRootLength = 32;
    uint constant private depositArgsLength =
        pubkeyLength +
        signatureLength +
        depositDataRootLength;

    constructor(IDepositContract _depositContract) {
        require(address(_depositContract) != address(0),
                "deposit contract");
        depositContract = _depositContract;   
    }

    function batchDeposit(uint validUntil, address withdrawAddress, bytes1 withdrawType, uint256[] calldata values, bytes calldata args) external payable {
        require(
            block.timestamp < validUntil,
            "deposit data agreed upon deadline");
        require(
            args.length % depositArgsLength == 0,
            "wrong input"
        );
        uint count = args.length / depositArgsLength;
        require(count == values.length, "mismatched num of args");

        uint signatureStart;
        uint depositDataRootStart;
        uint depositDataRootEnd;

        bytes memory rawWithdrawAuthority = abi.encodePacked(withdrawType, hex"0000000000000000000000", withdrawAddress);

        for (uint j = 0; j < count; j++) {
            unchecked
            {
                signatureStart = j * depositArgsLength + pubkeyLength;
                depositDataRootStart = signatureStart + signatureLength;
                depositDataRootEnd = depositDataRootStart + depositDataRootLength;
            }
    
            depositContract.deposit{value: values[j] }(
                args[j * depositArgsLength : signatureStart],
                rawWithdrawAuthority,
                args[signatureStart : depositDataRootStart],
                // bytes32 depositDataRoot
                bytes32(args[depositDataRootStart : depositDataRootEnd])
            );
        }
    }
}
