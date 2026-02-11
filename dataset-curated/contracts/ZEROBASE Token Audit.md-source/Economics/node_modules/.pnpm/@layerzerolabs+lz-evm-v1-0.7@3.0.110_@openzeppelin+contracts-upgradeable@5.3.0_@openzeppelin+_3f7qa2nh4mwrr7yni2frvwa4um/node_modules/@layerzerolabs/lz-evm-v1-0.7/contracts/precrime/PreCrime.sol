// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;
pragma abicoder v2;

import "./interfaces/IPreCrime.sol";
import "./PreCrimeBase.sol";

abstract contract PreCrime is PreCrimeBase, IPreCrime {
    bytes4 private constant SIMULATE_REVERT_SELECTOR = bytes4(keccak256("SimulateRevert(uint16,bytes)"));

    /**
     * @dev 10000 - 20000 is for view mode, 20000 - 30000 is for precrime inherit mode
     */
    uint16 public constant PRECRIME_VERSION = 20001;

    constructor(uint16 _localChainId) PreCrimeBase(_localChainId) {}

    /**
     * @dev simulate run cross chain packets and get a simulation result for precrime later
     * @param _packets packets, the packets item should group by srcChainId, srcAddress, then sort by nonce
     * @return code   simulation result code; see the error code defination
     * @return data the result is use for precrime params
     */
    function simulate(Packet[] calldata _packets) external override returns (uint16 code, bytes memory data) {
        // params check
        (code, data) = _checkPacketsMaxSizeAndNonceOrder(_packets);
        if (code != CODE_SUCCESS) {
            return (code, data);
        }

        (bool success, bytes memory result) = address(this).call(
            abi.encodeWithSelector(this._simulateAndRevert.selector, _packets)
        );
        require(!success, "simulate should never return success");

        // parse code and data
        (code, data) = _parseRevertResult(result);
        if (code == CODE_SUCCESS) {
            data = abi.encode(localChainId, data); // add localChainId to the header
        }
    }

    function _parseRevertResult(bytes memory result) internal pure returns (uint16 code, bytes memory data) {
        // check revert selector
        bytes4 selector;
        assembly {
            selector := mload(add(result, 0x20)) // skip the length and get bytes4 selector
        }
        if (selector != SIMULATE_REVERT_SELECTOR) {
            // bubble up the internal error
            assembly {
                revert(add(result, 0x20), mload(result))
            }
        }

        // parse code and result
        assembly {
            // Slice the sighash. Remove the selector which is the first 4 bytes
            result := add(result, 0x04)
        }
        return abi.decode(result, (uint16, bytes));
    }

    /**
     * @dev internal function, no one should call
     * @param _packets packets
     */
    function _simulateAndRevert(Packet[] calldata _packets) external virtual {
        require(msg.sender == address(this));
        (uint16 code, bytes memory simulation) = _simulate(_packets);
        // equal to: revert SimulateRevert(code, result);
        bytes memory revertData = abi.encodePacked(SIMULATE_REVERT_SELECTOR, abi.encode(code, simulation));
        assembly {
            revert(add(revertData, 32), mload(revertData))
        }
    }

    /**
     * @dev UA execute the logic by _packets, and return simulation result for precrime. would revert state after returned result.
     * @param _packets packets
     * @return code
     * @return result
     */
    function _simulate(Packet[] calldata _packets) internal virtual returns (uint16 code, bytes memory result);

    function version() external pure override returns (uint16) {
        return PRECRIME_VERSION;
    }
}
