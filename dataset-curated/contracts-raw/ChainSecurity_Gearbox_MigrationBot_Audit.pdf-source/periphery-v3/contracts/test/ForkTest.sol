// SPDX-License-Identifier: UNLICENSED
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2024.
pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IAddressProvider} from "@gearbox-protocol/permissionless/contracts/interfaces/IAddressProvider.sol";

import {
    AP_ACL,
    AP_CONTRACTS_REGISTER,
    NO_VERSION_CONTROL
} from "@gearbox-protocol/permissionless/contracts/libraries/ContractLiterals.sol";

import {ACL} from "@gearbox-protocol/permissionless/contracts/market/ACL.sol";
import {IACLLegacy} from "@gearbox-protocol/permissionless/contracts/market/legacy/MarketConfiguratorLegacy.sol";
import {IContractsRegister} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IContractsRegister.sol";

abstract contract ForkTest is Test {
    IAddressProvider addressProvider;
    ACL acl;
    IACLLegacy aclLegacy;
    IContractsRegister register;
    address configurator;

    modifier onlyFork() {
        if (address(addressProvider) != address(0)) _;
    }

    function _createFork() internal {
        string memory rpcUrl = vm.envOr("FORK_RPC_URL", string(""));
        if (bytes(rpcUrl).length == 0) return;

        uint256 blockNumber = vm.envOr("FORK_BLOCK_NUMBER", type(uint256).max);
        if (blockNumber == type(uint256).max) {
            vm.createSelectFork(rpcUrl);
        } else {
            vm.createSelectFork(rpcUrl, blockNumber);
        }

        addressProvider = IAddressProvider(vm.envAddress("FORK_ADDRESS_PROVIDER"));

        aclLegacy = IACLLegacy(addressProvider.getAddressOrRevert(AP_ACL, NO_VERSION_CONTROL));
        register = IContractsRegister(addressProvider.getAddressOrRevert(AP_CONTRACTS_REGISTER, NO_VERSION_CONTROL));
        configurator = Ownable(address(aclLegacy)).owner();
        acl = new ACL(configurator);
    }

    function _grantRole(bytes32 role, address account) internal {
        acl.grantRole(role, account);
        if (role == "PAUSABLE_ADMIN") IACLLegacy(aclLegacy).addPausableAdmin(account);
        else if (role == "UNPAUSABLE_ADMIN") IACLLegacy(aclLegacy).addUnpausableAdmin(account);
    }

    function _revokeRole(bytes32 role, address account) internal {
        acl.revokeRole(role, account);
        if (role == "PAUSABLE_ADMIN") IACLLegacy(aclLegacy).removePausableAdmin(account);
        else if (role == "UNPAUSABLE_ADMIN") IACLLegacy(aclLegacy).removeUnpausableAdmin(account);
    }
}
