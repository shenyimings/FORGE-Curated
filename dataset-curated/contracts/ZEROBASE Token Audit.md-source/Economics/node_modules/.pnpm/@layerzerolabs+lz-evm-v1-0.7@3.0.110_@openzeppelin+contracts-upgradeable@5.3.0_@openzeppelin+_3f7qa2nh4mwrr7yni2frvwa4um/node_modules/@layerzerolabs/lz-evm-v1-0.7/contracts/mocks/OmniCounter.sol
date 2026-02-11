// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.7.6;
pragma abicoder v2;
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/ILayerZeroReceiver.sol";
import "../interfaces/ILayerZeroEndpoint.sol";
import "../interfaces/ILayerZeroUserApplicationConfig.sol";
import "../Relayer.sol";

contract OmniCounter is Ownable, ILayerZeroReceiver, ILayerZeroUserApplicationConfig {
    using SafeMath for uint;

    // keep track of how many messages have been received from other chains
    uint public messageCounter;
    mapping(address => uint) public remoteAddressCounter;
    // required: the LayerZero endpoint which is passed in the constructor
    ILayerZeroEndpoint public endpoint;
    bool public payInZRO;

    mapping(uint16 => bytes) public trustedRemoteLookup;

    constructor(address _endpoint) {
        endpoint = ILayerZeroEndpoint(_endpoint);
    }

    function getCounter() public view returns (uint) {
        return messageCounter;
    }

    // overrides lzReceive function in ILayerZeroReceiver.
    // automatically invoked on the receiving chain after the source chain calls endpoint.send(...)
    function lzReceive(
        uint16 _srcChainId,
        bytes memory _fromAddress,
        uint64 /*_nonce*/,
        bytes memory _payload
    ) external virtual override {
        require(msg.sender == address(endpoint));
        _verifySourceAddress(_srcChainId, _fromAddress);

        address fromAddress;
        assembly {
            fromAddress := mload(add(_fromAddress, 20))
        }

        // used for testing reentrant, retry sending the payload through the relayer before the initial receive has been resolved
        // ff == '0x6666' on the payload side
        if (
            keccak256(abi.encodePacked((_payload))) == keccak256(abi.encodePacked((bytes2("ff")))) ||
            keccak256(abi.encodePacked((_payload))) == keccak256(abi.encodePacked((bytes10("ff"))))
        ) {
            endpoint.receivePayload(1, bytes(""), address(0x0), 1, 1, bytes(""));
        }

        remoteAddressCounter[fromAddress] += 1;
        messageCounter += 1;
    }

    function incrementCounter(
        uint16 _dstChainId,
        bytes calldata _adapterParams,
        bytes calldata payload
    ) public payable {
        address zroPaymentAddress = payInZRO ? address(this) : address(0x0);
        _incrementCounter(_dstChainId, payload, msg.sender, zroPaymentAddress, _adapterParams);
    }

    // call send() to multiple destinations in the same transaction!
    function multiIncrementCounter(
        uint16[] calldata _dstChainIds,
        bytes calldata _adapterParams,
        bytes calldata payload
    ) public payable {
        // send() each chainId + dst address pair
        uint16[] memory dstChainIds = _dstChainIds;
        bytes memory adapterParams = _adapterParams;

        uint _refund = msg.value;
        // send() each chainId + dst address pair
        for (uint i = 0; i < dstChainIds.length; ++i) {
            (uint valueToSend, ) = endpoint.estimateFees(
                dstChainIds[i],
                address(this),
                payload,
                payInZRO,
                adapterParams
            );
            _refund = _refund.sub(valueToSend);
            // a Communicator.sol instance is the 'endpoint'
            // .send() each payload to the destination chainId + UA destination address
            address zroPaymentAddress = payInZRO ? address(this) : address(0x0);
            _incrementCounter(_dstChainIds[i], payload, msg.sender, zroPaymentAddress, adapterParams);
        }
        // refund eth if too much was sent into this contract call
        msg.sender.transfer(_refund);
    }

    function _incrementCounter(
        uint16 _dstChainId,
        bytes memory _payload,
        address payable _refundAddress,
        address _zroPaymentAddress,
        bytes memory _adapterParams
    ) public payable {
        bytes memory trustedRemote = trustedRemoteLookup[_dstChainId];
        require(trustedRemote.length > 0, "*** trustedRemote cant be 0x ");
        endpoint.send{value: msg.value}(
            _dstChainId,
            trustedRemote,
            _payload,
            _refundAddress,
            _zroPaymentAddress,
            _adapterParams
        );
    }

    function setConfig(
        uint16 /*_version*/,
        uint16 _chainId,
        uint _configType,
        bytes calldata _config
    ) external override {
        endpoint.setConfig(endpoint.getSendVersion(address(this)), _chainId, _configType, _config);
    }

    function getConfig(uint16, uint16 _chainId, address, uint _configType) external view returns (bytes memory) {
        return endpoint.getConfig(endpoint.getSendVersion(address(this)), _chainId, address(this), _configType);
    }

    function setSendVersion(uint16 version) external override {
        endpoint.setSendVersion(version);
    }

    function setReceiveVersion(uint16 version) external override {
        endpoint.setReceiveVersion(version);
    }

    function getSendVersion() external view returns (uint16) {
        return endpoint.getSendVersion(address(this));
    }

    function getReceiveVersion() external view returns (uint16) {
        return endpoint.getReceiveVersion(address(this));
    }

    function setOutboundBlockConfirmations(uint16 dstChainId, uint64 confirmations) external {
        // should technically be onlyOwner but this is a mock
        uint TYPE_OUTBOUND_BLOCK_CONFIRMATIONS = 6;
        endpoint.setConfig(
            endpoint.getSendVersion(address(this)),
            dstChainId,
            TYPE_OUTBOUND_BLOCK_CONFIRMATIONS,
            abi.encodePacked(confirmations)
        );
    }

    function getOutboundBlockConfirmations(uint16 remoteChainId) external view returns (bytes memory _confirmations) {
        return endpoint.getConfig(endpoint.getSendVersion(address(this)), remoteChainId, address(this), 5);
    }

    // set the Oracle to be used by this UA for LayerZero messages
    function setOracle(uint16 dstChainId, address oracle) external {
        // should technically be onlyOwner but this is a mock
        uint TYPE_ORACLE = 6; // from UltraLightNode
        // set the Oracle
        // uint16 _version, uint16 _chainId, uint _configType, bytes calldata _config
        endpoint.setConfig(endpoint.getSendVersion(address(this)), dstChainId, TYPE_ORACLE, abi.encode(oracle));
    }

    // get the configured oracle
    function getOracle(uint16 remoteChainId) external view returns (address _oracle) {
        bytes memory bytesOracle = endpoint.getConfig(
            endpoint.getSendVersion(address(this)),
            remoteChainId,
            address(this),
            6
        );
        assembly {
            _oracle := mload(add(bytesOracle, 32))
        }
    }

    // set the Relayer to be used by this UA for LayerZero messages
    function setRelayer(uint16 dstChainId, address relayer) external {
        uint TYPE_RELAYER = 3;
        endpoint.setConfig(endpoint.getSendVersion(address(this)), dstChainId, TYPE_RELAYER, abi.encode(relayer));
    }

    // set the inbound block confirmations
    function setInboundConfirmations(uint16 remoteChainId, uint16 confirmations) external {
        endpoint.setConfig(
            endpoint.getSendVersion(address(this)),
            remoteChainId,
            2, // CONFIG_TYPE_INBOUND_BLOCK_CONFIRMATIONS
            abi.encode(confirmations)
        );
    }

    // set outbound block confirmations
    function setOutboundConfirmations(uint16 remoteChainId, uint16 confirmations) external {
        endpoint.setConfig(
            endpoint.getSendVersion(address(this)),
            remoteChainId,
            5, // CONFIG_TYPE_OUTBOUND_BLOCK_CONFIRMATIONS
            abi.encode(confirmations)
        );
    }

    function forceResumeReceive(uint16 _srcChainId, bytes calldata _srcAddress) external override {
        // ignored for this contract
    }

    function setPayInZRO(bool _payInZRO) external onlyOwner {
        payInZRO = _payInZRO;
    }

    function approveTokenSpender(address token, address spender, uint amount) external onlyOwner {
        IERC20(token).approve(spender, amount);
    }

    // allow this contract to receive ether
    fallback() external payable {}

    receive() external payable {
        // Mock the ability to reject payments
        require(
            msg.value < 1000 && msg.value != 10,
            "Did you mean to send a blocked amount - check receive() / fallback()"
        );
    }

    // allow owner to set it multiple times.
    function setTrustedRemote(uint16 _srcChainId, bytes calldata _srcAddress) external onlyOwner {
        trustedRemoteLookup[_srcChainId] = _srcAddress;
    }

    function _verifySourceAddress(uint16 _srcChainId, bytes memory _fromAddress) internal view {
        bytes memory trustedRemote = trustedRemoteLookup[_srcChainId];
        require(
            trustedRemote.length != 0 && keccak256(_fromAddress) == keccak256(trustedRemote),
            "source counter is not trusted"
        );
    }
}
