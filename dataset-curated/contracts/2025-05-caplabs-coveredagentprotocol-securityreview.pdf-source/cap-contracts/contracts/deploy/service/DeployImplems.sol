// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import { AccessControl } from "../../access/AccessControl.sol";

import { Delegation } from "../../delegation/Delegation.sol";

import { FeeAuction } from "../../feeAuction/FeeAuction.sol";
import { Lender } from "../../lendingPool/Lender.sol";
import { DebtToken } from "../../lendingPool/tokens/DebtToken.sol";

import { Oracle } from "../../oracle/Oracle.sol";
import { CapToken } from "../../token/CapToken.sol";
import { StakedCap } from "../../token/StakedCap.sol";
import { ImplementationsConfig } from "../interfaces/DeployConfigs.sol";

contract DeployImplems {
    function _deployImplementations() internal returns (ImplementationsConfig memory d) {
        d.accessControl = address(new AccessControl());
        d.lender = address(new Lender());
        d.delegation = address(new Delegation());
        d.capToken = address(new CapToken());
        d.stakedCap = address(new StakedCap());
        d.oracle = address(new Oracle());
        d.debtToken = address(new DebtToken());
        d.feeAuction = address(new FeeAuction());
    }
}
