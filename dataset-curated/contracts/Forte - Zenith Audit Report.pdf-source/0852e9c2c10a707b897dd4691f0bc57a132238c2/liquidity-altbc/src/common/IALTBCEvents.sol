// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "liquidity-base/src/common/IEvents.sol";
import {ALTBCInput} from "src/amm/ALTBC.sol";

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

event LiquidityDeposited(
    address indexed _sender, 
    uint256 indexed _tokenId, 
    uint256 _A,
    uint256 _B
);

event LiquidityWithdrawn(
    address _sender,
    uint256 _tokenId, 
    uint256 _A, 
    uint256 _B, 
    uint256 _revenue
);


event InitialLiquidityPositionMinted(
    address indexed _sender,
    uint256 indexed _tokenId,
    uint256 _initialX
);