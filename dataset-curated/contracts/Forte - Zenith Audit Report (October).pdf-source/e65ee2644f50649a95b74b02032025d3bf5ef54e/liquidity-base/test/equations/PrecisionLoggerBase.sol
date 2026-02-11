// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {MathLibs} from "src/amm/mathLibs/MathLibs.sol";
import {console2} from "forge-std/console2.sol";
import {PythonUtils} from "test/util/PythonUtils.sol";

abstract contract PrecisionLoggerBase is PythonUtils {
    using MathLibs for uint256;

    uint PRECISION_BASE = MathLibs.WAD ** 2; // all precision values will be WAD2 numbers
    uint PRECISION_BASE_SQRT = MathLibs.WAD;

    function runPrecisionPlotter(string memory columns, string memory fileName) internal {
        string[] memory inputs = _buildFFIPlotCSV(columns, fileName);
        bytes memory res = vm.ffi(inputs);
        if (res.length > 0) revert("python plotting issue");
        console2.log("plotted");
    }

    function getPrecision(uint256 solVal, uint256 pythonVal) internal view returns (uint256 precision) {
        uint absoluteError = solVal > pythonVal ? (solVal - pythonVal) : (pythonVal - solVal);
        uint num;
        if (absoluteError == solVal && solVal > 0) {
            precision = PRECISION_BASE;
        } else {
            if (absoluteError == 0) {
                precision = 0;
            } else {
                if (type(uint256).max / absoluteError > PRECISION_BASE_SQRT) {
                    num = absoluteError * PRECISION_BASE_SQRT;
                    precision = ((num) / solVal) * PRECISION_BASE_SQRT;
                } else {
                    num = absoluteError * PRECISION_BASE;
                    precision = (num) / solVal;
                }
            }
        }
        return precision;
    }

    function recordPrecision(string memory row, string memory columns, string memory fileName) internal {
        string[] memory inputs = _buildFFIRecordVars(row, columns, fileName);
        bytes memory res = vm.ffi(inputs);
        if (res.length > 0) revert("python recording issue");
        console2.log("row", row);
    }

    function runStandardPythonScript(string[] memory inputs) internal returns (uint256 resUint) {
        bytes memory res = vm.ffi(inputs);
        if (isPossiblyAnAscii(res)) resUint = decodeAsciiUint(res);
        else resUint = decodeFakeDecimalBytes(res);
        console2.log("resUint", resUint);
    }
}
