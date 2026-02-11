// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @title DecompressorExtension
 * @dev A contract that implements a decompression algorithm to be used in conjunction with compressed data.
 * You should implement in your contract a function that makes use of the internal methods `_setData`, `_setDataArray` for data addition to the dictionary.
 * NOTE: It is important to implement a delay when using the `_setData` and `_setDataArray` methods in your transactions. This delay helps to guard against the possibility of frontrunning, which can occur when the state of the dictionary changes during the execution of a transaction.
 * @notice This extension could result in a much higher gas consumption than expected and could potentially lead to significant memory expansion costs. Be sure to properly estimate these aspects to avoid unforeseen expenses.
 */
abstract contract DecompressorExtension {
    /**
     * @dev Emitted when an offset is used incorrectly, either because it is too small, or because its sum with a dict data's length exceeds a certain limit.
     * @param value The incorrect value used as an offset or as the sum of the offset and a dict data's length.
     */
    error IncorrectDictAccess(uint256 value);

    uint256 public constant MAX_DICT_LEN = 1_048_576; // 2 ** 20
    uint256 public constant RESERVE_DICT_LEN = 2; // 0: msg.sender; 1: address(this)

    /**
     * @dev The dictionary mapping storage slots to their associated compressed data.
     */
    bytes32[MAX_DICT_LEN] private _dict;

    /**
     * @dev Ensures the provided value is correctly used as an offset. This includes checks for the offset being too small or its sum with an dict data's length exceeding a certain limit. Value less `RESERVE_DICT_LEN` are reserved.
     * @param value The value used as an offset or as the sum of the offset and an array's length.
     */
    modifier validDictAccess(uint256 value) {
        if (value < RESERVE_DICT_LEN || value >= MAX_DICT_LEN) revert IncorrectDictAccess(value);
        _;
    }

    /**
     * @dev Returns the data stored in the dictionary in the specified range.
     * @param begin The starting index of the data range to return. First 2 positions are reserved, so it should be greater than 1.
     * @param end The ending index of the data range to return.
     * @return res An array of bytes32 values containing the data in the specified range.
     */
    function getData(
        uint256 begin,
        uint256 end
    ) external view validDictAccess(begin) validDictAccess(end) returns (bytes32[] memory res) {
        unchecked {
            if (begin < end) {
                res = new bytes32[](end - begin);
                for (uint256 i = begin; i < end; i++) {
                    res[i - begin] = _dict[i];
                }
            }
        }
    }

    /**
     * @dev Sets the data at the specified dictionary offset.
     * @param offset The dictionary offset to set the data at. First 2 positions are reserved, so it should be greater than 1.
     * @param data The data to be stored at the specified offset.
     */
    function _setData(uint256 offset, bytes32 data) internal validDictAccess(offset) {
        unchecked {
            _dict[offset] = data;
        }
    }

    /**
     * @dev Sets an array of data starting at the specified dictionary offset.
     * @param offset The starting dictionary offset to set the data at. First 2 positions are reserved, so it should be greater than 1.
     * @param dataArray The array of data to be stored starting at the specified offset.
     */
    function _setDataArray(
        uint256 offset,
        bytes32[] calldata dataArray
    ) internal validDictAccess(offset) validDictAccess(offset + dataArray.length) {
        unchecked {
            for (uint256 i = 0; i < dataArray.length; i++) {
                _dict[offset + i] = dataArray[i];
            }
        }
    }

    /**
     * @dev Decompresses the compressed data (N bytes) passed to the function using the _delegatecall function.
     */
    function decompress() external payable {
        _delegatecall(decompressed());
    }

    /**
     * @dev Calculates and returns the decompressed data from the compressed calldata.
     * @return raw The decompressed raw data.
     */
    function decompressed() public view returns (bytes memory raw) {
        return _decompressed(msg.data[4:]);
    }

    /**
     * @dev Calculates and returns the decompressed raw data from the compressed data passed as an argument.
     * @param cd The compressed data to be decompressed.
     * @return raw The decompressed raw data.
     */
    function _decompressed(bytes calldata cd) internal view returns (bytes memory raw) {
        assembly ("memory-safe") {
            // solhint-disable-line no-inline-assembly
            raw := mload(0x40)
            let outptr := add(raw, 0x20)
            let end := add(cd.offset, cd.length)
            for {
                let inptr := cd.offset
            } lt(inptr, end) {

            } {
                // solhint-disable-line no-empty-blocks
                let data := calldataload(inptr)

                let key

                // 00XXXXXX - insert X+1 zero bytes
                // 01PXXXXX - copy X+1 bytes calldata (P means padding to 32 bytes or not)
                // 10BBXXXX XXXXXXXX - use 12 bits as key for [32,20,4,31][B] bytes from storage X
                // 11BBXXXX XXXXXXXX XXXXXXXX - use 20 bits as [32,20,4,31][B] bytes from storage X
                switch shr(254, data)
                case 0 {
                    let size := add(byte(0, data), 1)
                    calldatacopy(outptr, calldatasize(), size)
                    inptr := add(inptr, 1)
                    outptr := add(outptr, size)
                    continue
                }
                case 1 {
                    let size := add(and(0x1F, byte(0, data)), 1)
                    if and(data, 0x2000000000000000000000000000000000000000000000000000000000000000) {
                        mstore(outptr, 0)
                        outptr := add(outptr, sub(32, size))
                    }
                    calldatacopy(outptr, add(inptr, 1), size)
                    inptr := add(inptr, add(1, size))
                    outptr := add(outptr, size)
                    continue
                }
                case 2 {
                    key := shr(244, shl(4, data))
                    inptr := add(inptr, 2)
                    // fallthrough
                }
                case 3 {
                    key := shr(236, shl(4, data))
                    inptr := add(inptr, 3)
                    // fallthrough
                }

                // TODO: check sload argument
                let value
                switch key
                case 0 {
                    value := caller()
                }
                case 1 {
                    value := address()
                }
                default {
                    value := sload(add(_dict.slot, key))
                }

                switch shr(254, shl(2, data))
                case 0 {
                    mstore(outptr, value)
                    outptr := add(outptr, 32)
                }
                case 1 {
                    mstore(outptr, shl(96, value))
                    outptr := add(outptr, 20)
                }
                case 2 {
                    mstore(outptr, shl(224, value))
                    outptr := add(outptr, 4)
                }
                default {
                    mstore(outptr, shl(8, value))
                    outptr := add(outptr, 31)
                }
            }
            mstore(raw, sub(sub(outptr, raw), 0x20))
            mstore(0x40, outptr)
        }
    }

    /**
     * @dev Executes a delegate call to the raw data calculated by the _decompressed function.
     * @param raw The raw data to execute the delegate call with.
     */
    function _delegatecall(bytes memory raw) internal {
        assembly ("memory-safe") {
            // solhint-disable-line no-inline-assembly
            let success := delegatecall(gas(), address(), add(raw, 0x20), mload(raw), 0, 0)
            returndatacopy(0, 0, returndatasize())
            if success {
                return(0, returndatasize())
            }
            revert(0, returndatasize())
        }
    }
}
