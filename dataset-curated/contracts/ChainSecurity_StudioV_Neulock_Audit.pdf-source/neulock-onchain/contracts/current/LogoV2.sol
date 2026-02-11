// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.28;

import {INeuLogoV2} from "../interfaces/ILogoV2.sol";

/**
 * @title NeuLogoV2
 * @author Lucas Neves (lneves.eth) for Studio V
 * @notice Generates SVG logos for NEU tokens with customizable colors and series name.
 * @dev Stateless utility contract for on-chain SVG logo generation, used by Neulock.
 * @custom:security-contact security@studiov.tech
 */
contract NeuLogoV2 is INeuLogoV2 {
    string constant private _BEFORE_FOREGROUND_COLOR = '<svg width="500" height="500" viewBox="0 0 500 500" zoomAndPan="magnify" preserveAspectRatio="xMidYMid" version="1.0" xmlns="http://www.w3.org/2000/svg"><style>.f { fill: #';
    string constant private _BEFORE_BACKGROUND_COLOR = '; } .b { fill: #';
    string constant private _BEFORE_ACCENT_COLOR = '; } .a { fill: #';
    string constant private _BEFORE_TOKEN_ID = '; }</style><rect class="b" x="0" y="0" width="500" height="500" /><g transform="scale(0.8) translate(50 10)"><path class="f" d="M 250,23 47,359 l 203,118 203,-118 z" /><path class="a" d="m 250,177 a 53,53 0 0 0 -53,53 53,53 0 0 0 38,50.82812 V 388 l 15,14 13.96484,-13.03516 L 254,379 v -13 l 7.5,-7.5 -7.5,-7.5 v -13 l 7.5,-7.5 -7.5,-7.5 v -9 l 11,-11 V 280.82812 A 53,53 0 0 0 303,230 53,53 0 0 0 250,177 Z m 0,27 a 16,16 0 0 1 16,16 16,16 0 0 1 -16,16 16,16 0 0 1 -16,-16 16,16 0 0 1 16,-16 z" /></g><rect class="f" x="0" y="440" width="500" height="500" /><style>@font-face {font-family: MajorMono; src: url(data:font/woff2;utf-8;base64,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);}</style><text class="b" font-family="MajorMono" font-weight="400" x="250" y="480" font-size="28" text-anchor="middle">neu #';
    string constant private _BEFORE_SERIES_NAME = ' ';
    string constant private _TAIL = '</text></svg>';

    // Adapted from https://ethereum.stackexchange.com/a/126928
    function _byteToHex(uint8 b) private pure returns (string memory) {
        bytes memory _base = "0123456789abcdef";

        bytes memory converted = new bytes(2);

        converted[0] = _base[b / 16];
        converted[1] = _base[b % 16];

        return string(converted);
    }

    function _rgb565ToHex(uint16 color) private pure returns (string memory) {
        uint8 r = uint8((color & 0xF800) >> 8);
        uint8 g = uint8((color & 0x07E0) >> 3);
        uint8 b = uint8((color & 0x001F) << 3);

        return string(string.concat(
            _byteToHex(r),
            _byteToHex(g),
            _byteToHex(b)
        ));
    }

    function _toLowerCase(string memory str) private pure returns (string memory) {
        bytes memory bStr = bytes(str);
        for (uint i = 0; i < bStr.length; i++) {
            if ((uint8(bStr[i]) >= 65) && (uint8(bStr[i]) <= 90)) {
                bStr[i] = bytes1(uint8(bStr[i]) + 32);
            }
        }
        return string(bStr);
    }

    /**
     * @notice Generates an SVG logo for a NEU token with the specified parameters.
     * @dev Returns a complete SVG as a string, with specified colors and series name. Colors are provided in RGB565 format.
     * @param tokenId The string representation of the token ID to display in the logo.
     * @param seriesName The series name to display in the logo (converted to lowercase).
     * @param foregroundColor The foreground color in RGB565 format.
     * @param backgroundColor The background color in RGB565 format.
     * @param accentColor The accent color in RGB565 format.
     * @return svg The generated SVG logo as a string.
     */
    function makeLogo(string calldata tokenId, string calldata seriesName, uint16 foregroundColor, uint16 backgroundColor, uint16 accentColor) external pure returns (string memory) {
        string memory part1 = string(string.concat(
            _BEFORE_FOREGROUND_COLOR,
            _rgb565ToHex(foregroundColor),
            _BEFORE_BACKGROUND_COLOR,
            _rgb565ToHex(backgroundColor)
        ));

        string memory part2 = string(string.concat(
            _BEFORE_ACCENT_COLOR,
            _rgb565ToHex(accentColor),
            _BEFORE_TOKEN_ID
        ));

        string memory part3 = string(string.concat(
            tokenId,
            _BEFORE_SERIES_NAME,
            _toLowerCase(seriesName), // We're using a lowercase-only font
            _TAIL
        ));

        return string(string.concat(
            part1,
            part2,
            part3
        ));
    }
}