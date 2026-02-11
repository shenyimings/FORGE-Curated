// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {Vm} from "forge-std/Test.sol";

import {ICowSettlement} from "src/interface/ICowSettlement.sol";
import {ICowAuthentication} from "src/vendored/ICowAuthentication.sol";

contract CowProtocolMock {
    ICowSettlement public immutable SETTLEMENT;
    ICowAuthentication public immutable AUTHENTICATOR;

    Vm private vm;

    constructor(Vm _vm, address mockSettlementAddress, address mockAuthenticatorAddress) {
        vm = _vm;
        SETTLEMENT = ICowSettlement(mockSettlementAddress);
        AUTHENTICATOR = ICowAuthentication(mockAuthenticatorAddress);
        mockAuthenticator();
    }

    function mockAuthenticator() private {
        vm.mockCall(address(SETTLEMENT), abi.encodeCall(ICowSettlement.authenticator, ()), abi.encode(AUTHENTICATOR));
    }

    function mockIsSolver(address solver, bool isSolver) public {
        vm.mockCall(address(AUTHENTICATOR), abi.encodeCall(ICowAuthentication.isSolver, (solver)), abi.encode(isSolver));
    }
}
