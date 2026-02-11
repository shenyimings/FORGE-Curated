// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

contract BaseInherited {
    function pushSerializedTx(
        string memory _name,
        address _to,
        uint256 _value,
        bytes memory _data
    ) public virtual {}
}