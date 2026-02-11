// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";

contract BaseTestHelper is Test {
    uint256 internal ownerSk = 1;
    uint256 internal user1Sk = 2;
    uint256 internal user2Sk = 3;
    uint256 internal operatorSk = 4;
    uint256 internal operator2Sk = 5;
    uint256 internal validatorSk = 6;
    uint256 internal serviceFeeRecipientSk = 7;

    address public immutable OWNER = vm.addr(ownerSk);
    address public immutable USER1 = vm.addr(user1Sk);
    address public immutable USER2 = vm.addr(user2Sk);
    address public immutable OPERATOR = vm.addr(operatorSk);
    address public immutable OPERATOR2 = vm.addr(operator2Sk);
    address public immutable VALIDATOR = vm.addr(validatorSk);
    address public immutable SERVICE_FEE_RECIPIENT = vm.addr(serviceFeeRecipientSk);
}
