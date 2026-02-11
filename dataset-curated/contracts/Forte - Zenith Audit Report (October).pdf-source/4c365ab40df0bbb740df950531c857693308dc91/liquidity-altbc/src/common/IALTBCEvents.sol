// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import "liquidity-base/src/common/IEvents.sol";
import {ALTBCInput, ALTBCDef} from "src/amm/ALTBC.sol";

event ALTBCFactoryDeployed(string _version);

event ALTBCPoolDeployed(
    address indexed _xToken,
    address indexed _yToken,
    string _version,
    uint16 _lpFee,
    uint16 _protocolFee,
    address _protocolFeeCollector,
    ALTBCInput _tbcInput
);

event ALTBCCurveState(ALTBCDef altbc, packedFloat x);
