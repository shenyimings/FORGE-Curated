// SPDX-License-Identifier: MIT 
pragma solidity ^0.8.0;

import {VerificationLibrary} from  './VerificationLibrary.sol';
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./VerificationLibrary.sol";
import "./interfaces/IZenToken.sol";

/// @title ZendBackupVault
/// @notice This contract is used to store balances from old ZEND Mainchain, and, once all are loaded, it allows manual claiming in the new chain.
///         In the constructor will receive an admin address (owner), the only entity authorized to perform load operations. Before loading all the accounts,
//          the cumulative hash calculated with all the accounts dump data must be set.
contract ZendBackupVault is Ownable {
    uint256 constant HORIZEN_UNCOMPRESSED_PUBLIC_KEY_LENGTH = 65;
    uint256 constant HORIZEN_COMPRESSED_PUBLIC_KEY_LENGTH = 33;

    struct AddressValue {
        bytes20 addr;
        uint256 value;
    }

    struct PubKey {
        bytes32 x;
        bytes32 y;
    }
    
    // Map of the claimable balances.
    // The key is the zendAddress in bs58 decoded format
    mapping(bytes20 => uint256) public balances;
       
    // Cumulative Hash calculated
    bytes32 public _cumulativeHash;

    // Final expected Cumulative Hash, used for checkpoint, to unlock claim
    bytes32 public cumulativeHashCheckpoint;

    IZenToken public zenToken;

    string private MESSAGE_CONSTANT;
    /// First part of the message to sign, needed for zen claim operation. It is composed by the token symbol + MESSAGE_CONSTANT
    string public message_prefix;

    error AddressNotValid();
    error CumulativeHashNotValid();
    error CumulativeHashCheckpointReached();
    error CumulativeHashCheckpointNotSet();
    error UnauthorizedOperation();
    error ERC20NotSet();
    error NothingToClaim(bytes20 zenAddress);
    error InsufficientSignatures(uint256 number, uint256 required);
    error InvalidSignatureArrayLength();
    error InvalidPublicKeysArraysLength();
    error TooManySignatures();
    error InvalidScriptLength();
    error InvalidPublicKeySize(uint256 size);
    error UnexpectedZeroPublicKey(PubKey);
    error InvalidPublicKey(uint256 index, uint256 xOrY, bytes32 expected, bytes32 received);
    error InvalidDirectMultisigScript(uint256 requiredSignaturesInScript, uint256 totalSignaturesInScript);

    event Claimed(address indexed claimer, address indexed destAddress, bytes20 zenAddress, uint256 amount);

    /// @notice verify if we are in the state in which users can already claim
    modifier canClaim(address destAddress) {
        if (_cumulativeHash != cumulativeHashCheckpoint) revert CumulativeHashNotValid(); //Loaded data not matching - distribution locked 
        if (address(zenToken) == address(0)) revert ERC20NotSet();
        if (address(destAddress) == address(0)) revert AddressNotValid();
        if (cumulativeHashCheckpoint == bytes32(0)) revert CumulativeHashCheckpointNotSet();
        _;
    }

    /// @notice Smart contract constructor
    /// @param _admin the only entity authorized to perform restore operations
    /// @param base_message one of the parts of the message to sign for zen claim
    constructor(address _admin, string memory base_message) Ownable(_admin) {
        MESSAGE_CONSTANT = base_message;
    }

    /// @notice Set expected cumulative hash after all the data has been loaded
    /// @param _cumulativeHashCheckpoint  a cumulative recursive hash calculated with all the dump data.
    ///                                   Will be used to verify the consistency of the restored data, and as
    ///                                   a checkpoint to understand when all the data has been loaded and the claim 
    ///                                   can start
    function setCumulativeHashCheckpoint(bytes32 _cumulativeHashCheckpoint) public onlyOwner{
        if(_cumulativeHashCheckpoint == bytes32(0)) revert CumulativeHashNotValid();  
        if (cumulativeHashCheckpoint != bytes32(0)) revert UnauthorizedOperation();  //already set
        cumulativeHashCheckpoint = _cumulativeHashCheckpoint;
    }

    /// @notice Insert a new batch of account tuples (bytes20, value) and updates the cumulative hash. The total balance of all accounts is minted and assigned to Zend Vault contract.
    ///         The zend addresses are in bs58 decoded format, without prefix and checksum.
    ///         To guarantee the same algorithm is applied, the expected cumulativeHash after the batch processing must be provided explicitly
    /// @param expectedCumulativeHash  the cumulative recursive hash calculated with all the data already inserted plus the current batch.
    /// @param addressValues new accounts batch to insert 
    function batchInsert(bytes32 expectedCumulativeHash, AddressValue[] calldata addressValues) public onlyOwner {
        if (cumulativeHashCheckpoint == bytes32(0)) revert CumulativeHashCheckpointNotSet();  
        if (address(zenToken) == address(0)) revert ERC20NotSet();
        if (_cumulativeHash == cumulativeHashCheckpoint) revert CumulativeHashCheckpointReached();

        uint256 i;
        bytes32 auxHash = _cumulativeHash;
        uint256 cumulativeBalance;
        while (i != addressValues.length) {
            balances[addressValues[i].addr] = addressValues[i].value;
            auxHash = keccak256(abi.encode(auxHash, addressValues[i].addr, addressValues[i].value));
            unchecked {cumulativeBalance = cumulativeBalance + addressValues[i].value; }
            unchecked { ++i; }
        }
        _cumulativeHash = auxHash;
        if (expectedCumulativeHash != _cumulativeHash) revert CumulativeHashNotValid();   
        zenToken.mint(address(this), cumulativeBalance);

        if (cumulativeHashCheckpoint == _cumulativeHash){
            zenToken.notifyMintingDone();
        }
    }

    /// @notice Set official ZEN ERC-20 smart contract that will be used for minting
    function setERC20(address addr) public onlyOwner {
        if (address(zenToken) != address(0)) revert UnauthorizedOperation();  //ERC-20 address already set
        if(addr == address(0)) revert AddressNotValid();
        zenToken = IZenToken(addr);
        message_prefix = string(abi.encodePacked(zenToken.symbol(), MESSAGE_CONSTANT));

    }

    /// @notice Internal claim function, to reuse the code between P2PKH and P2PSH
    function _claim(address destAddress, bytes20 zenAddress) internal {
        uint256 amount = balances[zenAddress];
        
        balances[zenAddress] = 0;
        zenToken.transfer(destAddress, amount);
        emit Claimed(msg.sender, destAddress, zenAddress, amount);
    }

    /// @notice Claim a P2PKH balance.
    /// @param  destAddress is the receiver of the funds
    /// @param  hexSignature is the signature of the claiming message. Must be generated in a compressed format to claim a zend address
    ///         generated with the public key in compressed format, or uncompressed otherwise.
    ///         (Claiming message is predefined and composed by the concatenation of the message_prefix (token symbol + MESSAGE_CONSTANT) and the destination address in EIP-55 format (https://github.com/ethereum/ercs/blob/master/ERCS/erc-55.md) string)
    /// @param  pubKey are the first 32 bytes and second 32 bytes of the signing key (we use always the uncompressed format here)
    ///         Note: we pass the pubkey explicitly because the extraction from the signature would be GAS expensive.
    function claimP2PKH(address destAddress, bytes memory hexSignature, PubKey calldata pubKey) public canClaim(destAddress) {
        VerificationLibrary.Signature memory signature = VerificationLibrary.parseZendSignature(hexSignature);
        bytes20 zenAddress;
        if (signature.v == 31 || signature.v == 32){
            //signature was compressed, also the zen address will be from the compressed format
             zenAddress = VerificationLibrary.pubKeyCompressedToZenAddress(pubKey.x, VerificationLibrary.signByte(pubKey.y));
        } else {
             zenAddress = VerificationLibrary.pubKeyUncompressedToZenAddress(pubKey.x, pubKey.y);
        }
        //check amount to claim
        uint256 amount = balances[zenAddress];
        if (amount == 0) revert NothingToClaim(zenAddress);

        //address in signed message should respect EIP-55 format (https://github.com/ethereum/EIPs/blob/master/EIPS/eip-55.md)
        string memory asString = Strings.toChecksumHexString(destAddress);
        string memory strMessageToSign = string(abi.encodePacked(message_prefix, asString));
        bytes32 messageHash = VerificationLibrary.createMessageHash(strMessageToSign);
        VerificationLibrary.verifyZendSignature(messageHash, signature, pubKey.x, pubKey.y);

        _claim(destAddress, zenAddress);
    }

    /// @notice Direct claim of special UTXOs generated deterministically from a BaseAddress. 
    ///         This is a special usecase for users that can't sign a message, and requires they create this special UTXO in the old mainchain before the migration.
    ///          Check documentation for details.
    /// @param  baseDestAddress is the receiver of the funds. The zend address will be calculated from this one.
    function claimDirect(address baseDestAddress) public canClaim(baseDestAddress) {
        bytes memory addressToBytes = abi.encodePacked(baseDestAddress);
        bytes20 zenAddress = _extractZenAddressFromScriptOrDestAddress(addressToBytes);

        //check amount to claim
        uint256 amount = balances[zenAddress];
        if (amount == 0) revert NothingToClaim(zenAddress);

        _claim(baseDestAddress, zenAddress);
    }
    
    /// @notice Claim a P2SH balance.
    ///         destAddress is the receiver of the funds
    ///         hexSignatures is the array of the signatures of the claiming message. If a signature is not present, signature MUST be 0

    ///         IMPORTANT: the array should have as length the number of public keys in the script. The signature in the "i" position should be the signature for the "i"
    ///         pub key in the order it appears in the script. If the signature is not present for that key, it should be empty.
    ///         This is to avoid duplicated signatures without expensive checks.
    ///         
    ///         script is the script to claim, from which pubKeys will be extracted
    ///         pubKeysX and pubKeysY are the first 32 bytes and second 32 bytes of the signing keys for each one in the script (we use always the uncompressed format here)
    ///         If a public key is not needed (because signature is zero) its value can be zero; even if not needed, if it is present, it should be the same used for the script
    ///         (Claiming message is predefined and composed by the string in the message_prefix variable concatenated with the zenAddress and destAddress in lowercase string hex format)
    ///         (zenAddress is the string representation with 0x prefix )
    function claimP2SH(address destAddress, bytes[] calldata hexSignatures, bytes memory script, PubKey[] calldata pubKeys) public canClaim(destAddress) {
        if(hexSignatures.length != pubKeys.length) revert InvalidSignatureArrayLength(); //check method doc
        if(hexSignatures.length > 16) revert TooManySignatures(); //ZEND multisig scripts support up to 16 signatures

        bytes20 zenAddress = _extractZenAddressFromScriptOrDestAddress(script);
        //check amount to claim
        if (balances[zenAddress] == 0) revert NothingToClaim(zenAddress);
        uint256 minSignatures = uint256(uint8(script[0])) - 80;

        _verifyPubKeysFromScript(script, pubKeys);

        //address in signed message should respect EIP-55 format (https://github.com/ethereum/EIPs/blob/master/EIPS/eip-55.md)
        string memory destAddressAsString = Strings.toChecksumHexString(destAddress);
        string memory zenAddressAsString = Strings.toHexString(address(zenAddress));
        string memory strMessageToSign = string(abi.encodePacked(message_prefix, zenAddressAsString, destAddressAsString));
        bytes32 messageHash = VerificationLibrary.createMessageHash(strMessageToSign);

        //check signatures
        uint256 validSignatures;
        uint256 i;
        while(i != hexSignatures.length && validSignatures < minSignatures) {
            if(hexSignatures[i].length != 0) { // skip otherwise
                if(pubKeys[i].x == bytes32(0) || pubKeys[i].y == bytes32(0)) revert UnexpectedZeroPublicKey(pubKeys[i]);
                else {
                    VerificationLibrary.Signature memory signature = VerificationLibrary.parseZendSignature(hexSignatures[i]);
                    //check doc: we suppose the signature in i position belonging to the pub key in i position in the script
                    if(VerificationLibrary.verifyZendSignatureBool(messageHash, signature, pubKeys[i].x, pubKeys[i].y)) {
                        unchecked { ++validSignatures; }
                    }
                }
            }
            unchecked { ++i; }
        }

        if(validSignatures < minSignatures) revert InsufficientSignatures(validSignatures, minSignatures); //insufficient signatures

        _claim(destAddress, zenAddress);
    }

    /// @notice Direct claim of special UTXOs to a multisignature partially generated deterministically from a BaseAddress. 
    ///         This is a special usecase for users that can't sign a message, and requires they create this special UTXO in the old mainchain before the migration.
    ///          Check documentation for details.
    /// @param  script is the redeem script for the multisig wallet.
    /// @param  baseDestAddress is the receiver of the funds. The zend address will be calculated from this one.
    function claimDirectMultisig(bytes memory script, address baseDestAddress) public canClaim(baseDestAddress) {
        //check amount to claim
        bytes20 zenAddress = _extractZenAddressFromScriptOrDestAddress(script);
        uint256 amount = balances[zenAddress];
        if (amount == 0) revert NothingToClaim(zenAddress);

        //generate derivative pub key from base address
        bytes memory baseAddressToBytes = abi.encodePacked(baseDestAddress);
        bytes32 pubKeyXFromBaseAddress = sha256(baseAddressToBytes);

        //check is multisig 1 of 2
        uint256 minSignatures = uint256(uint8(script[0])) - 80;
        uint256 total = uint256(uint8(script[script.length - 2])) - 80;
        if(minSignatures != 1 || total != 2) revert InvalidDirectMultisigScript(minSignatures, total);

        //extract second key "x" from script
        uint256 firstPubKeySize = uint256(uint8(script[1]));
        uint256 start = firstPubKeySize + 4; //skip first OP (+1), skip size of first key (+1), first key (firstPubKeySize), size of second key (+1) and prefix of second key (+1)
        bytes32 key = _extractBytes32FromBytes(script, start);

        if(pubKeyXFromBaseAddress != key) revert InvalidPublicKey(1, 0, key, pubKeyXFromBaseAddress);

        _claim(baseDestAddress, zenAddress);
    }

    /// @notice verify public keys from multisignature script
    function _verifyPubKeysFromScript(bytes memory script, PubKey[] calldata pubKeys) internal pure {
        if(script.length < 2) revert InvalidScriptLength();
        uint256 total = uint256(uint8(script[script.length - 2])) - 80;

        if(pubKeys.length != total) revert InvalidPublicKeysArraysLength();
        uint256 pos = 1;

        uint256 i;
        while(i < total) {
            uint256 nextPubKeySize = uint256(uint8(script[pos]));
            unchecked { ++pos; }

            if(nextPubKeySize != HORIZEN_COMPRESSED_PUBLIC_KEY_LENGTH && nextPubKeySize != HORIZEN_UNCOMPRESSED_PUBLIC_KEY_LENGTH) revert InvalidPublicKeySize(nextPubKeySize);
            
            if(pubKeys[i].x != 0 && pubKeys[i].y != 0) { //we check pub keys only if both x and y are != 0 
                //extract key
                //first 32 bytes
                uint256 firstPartStart = pos+1;
                bytes32 firstPart = _extractBytes32FromBytes(script, firstPartStart);

                if(pubKeys[i].x != firstPart) revert InvalidPublicKey(i, 0, firstPart, pubKeys[i].x);

                //second part
                if(nextPubKeySize == HORIZEN_UNCOMPRESSED_PUBLIC_KEY_LENGTH) { //uncompressed case
                    uint256 secondPartStart = pos + 33;
                    bytes32 secondPart = _extractBytes32FromBytes(script, secondPartStart);
                    
                    if(pubKeys[i].y != secondPart) revert InvalidPublicKey(i, 1, secondPart, pubKeys[i].y);
                }
                else { //in compressed case, we just check sign
                    uint8 sign;
                    assembly {
                        let offset := add(add(script, 0x20), pos) // data start + pos
                        sign := byte(0, mload(offset))            // take the LS byte
                    }
                    uint8 ySign = VerificationLibrary.signByte(pubKeys[i].y);
                    if(sign != ySign) revert InvalidPublicKey(i, 1, bytes32(uint256(sign)), bytes32(uint256(ySign)));
                }
            }

            pos += nextPubKeySize;
            unchecked { ++i; }
        }
    }

    /// @notice extract zen address from multisignature script or address (direct claim)
    function _extractZenAddressFromScriptOrDestAddress(bytes memory script) internal pure returns(bytes20) {
        bytes32 scriptHash = sha256(script);
        scriptHash = ripemd160(abi.encode(scriptHash));
        return bytes20(scriptHash); 
    }

    /// @notice extract a bytes32 object from a bytes object starting from the given position
    function _extractBytes32FromBytes(bytes memory script, uint256 start) internal pure returns(bytes32) {
        bytes32 ret;
        assembly {
            let sourcePtr := add(script, 0x20)
            let offset := add(sourcePtr, start)
            ret := mload(offset)
        }
        return ret;
    }
}
