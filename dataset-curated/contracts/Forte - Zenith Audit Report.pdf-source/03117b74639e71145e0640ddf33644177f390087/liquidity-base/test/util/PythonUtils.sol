/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "lib/openzeppelin-contracts/contracts/utils/Strings.sol";
import "forge-std/console2.sol";
import "forge-std/Test.sol";
import {MathLibs, packedFloat, Float128} from "src/amm/mathLibs/MathLibs.sol";
import {diffGreaterThanUint256, bytesLargerThanUint256} from "src/common/IErrors.sol";

/**
 * @title Utils for interacting with Python
 */
abstract contract PythonUtils is Test {
    using Strings for uint256;
    using MathLibs for uint256;
    using MathLibs for int256;
    using MathLibs for packedFloat;
    bytes slice;

    function _buildFFIRecordVars(
        string memory vars,
        string memory fileName,
        string memory columnNames // column names must be a single string with 5 names separated by commas without spaces. ie. "col_a,col_b,col_c,col_d,col_e"
    ) internal pure returns (string[] memory) {
        string[] memory inputs = new string[](5);
        inputs[0] = "python3";
        inputs[1] = "script/python/record_vars.py";
        inputs[2] = vars;
        inputs[3] = fileName;
        inputs[4] = columnNames;
        return inputs;
    }

    function _buildFFIPlotCSV(
        string memory fileName,
        string memory columnNames // column names must be a single string with 5 names separated by commas without spaces. ie. "col_a,col_b,col_c,col_d,col_e"
    ) internal pure returns (string[] memory) {
        string[] memory inputs = new string[](4);
        inputs[0] = "python3";
        inputs[1] = "script/python/plot_csv.py";
        inputs[2] = columnNames;
        inputs[3] = fileName;
        return inputs;
    }
    function _buildBaseFFIsqrt(uint256 x) internal pure returns (string[] memory) {
        string[] memory inputs = new string[](3);
        inputs[0] = "python3";
        inputs[1] = "./script/python/sqrt.py";
        inputs[2] = x.toString();
        return inputs;
    }

    function _buildFFICalculateLogarithmNaturalWAD2(uint x) internal pure returns (string[] memory) {
        string[] memory inputs = new string[](3);
        inputs[0] = "python3";
        inputs[1] = "./script/python/ln_wad_2.py";
        inputs[2] = x.toString();
        return inputs;
    }

    function _buildWriteCurveToCSV(uint256 i, uint256 x, uint256 b, uint256 c, uint256 id) internal pure returns (string[] memory) {
        string[] memory inputs = new string[](7);
        inputs[0] = "python3";
        inputs[1] = "./script/python/recordCurveTest.py";
        inputs[2] = i.toString();
        inputs[3] = x.toString();
        inputs[4] = b.toString();
        inputs[5] = c.toString();
        inputs[6] = id.toString();
        return inputs;
    }

    function _buildFFIDiv512ByPowerOf2(uint a0, uint a1, uint8 n) internal pure returns (string[] memory) {
        string[] memory inputs = new string[](5);
        inputs[0] = "python3";
        inputs[1] = "script/python/mathLibs/div_512_by_power_of_2.py";
        inputs[2] = a0.toString();
        inputs[3] = a1.toString();
        inputs[4] = uint(n).toString();
        return inputs;
    }

    function _buildFFIDiv512x512(uint a0, uint a1, uint256 b0, uint256 b1) internal pure returns (string[] memory) {
        string[] memory inputs = new string[](6);
        inputs[0] = "python3";
        inputs[1] = "script/python/mathLibs/div_512_x_512.py";
        inputs[2] = a0.toString();
        inputs[3] = a1.toString();
        inputs[4] = b0.toString();
        inputs[5] = b1.toString();
        return inputs;
    }

    function _buildFFIDiv512x256ResultIn512(uint a0, uint a1, uint b) internal pure returns (string[] memory) {
        string[] memory inputs = new string[](5);
        inputs[0] = "python3";
        inputs[1] = "script/python/mathLibs/div_512_by_256_result_in_512.py";
        inputs[2] = a0.toString();
        inputs[3] = a1.toString();
        inputs[4] = b.toString();
        return inputs;
    }

    function _buildFFIConvertToRaw512(uint a0, uint a1) internal pure returns (string[] memory) {
        string[] memory inputs = new string[](4);
        inputs[0] = "python3";
        inputs[1] = "script/python/mathLibs/convert_to_raw_512.py";
        inputs[2] = a0.toString();
        inputs[3] = a1.toString();
        return inputs;
    }

    function _buildFFIQuadraticEquation(uint a, uint b, uint c, bool isBNegative) internal pure returns (string[] memory) {
        string[] memory inputs = new string[](6);
        inputs[0] = "python3";
        inputs[1] = "script/python/mathLibs/quadratic_equation.py";
        inputs[2] = vm.toString(a);
        inputs[3] = vm.toString(b);
        inputs[4] = vm.toString(c);
        inputs[5] = vm.toString(isBNegative ? 1 : 0);
        return inputs;
    }

    function _buildFIICalculateLastRevenueClaim(
        uint256 hn,
        uint256 wj,
        uint256 r_hat,
        uint256 w_hat
    ) internal pure returns (string[] memory) {
        string[] memory inputs = new string[](6);
        inputs[0] = "python3";
        inputs[1] = "lib/liquidity-base/script/python/equations/calculate_last_revenue_claim.py";
        inputs[2] = vm.toString(hn);
        inputs[3] = vm.toString(wj);
        inputs[4] = vm.toString(r_hat);
        inputs[5] = vm.toString(w_hat);
        return inputs;
    }

    /**
     * compares if 2 uints are similar enough.
     * @param x value to compare against *y*
     * @param y value to compare against *x*
     * @param maxTolerance the maximum allowed difference tolerance based on the precision
     * @param toleranceDenom the denom of the tolerance value. For instance, 10 ** 11.
     * @return withinTolerance true if the difference expressed as a normalized value is less or equal than the tolerance.
     */
    function areWithinTolerance(uint x, uint y, uint8 maxTolerance, uint256 toleranceDenom) internal pure returns (bool withinTolerance) {
        /// we calculate the absolute difference to avoid overflow/underflow
        uint diff = absoluteDiff(x, y);
        /// we calculate difference percentage as diff/(smaller number unless 0) to get the bigger difference "percentage".
        withinTolerance = true;
        if (diff != 0) {
            packedFloat scaled = int(diff).toPackedFloat(-18).mul(int(toleranceDenom).toPackedFloat(-18));
            console2.log("first");
            uint relativeDiff = uint(
                scaled
                    .div(
                        int(
                            x > y
                                ? y == 0
                                    ? x
                                    : y
                                : x == 0
                                    ? y
                                    : x
                        ).toPackedFloat(-2)
                    )
                    .convertpackedFloatToWAD()
            );
            console2.log("second");
            if (relativeDiff > maxTolerance) withinTolerance = false;
        }
    }

    /**
     * Tries to find the decimal place from the python output in the tests so that we can create a decimal places long enough to hold the int
     * @param pythonReturn the python output that was returned from the ffi command
     * @return uint This is the number of places that should house the decimal digits precision. Otherwise 0 if not a decimal.
     */
    function findDecimalPlaces(bytes memory pythonReturn) internal pure returns (uint) {
        for (uint i; i < pythonReturn.length; i++) {
            if (pythonReturn[i] == 0x2e) {
                return pythonReturn.length - i;
            }
        }
        return 0;
    }

    /**
     * @dev calculates the difference between 2 uints without risk of overflow/underflow
     * @param x uint
     * @param y uint
     * @return diff the absolute difference between *x* and *y*
     */
    function absoluteDiff(uint x, uint y) public pure returns (uint diff) {
        diff = x > y ? x - y : y - x;
    }

    /**
     * @dev gets a bytes variable and checks if it is an ascii value or not.
     * @notice this algorithm is 100% accurate in the negative case, but false
     * positives are possible. This is because if all the bytes are between 0x30
     * and 0x39, then the code will say it is an ascii number, but there will be
     * cases where they are not. For instance, the decimal number 0x3333333333333333
     * will be interpreted as an ascii even though it might not be.
     * @param _bytes the variable to decide if it is a possible ascii.
     * @return true if it is a possible ascii.
     */
    function isPossiblyAnAscii(bytes memory _bytes) public pure returns (bool) {
        if (_bytes.length > 48) return true;
        bool isAscii = true;
        for (uint i; i < _bytes.length; i++) {
            if (uint(uint8(_bytes[i])) < 0x30 || uint(uint8(_bytes[i])) > 0x39) {
                isAscii = false;
                break;
            }
        }
        return isAscii;
    }

    /**
     * @dev gets a bytes variable and checks if it is a hex number expressed in ascii.
     * @notice this algorithm is 100% accurate in the negative case, but false
     * positives are possible. This is because if the first 2 bytes end up being
     * 0x3078 which is the ascii for "0x", and then all the following bytes are either
     * between 0x30 and 0x39 (asciis for numbers) or between 0x61 and 0x66 (asciis for
     * letters a to f), then it might say it's an ascii even if it is not.
     * @param _bytes the variable to decide if it is a possible ascii.
     * @return true if it is a possible ascii.
     */
    function isPossiblyAnAsciiHex(bytes memory _bytes) public pure returns (bool) {
        if (!(uint8(_bytes[0]) == 0x30 && uint8(_bytes[1]) == 0x78)) return false;
        bool isAscii = true;
        for (uint i = 2; i < _bytes.length; i++) {
            if (
                !((uint(uint8(_bytes[i])) >= 0x30 && uint(uint8(_bytes[i])) <= 0x39) ||
                    (uint(uint8(_bytes[i])) >= 0x61 && uint(uint8(_bytes[i])) <= 0x66))
            ) {
                isAscii = false;
                break;
            }
        }
        return isAscii;
    }

    /**
     * @dev decodes an ascii number to return the uint
     * @param ascii the number to convert to uint
     * @return decodedUint
     */
    function decodeAsciiUint(bytes memory ascii) public pure returns (uint256 decodedUint) {
        for (uint i; i < ascii.length; i++) {
            uint units = uint(uint8(ascii[i])) - 0x30;
            if (i != ascii.length - 1) decodedUint += units * (10 ** ((ascii.length - i - 1)));
            else decodedUint += units;
        }
    }

    /**
     * @dev converts bytes into a uint256
     * @notice that bytes should not be greater than 32 so it doesn't overflow
     * @param hexBytes the bytes to convert to uint256
     * @return decodedUint
     */
    function fromBytesToUint(bytes memory hexBytes) public pure returns (uint256 decodedUint) {
        if (hexBytes.length > 32) revert bytesLargerThanUint256();
        for (uint i; i < hexBytes.length; i++) {
            uint value = uint(uint8(hexBytes[i]));
            console2.log(value);
            if (i != hexBytes.length - 1) decodedUint += value * (256 ** ((hexBytes.length - i - 1)));
            else decodedUint += value;
        }
        console2.log("end");
    }

    /**
     * @dev decodes an ascii hex number to return the uint
     * @param ascii the number to convert to uint
     * @return decodedUint
     */
    function decodeAsciiUintHex(bytes memory ascii) public pure returns (uint256 decodedUint) {
        for (uint i; i < ascii.length; i++) {
            uint value;
            if (ascii[i] > 0x39) value = (uint(uint8(ascii[i])) - 0x61) + 10;
            else value = uint(uint8(ascii[i])) - 0x30;
            if (i != ascii.length - 1) decodedUint += value * (16 ** ((ascii.length - i - 1)));
            else decodedUint += value;
        }
    }

    /**
     * @dev decodes a byte variable trying to express a decimal number. For instance 0x297462 = 297462.
     * @param bytesDecimal the byte variable to convert to uint.
     * @return decodedUint the uint that the bytes variable was trying to imply.
     */
    function decodeFakeDecimalBytes(bytes memory bytesDecimal) public pure returns (uint256 decodedUint) {
        for (uint i; i < bytesDecimal.length; i++) {
            uint tens = ((uint(uint8(bytesDecimal[i])) / 16) * 10);
            uint units = (uint(uint8(bytesDecimal[i])) - ((uint(uint8(bytesDecimal[i])) / 16) * 16));
            if (i != bytesDecimal.length - 1) decodedUint += (tens + units) * (10 ** ((bytesDecimal.length - i - 1) * 2));
            else decodedUint += (tens + units);
        }
    }

    function concatUints(uint256[] memory vars) internal pure returns (string memory str) {
        string[] memory strs = new string[](vars.length);
        for (uint i = 0; i < vars.length; i++) {
            strs[i] = i < vars.length - 1 ? string.concat(vars[i].toString(), ",") : vars[i].toString();
        }
        for (uint i = 0; i < vars.length; i++) {
            str = string.concat(str, strs[i]);
        }
    }
}
