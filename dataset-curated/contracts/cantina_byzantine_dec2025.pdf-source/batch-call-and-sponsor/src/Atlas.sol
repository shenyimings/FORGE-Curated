// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

interface IAtlas {
    event CallExecuted(address indexed sender, address indexed to, uint256 value, bytes data);

    error InvalidSigner();
    error ExpiredSignature();
    error Unauthorized();
    error NonceAlreadyUsed();
    error CallReverted();

    /// @notice Represents a single call within a batch.
    struct Call {
        address to;
        uint256 value;
        bytes data;
    }

    function executeCall(Call calldata call, uint256 deadline, uint256 nonce, uint8 v, bytes32 r, bytes32 s)
        external
        payable;
    function executeCalls(Call[] calldata calls, uint256 deadline, uint256 nonce, uint8 v, bytes32 r, bytes32 s)
        external
        payable;
    function executeCall(Call calldata call) external payable;
    function executeCalls(Call[] calldata calls) external payable;
}

contract Atlas is IAtlas {
    /*
        Storage
    */

    bytes32 constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(uint256 chainId,address verifyingContract)");
    bytes32 constant CALL_TYPEHASH = keccak256("Call(address to,uint256 value,bytes data)");
    bytes32 constant EXECUTE_CALLS_TYPEHASH =
        keccak256("ExecuteCalls(Call[] calls,uint256 deadline,uint256 nonce)Call(address to,uint256 value,bytes data)");
    bytes32 constant EXECUTE_CALL_TYPEHASH =
        keccak256("ExecuteCall(Call call,uint256 deadline,uint256 nonce)Call(address to,uint256 value,bytes data)");

    mapping(uint256 => bool) public usedNonces;

    /*
        External functions
    */

    function executeCall(Call calldata call, uint256 deadline, uint256 nonce, uint8 v, bytes32 r, bytes32 s)
        external
        payable
    {
        // Verify deadline
        require(block.timestamp <= deadline, ExpiredSignature());

        // Verify nonce
        require(!usedNonces[nonce], NonceAlreadyUsed());

        // Retrieve eip-712 digest
        bytes32 encodeData = keccak256(abi.encode(CALL_TYPEHASH, call.to, call.value, keccak256(call.data)));
        bytes32 hashStruct = keccak256(abi.encode(EXECUTE_CALL_TYPEHASH, encodeData, deadline, nonce));
        bytes32 digest = keccak256(abi.encodePacked(hex"1901", DOMAIN_SEPARATOR(), hashStruct));

        // Recover the signer
        address recoveredAddress = ECDSA.recover(digest, v, r, s);
        require(recoveredAddress != address(0) && recoveredAddress == address(this), InvalidSigner());

        // Mark the nonce as used
        usedNonces[nonce] = true;

        _executeCall(call);
    }

    function executeCalls(Call[] calldata calls, uint256 deadline, uint256 nonce, uint8 v, bytes32 r, bytes32 s)
        external
        payable
    {
        // Verify deadline
        require(block.timestamp <= deadline, ExpiredSignature());

        // Verify nonce
        require(!usedNonces[nonce], NonceAlreadyUsed());

        // Hash each call individually
        bytes32[] memory callStructHashes = new bytes32[](calls.length);
        for (uint256 i; i < calls.length; ++i) {
            callStructHashes[i] =
                keccak256(abi.encode(CALL_TYPEHASH, calls[i].to, calls[i].value, keccak256(calls[i].data)));
        }

        // Retrieve eip-712 digest
        bytes32 encodeData = keccak256(abi.encodePacked(callStructHashes));
        bytes32 hashStruct = keccak256(abi.encode(EXECUTE_CALLS_TYPEHASH, encodeData, deadline, nonce));
        bytes32 digest = keccak256(abi.encodePacked(hex"1901", DOMAIN_SEPARATOR(), hashStruct));

        // Recover the signer
        address recoveredAddress = ECDSA.recover(digest, v, r, s);
        require(recoveredAddress != address(0) && recoveredAddress == address(this), InvalidSigner());

        // Mark the nonce as used
        usedNonces[nonce] = true;

        _executeBatch(calls);
    }

    function executeCall(Call calldata call) external payable {
        require(msg.sender == address(this), Unauthorized());
        _executeCall(call);
    }

    function executeCalls(Call[] calldata calls) external payable {
        require(msg.sender == address(this), Unauthorized());
        _executeBatch(calls);
    }

    /*
        Private functions
    */

    function _executeBatch(Call[] calldata calls) private {
        for (uint256 i; i < calls.length; ++i) {
            _executeCall(calls[i]);
        }
    }

    function _executeCall(Call calldata callItem) private {
        // address(this) in the contract equals the EOA address NOT the contract address
        (bool success,) = callItem.to.call{value: callItem.value}(callItem.data);
        require(success, CallReverted());
        emit CallExecuted(msg.sender, callItem.to, callItem.value, callItem.data);
    }

    /*
        Views
    */

    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        return keccak256(abi.encode(DOMAIN_TYPEHASH, block.chainid, address(this)));
    }
}
