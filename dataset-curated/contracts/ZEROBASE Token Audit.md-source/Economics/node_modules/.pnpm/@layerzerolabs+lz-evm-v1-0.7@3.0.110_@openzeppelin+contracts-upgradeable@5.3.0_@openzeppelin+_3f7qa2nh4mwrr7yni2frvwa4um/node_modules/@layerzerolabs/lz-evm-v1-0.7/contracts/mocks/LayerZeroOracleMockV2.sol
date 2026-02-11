// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/ILayerZeroOracleV2.sol";
import "../interfaces/ILayerZeroUltraLightNodeV2.sol";

contract LayerZeroOracleMockV2 is ILayerZeroOracleV2, Ownable, ReentrancyGuard {
    mapping(address => bool) public approvedAddresses;
    mapping(uint16 => mapping(uint16 => uint)) public chainPriceLookup;
    mapping(uint16 => mapping(uint16 => uint64)) public jobs; // mocked, not used for anything yet
    uint public fee;
    ILayerZeroUltraLightNodeV2 public uln; // ultraLightNode instance

    event OracleNotified(uint16 dstChainId, uint16 _outboundProofType, uint blockConfirmations);
    event Withdraw(address to, uint amount);

    constructor() {
        approvedAddresses[msg.sender] = true;
    }

    // mocked for now, will auto accept the job, and return the price at the same time
    function assignJob(
        uint16 _dstChainId,
        uint16 _outboundProofType,
        uint64 _outboundBlockConfirmation,
        address
    ) external override returns (uint price) {
        jobs[_dstChainId][_outboundProofType] = _outboundBlockConfirmation;
        return chainPriceLookup[_outboundProofType][_dstChainId];
    }

    function getFee(
        uint16 _dstChainId,
        uint16 _outboundProofType,
        uint64 /*_outboundBlockConfirmation*/,
        address
    ) external view override returns (uint) {
        return chainPriceLookup[_outboundProofType][_dstChainId];
    }

    function withdrawFee(address payable _to, uint _amount) public override onlyOwner nonReentrant {
        (bool success, ) = _to.call{value: _amount}("");
        require(success, "failed to withdraw");
        emit Withdraw(_to, _amount);
    }

    function updateHash(uint16 _remoteChainId, bytes32 _blockHash, uint _confirmations, bytes32 _data) external {
        require(approvedAddresses[msg.sender], "LayerZeroOracleMock: caller must be approved");
        uln.updateHash(_remoteChainId, _blockHash, _confirmations, _data);
    }

    function setUln(address ulnAddress) external onlyOwner {
        uln = ILayerZeroUltraLightNodeV2(ulnAddress);
    }

    function setDeliveryAddress(uint16 _dstChainId, address _deliveryAddress) public onlyOwner {}

    function setPrice(uint16 _destinationChainId, uint16 _outboundProofType, uint _price) external onlyOwner {
        chainPriceLookup[_outboundProofType][_destinationChainId] = _price;
    }

    function setApprovedAddress(address _oracleAddress, bool _approve) external {
        approvedAddresses[_oracleAddress] = _approve;
    }

    function isApproved(address _relayerAddress) public view returns (bool) {
        return approvedAddresses[_relayerAddress];
    }

    fallback() external payable {}

    receive() external payable {}
}
