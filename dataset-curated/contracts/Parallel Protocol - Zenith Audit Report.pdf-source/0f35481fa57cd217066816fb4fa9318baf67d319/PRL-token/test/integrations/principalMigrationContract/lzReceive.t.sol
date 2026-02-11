// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "test/Integrations.t.sol";

contract PrincipalMigrationContract_LzReceive_Integrations_Test is Integrations_Test {
    using OptionsBuilder for bytes;
    using OFTMsgCodec for bytes;

    bytes32 guid = hex"0000000000000000000000000000000000000000000000000000000000000001";

    function testFuzz_LzReceive_MigrateToPrincipalChain(uint256 amountToMigrate) external {
        amountToMigrate = _bound(amountToMigrate, 10, INITIAL_BALANCE);

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 0);
        (uint256 gas, uint256 value) = OptionsHelper._parseExecutorLzReceiveOption(options);

        Origin memory origin = Origin(aEid, addressToBytes32(address(peripheralMigrationContractA)), 1);
        bytes memory message = _buildMessage(users.alice.addr, amountToMigrate, mainEid, "");

        address endpoint = address(principalMigrationContract.endpoint());
        vm.startPrank(endpoint);
        principalMigrationContract.lzReceive{ value: value, gas: gas }(origin, guid, message, address(0), bytes(""));

        assertEq(prl.balanceOf(users.alice.addr), amountToMigrate);
        assertEq(prl.balanceOf(address(principalMigrationContract)), DEFAULT_PRL_SUPPLY - amountToMigrate);
    }

    function testFuzz_LzReceive_MigrateToPrincipalChain_WhenExtraMessageExistButDestEidIsMainChain(
        uint256 amountToMigrate
    )
        external
    {
        amountToMigrate = _bound(amountToMigrate, 10, INITIAL_BALANCE);

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 0);
        bytes memory extraReturnOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 0);
        (uint256 gas, uint256 value) = OptionsHelper._parseExecutorLzReceiveOption(options);

        Origin memory origin = Origin(aEid, addressToBytes32(address(peripheralMigrationContractA)), 1);
        bytes memory message = _buildMessage(users.alice.addr, amountToMigrate, mainEid, extraReturnOptions);

        address endpoint = address(principalMigrationContract.endpoint());
        vm.startPrank(endpoint);
        principalMigrationContract.lzReceive{ value: value, gas: gas }(origin, guid, message, address(0), bytes(""));

        assertEq(prl.balanceOf(users.alice.addr), amountToMigrate);
        assertEq(prl.balanceOf(address(principalMigrationContract)), DEFAULT_PRL_SUPPLY - amountToMigrate);
    }

    function testFuzz_LzReceive_MigrateToPrincipalChain_WhenDestEidIsNotMainChainButExtraReturnOptionIsEmpty(
        uint256 amountToMigrate
    )
        external
    {
        amountToMigrate = _bound(amountToMigrate, 10, INITIAL_BALANCE);

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 0);
        (uint256 gas, uint256 value) = OptionsHelper._parseExecutorLzReceiveOption(options);

        Origin memory origin = Origin(aEid, addressToBytes32(address(peripheralMigrationContractA)), 1);
        bytes memory message = _buildMessage(users.alice.addr, amountToMigrate, bEid, "");

        address endpoint = address(principalMigrationContract.endpoint());
        vm.startPrank(endpoint);
        principalMigrationContract.lzReceive{ value: value, gas: gas }(origin, guid, message, address(0), bytes(""));

        assertEq(prl.balanceOf(users.alice.addr), amountToMigrate);
        assertEq(prl.balanceOf(address(principalMigrationContract)), DEFAULT_PRL_SUPPLY - amountToMigrate);
    }

    function testFuzz_LzReceive_MigrateToAnotherChain(uint256 amountToMigrate) external {
        amountToMigrate = _bound(amountToMigrate, 10, INITIAL_BALANCE);

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(450_000, 0);
        bytes memory extraReturnOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(210_000, 0);

        MessagingFee memory fees =
            peripheralMigrationContractA.quote(bEid, users.alice.addr, amountToMigrate, options, extraReturnOptions);

        Origin memory origin = Origin(aEid, addressToBytes32(address(peripheralMigrationContractA)), 1);
        bytes memory message = _buildMessage(users.alice.addr, amountToMigrate, bEid, extraReturnOptions);
        address endpoint = address(principalMigrationContract.endpoint());
        vm.startPrank(endpoint);
        vm.deal({ account: endpoint, newBalance: fees.nativeFee });
        principalMigrationContract.lzReceive{ value: fees.nativeFee }(origin, guid, message, address(0), bytes(""));

        verifyPackets(bEid, address(peripheralPRLB));
        assertEq(peripheralPRLB.balanceOf(users.alice.addr), amountToMigrate);
        assertEq(prl.balanceOf(address(principalMigrationContract)), DEFAULT_PRL_SUPPLY - amountToMigrate);
        assertEq(prl.balanceOf(address(lockBox)), amountToMigrate);
    }
}
