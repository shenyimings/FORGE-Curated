// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;
import './Interface.sol';
library Utils {
    function stringToAddress(string memory str) internal pure returns (address) {
        bytes memory strBytes = bytes(str);
        require(strBytes.length == 42, "Invalid address length");
        bytes memory addrBytes = new bytes(20);

        for (uint i = 0; i < 20; i++) {
            addrBytes[i] = bytes1(hexCharToByte(strBytes[2 + i * 2]) * 16 + hexCharToByte(strBytes[3 + i * 2]));
        }

        return address(uint160(bytes20(addrBytes)));
    }

    function hexCharToByte(bytes1 char) internal pure returns (uint8) {
        uint8 byteValue = uint8(char);
        if (byteValue >= uint8(bytes1('0')) && byteValue <= uint8(bytes1('9'))) {
            return byteValue - uint8(bytes1('0'));
        } else if (byteValue >= uint8(bytes1('a')) && byteValue <= uint8(bytes1('f'))) {
            return 10 + byteValue - uint8(bytes1('a'));
        } else if (byteValue >= uint8(bytes1('A')) && byteValue <= uint8(bytes1('F'))) {
            return 10 + byteValue - uint8(bytes1('A'));
        }
        revert("Invalid hex character");
    }

    function containTokenset(Token[] memory a, Token[] memory b) internal pure returns (bool) {
        uint k;
        for (uint i = 0; i < b.length; i++) {
            k = a.length;
            for (uint j = 0; j < a.length; j++) {
                if (isSameToken(b[i], a[j])) {
                    if (a[j].amount < b[i].amount) {
                        return false;
                    }
                    k = j;
                    break;
                }
            }
            if (k == a.length) {
                return false;
            }
        }
        return true;
    }

    function subTokenset(Token[] memory a_, Token[] memory b) internal pure returns (Token[] memory) {
        Token[] memory a = copyTokenset(a_);
        uint newLength = a.length;
        uint k;
        for (uint i = 0; i < b.length; i++) {
            k = a.length;
            for (uint j = 0; j < a.length; j++) {
                if (isSameToken(b[i], a[j])) {
                    require(a[j].amount >= b[i].amount, "a.amount less than b.amount");
                    a[j].amount -= b[i].amount;
                    if (a[j].amount == 0) {
                        newLength -= 1;
                    }
                    k = j;
                    break;
                }
            }
            require(k < a.length, "a not contains b");
        }
        Token[] memory res = new Token[](newLength);
        k = 0;
        for (uint i = 0; i < a.length; i++) {
            if (a[i].amount > 0) {
                res[k++] = a[i];
            }
        }
        return res;
    }

    function addTokenset(Token[] memory a_, Token[] memory b_) internal pure returns (Token[] memory) {
        Token[] memory a = copyTokenset(a_);
        Token[] memory b = copyTokenset(b_);
        uint k;
        uint newCnt = 0;
        for (uint i = 0; i < b.length; i++) {
            k = a.length;
            for (uint j = 0; j < a.length; j++) {
                if (isSameToken(a[j], b[i])) {
                    a[j].amount += b[i].amount;
                    k = j;
                    break;
                }
            }
            if (k == a.length) {
                if (newCnt < i) {
                    b[newCnt] = b[i];
                }
                newCnt += 1;
            }
        }
        Token[] memory res = new Token[](a.length + newCnt);
        for (uint i = 0; i < a.length; i++) {
            res[i] = a[i];
        }
        for (uint i = 0; i < newCnt; i++) {
            res[a.length + i] = b[i];
        }
        return res;
    }

    function copyTokenset(Token[] memory a) internal pure returns (Token[] memory) {
        Token[] memory b = new Token[](a.length);
        for (uint i = 0; i < a.length; i++) {
            b[i] = Token({
                chain: a[i].chain,
                symbol: a[i].symbol,
                addr: a[i].addr,
                decimals: a[i].decimals,
                amount: a[i].amount
            });
        }
        return b;
    }

    function muldivTokenset(Token[] memory a_, uint mul_factor, uint div_facotr) internal pure returns (Token[] memory) {
        Token[] memory a = copyTokenset(a_);
        for (uint i = 0; i < a.length; i++) {
            a[i].amount = a[i].amount * mul_factor / div_facotr;
        }
        return a;
    }

    function isSameToken(Token memory a, Token memory b) internal pure returns (bool) {
        return calcTokenHash(a) == calcTokenHash(b);
    }

    function calcTokenHash(Token memory token) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(token.chain, token.symbol, token.addr, token.decimals));
    }
}