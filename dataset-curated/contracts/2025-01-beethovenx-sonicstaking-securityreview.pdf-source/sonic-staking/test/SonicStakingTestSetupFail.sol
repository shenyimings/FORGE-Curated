// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {SonicStaking} from "src/SonicStaking.sol";

import {ISFC} from "src/interfaces/ISFC.sol";
import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";

contract SonicStakingTestSetupFail is Test {
    address SONIC_STAKING_CLAIMOR;
    address SONIC_STAKING_OPERATOR;
    address SONIC_STAKING_OWNER;
    address SONIC_STAKING_ADMIN;
    SonicStaking sonicStaking;

    string SONIC_FORK_URL = "https://rpc.soniclabs.com";
    uint256 INITIAL_FORK_BLOCK_NUMBER = 10000;

    uint256 sonicFork;

    enum WithdrawKind {
        POOL,
        VALIDATOR
    }

    function setUp() public {}

    function testZeroSFC() public virtual {
        address TREASURY_ADDRESS = 0xa1E849B1d6c2Fd31c63EEf7822e9E0632411ada7;
        ISFC SFC = ISFC(address(0));

        sonicFork = vm.createSelectFork(SONIC_FORK_URL, INITIAL_FORK_BLOCK_NUMBER);

        // the Upgrades.deployUUPSProxy call reverts with two errors. One internally and one with our require in the initialize() function
        vm.expectRevert();
        vm.expectRevert(abi.encodeWithSelector(SonicStaking.SFCAddressCannotBeZero.selector));
        Upgrades.deployUUPSProxy(
            "SonicStaking.sol:SonicStaking", abi.encodeCall(SonicStaking.initialize, (SFC, TREASURY_ADDRESS))
        );
    }

    function testZeroTreasury() public virtual {
        address TREASURY_ADDRESS = address(0);
        ISFC SFC = ISFC(0xFC00FACE00000000000000000000000000000000);

        sonicFork = vm.createSelectFork(SONIC_FORK_URL, INITIAL_FORK_BLOCK_NUMBER);

        // the Upgrades.deployUUPSProxy call reverts with two errors. One internally and one with our require in the initialize() function
        vm.expectRevert();
        vm.expectRevert(abi.encodeWithSelector(SonicStaking.SFCAddressCannotBeZero.selector));
        Upgrades.deployUUPSProxy(
            "SonicStaking.sol:SonicStaking", abi.encodeCall(SonicStaking.initialize, (SFC, TREASURY_ADDRESS))
        );
    }
}
