// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

/**
 * @title TBC Data Structures
 * @dev All TBC definitions can be found here.
 * @author  @oscarsernarosero @mpetersoCode55 @cirsteve
 */

/// TBC Enum

enum TBCType {
    ALTBC,
    URQTBC
}

struct FeeInfo {
    uint16 _lpFee;
    uint16 _protocolFee;
    address _protocolFeeCollector;
}
