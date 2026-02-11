// SPDX-License-Identifier: BUSL-1.1

pragma solidity >=0.7.0;
pragma abicoder v2;

import "../interfaces/ILayerZeroUltraLightNodeV2.sol";

contract UltraLightNodeV2Mock is ILayerZeroUltraLightNodeV2 {
    event executed();
    event paidTo(address _to, uint _amount);

    mapping(address => mapping(uint16 => mapping(bytes32 => mapping(bytes32 => uint)))) public hashLookup; //[oracle][srcChainId][blockhash][datahash] -> confirmation

    constructor() {}

    //Mock version of uln for testing the withdraw fee function. If we need to use this again we can expand on it.
    // Relayer functions
    function validateTransactionProof(
        uint16 _srcChainId,
        address _dstAddress,
        uint _gasLimit,
        bytes32 _lookupHash,
        bytes32 _blockData,
        bytes calldata _transactionProof
    ) external override {
        emit executed();
    }

    // an Oracle delivers the block data using updateHash()
    function updateHash(
        uint16 _srcChainId,
        bytes32 _lookupHash,
        uint _confirmations,
        bytes32 _blockData
    ) external override {
        emit executed();
    }

    // can only withdraw the receivable of the msg.sender
    function withdrawNative(address payable _to, uint _amount) external override {
        (bool success, ) = _to.call{value: _amount}("");
        emit paidTo(_to, _amount);
    }

    function withdrawZRO(address _to, uint _amount) external override {
        emit executed();
    }

    // view functions
    function getAppConfig(
        uint16 _remoteChainId,
        address _userApplicationAddress
    ) external view override returns (ApplicationConfiguration memory) {}

    function accruedNativeFee(address _address) external view override returns (uint) {}

    receive() external payable {}
}
