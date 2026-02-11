// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { console } from '@std/console.sol';

import { LibString } from '@solady/utils/LibString.sol';

contract MockContract {
  using LibString for bytes;
  using LibString for uint256;

  struct Log {
    bytes4 sig;
    bytes args;
    uint256 value;
  }

  struct Ret {
    bool revert_;
    bytes data;
  }

  mapping(bytes4 => bool) public isCall;
  mapping(bytes => Ret) public rets;

  mapping(bytes4 => uint256) public calls;
  mapping(bytes4 => Log[]) public callLogs;

  receive() external payable { }

  fallback() external payable {
    if (isCall[msg.sig]) {
      calls[msg.sig]++;
      callLogs[msg.sig].push(Log({ sig: msg.sig, args: msg.data[4:], value: msg.value }));
    }

    Ret memory ret = rets[msg.data];
    bytes memory data = ret.data;
    if (ret.revert_) {
      assembly {
        revert(add(data, 32), mload(data))
      }
    } else {
      assembly {
        return(add(data, 32), mload(data))
      }
    }
  }

  /// @notice Sets a return value for a function call
  /// @param data The calldata for the function call
  /// @param revert_ Whether the function call should revert
  /// @param returnData The return data to be used if the call does not revert
  function setRet(bytes calldata data, bool revert_, bytes calldata returnData) external {
    rets[data] = Ret({ revert_: revert_, data: returnData });
  }

  /// @notice Sets whether a function call is mutative
  /// @param sig The function selector
  function setCall(bytes4 sig) external {
    isCall[sig] = true;
  }

  /// @notice Sets whether a function call is static
  /// @param sig The function selector
  function setStatic(bytes4 sig) external {
    isCall[sig] = false;
  }

  function lastCallLog(bytes4 sig) external view returns (Log memory) {
    return _lastCallLog(sig);
  }

  function assertCall(bytes calldata args, uint256 offset) external view {
    bytes4 sig = bytes4(args[0:4]);
    _assertCall(sig, args[4:], 0, callLogs[sig][callLogs[sig].length - 1 - offset]);
  }

  function assertCall(bytes calldata args, uint256 offset, uint256 value) external view {
    bytes4 sig = bytes4(args[0:4]);
    _assertCall(sig, args[4:], value, callLogs[sig][callLogs[sig].length - 1 - offset]);
  }

  function printCall(Log memory log) public pure {
    console.log('=> log.sig: ', abi.encodePacked(log.sig).toHexString());
    console.log('=> args: ', log.args.toHexString());
    console.log('=> value: ', log.value);
  }

  function printCall(bytes4 sig, uint256 offset) external view {
    printCall(callLogs[sig][callLogs[sig].length - 1 - offset]);
  }

  function assertLastCall(bytes calldata args) external view {
    _assertLastCall(bytes4(args[0:4]), args[4:], 0);
  }

  function assertLastCall(bytes calldata args, uint256 value) external view {
    _assertLastCall(bytes4(args[0:4]), args[4:], value);
  }

  function _lastCallLog(bytes4 sig) internal view returns (Log memory) {
    return callLogs[sig][callLogs[sig].length - 1];
  }

  function _assertLastCall(bytes4 sig, bytes memory args, uint256 value) internal view {
    require(callLogs[sig].length > 0, 'no calls');
    _assertCall(sig, args, value, _lastCallLog(sig));
  }

  function _assertCall(bytes4 sig, bytes memory args, uint256 value, Log memory log) internal view {
    require(callLogs[sig].length > 0, 'no calls');

    if (log.sig != sig) {
      _printAssertionResult(sig, args, value, log);
      revert('sig mismatch');
    }

    if (log.value != value) {
      _printAssertionResult(sig, args, value, log);
      revert('value mismatch');
    }

    if (keccak256(log.args) != keccak256(args)) {
      _printAssertionResult(sig, args, value, log);
      revert('args mismatch');
    }
  }

  function _printAssertionResult(bytes4 sig, bytes memory args, uint256 value, Log memory log) internal view {
    console.log('Expected:');
    printCall(Log({ sig: sig, args: args, value: value }));
    console.log('Actual:');
    printCall(log);

    console.log('============= STACK TRACE ===============');
    for (uint256 i = 0; i < callLogs[sig].length; i++) {
      console.log('=> INDEX: ', i.toString());
      printCall(callLogs[sig][i]);
      console.log('=========================================');
    }
  }
}
