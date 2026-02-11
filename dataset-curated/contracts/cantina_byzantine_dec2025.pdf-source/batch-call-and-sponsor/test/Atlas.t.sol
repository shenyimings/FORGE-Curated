// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "forge-std/Test.sol";
import "../src/Atlas.sol";
import "./Deadcoin.sol";
import {console} from "forge-std/console.sol";

// Need to copy those constant from Atlas.sol otherwise trying to read them from the contract fail
bytes32 constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(uint256 chainId,address verifyingContract)");
bytes32 constant CALL_TYPEHASH = keccak256("Call(address to,uint256 value,bytes data)");
bytes32 constant EXECUTE_CALLS_TYPEHASH =
    keccak256("ExecuteCalls(Call[] calls,uint256 deadline,uint256 nonce)Call(address to,uint256 value,bytes data)");
bytes32 constant EXECUTE_CALL_TYPEHASH =
    keccak256("ExecuteCall(Call call,uint256 deadline,uint256 nonce)Call(address to,uint256 value,bytes data)");

contract AtlasTest is Test {
    Atlas public atlas;
    Deadcoin public deadcoin;

    // Initial Deadcoin balance for Alice
    uint256 constant INITIAL_AMOUNT = 100;

    // Alice's address and private key (EOA with no initial contract code).
    Vm.Wallet alice = vm.createWallet("alice");

    // Bob's address and private key (Bob will execute transactions on Alice's behalf).
    Vm.Wallet bob = vm.createWallet("bob");

    // Charlie's address and private key (Charlie will try to call Alice's function without her signature).
    Vm.Wallet charlie = vm.createWallet("charlie");

    function setUp() public {
        atlas = new Atlas();

        // Alice signs an authorization
        Vm.SignedDelegation memory signedDelegation = vm.signDelegation(address(atlas), alice.privateKey);
        // Bob send the authorization signed by Alice
        vm.prank(bob.addr);
        vm.attachDelegation(signedDelegation);

        // We create our ERC20 token
        deadcoin = new Deadcoin();

        vm.prank(bob.addr);
        deadcoin.transfer(alice.addr, INITIAL_AMOUNT);
    }

    // Utilitary function to get the digest of several calls
    function getDigest(Atlas.Call[] memory calls, uint256 deadline, uint256 cnonce)
        internal
        view
        returns (bytes32 digest)
    {
        bytes32[] memory callStructHashes = new bytes32[](calls.length);
        for (uint256 i; i < calls.length; ++i) {
            callStructHashes[i] =
                keccak256(abi.encode(CALL_TYPEHASH, calls[i].to, calls[i].value, keccak256(calls[i].data)));
        }

        // Retrieve eip-712 digest
        bytes32 encodeData = keccak256(abi.encodePacked(callStructHashes));
        bytes32 hashStruct = keccak256(abi.encode(EXECUTE_CALLS_TYPEHASH, encodeData, deadline, cnonce));

        // IMPORTANT!! `Atlas(alice.addr).DOMAIN_SEPARATOR()` need ot be called from alice bytecodes because it doesn't have the same address as the atlas deployed one.
        digest = keccak256(abi.encodePacked(hex"1901", Atlas(alice.addr).DOMAIN_SEPARATOR(), hashStruct));
    }

    // Utilitary function to get the digest of one single call
    function getDigest(Atlas.Call memory call, uint256 deadline, uint256 cnonce)
        internal
        view
        returns (bytes32 digest)
    {
        // Retrieve eip-712 digest
        bytes32 encodeData = keccak256(abi.encode(CALL_TYPEHASH, call.to, call.value, keccak256(call.data)));
        bytes32 hashStruct = keccak256(abi.encode(EXECUTE_CALL_TYPEHASH, encodeData, deadline, cnonce));

        // IMPORTANT!! `Atlas(alice.addr).DOMAIN_SEPARATOR()` need ot be called from alice bytecodes because it doesn't have the same address as the atlas deployed one.
        digest = keccak256(abi.encodePacked(hex"1901", Atlas(alice.addr).DOMAIN_SEPARATOR(), hashStruct));
    }

    // Sucess calls execution with one call
    function test_executeSuccesfull(uint256 amount) public {
        vm.assume(amount <= INITIAL_AMOUNT);

        Atlas.Call memory call =
            IAtlas.Call({to: address(deadcoin), value: 0, data: abi.encodeCall(deadcoin.transfer, (bob.addr, amount))});
        Atlas.Call[] memory calls = new IAtlas.Call[](1);
        calls[0] = call;

        uint256 deadline = block.timestamp + 1;
        uint256 cnonce = vm.randomUint();

        bytes32 digest = getDigest(calls, deadline, cnonce);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alice, digest);

        vm.prank(bob.addr);
        Atlas(alice.addr).executeCalls(calls, deadline, cnonce, v, r, s);

        // Check balance has decreased
        uint256 balance = deadcoin.balanceOf(alice.addr);
        assert(balance == INITIAL_AMOUNT - amount);
    }

    // Sucess calls execution with two calls
    function test_executeSuccesfullMulticalls(uint256 amount) public {
        vm.assume(amount <= INITIAL_AMOUNT / 2);

        Atlas.Call memory call =
            IAtlas.Call({to: address(deadcoin), value: 0, data: abi.encodeCall(deadcoin.transfer, (bob.addr, amount))});
        Atlas.Call[] memory calls = new IAtlas.Call[](2);
        calls[0] = call;
        calls[1] = call;

        uint256 deadline = block.timestamp + 1;
        uint256 cnonce = vm.randomUint();

        bytes32 digest = getDigest(calls, deadline, cnonce);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alice, digest);

        vm.prank(bob.addr);
        Atlas(alice.addr).executeCalls(calls, deadline, cnonce, v, r, s);

        // Check balance has decreased
        uint256 balance = deadcoin.balanceOf(alice.addr);
        assert(balance == INITIAL_AMOUNT - (2 * amount));
    }

    // Sending the wrong signature
    function test_executeFail(uint256 amount) public {
        vm.assume(amount <= INITIAL_AMOUNT);

        Atlas.Call memory call =
            IAtlas.Call({to: address(deadcoin), value: 0, data: abi.encodeCall(deadcoin.transfer, (bob.addr, amount))});
        Atlas.Call[] memory calls = new IAtlas.Call[](1);
        calls[0] = call;

        uint256 deadline = block.timestamp + 1;
        uint256 cnonce = vm.randomUint();

        bytes32 digest = getDigest(calls, deadline, cnonce);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(charlie, digest);

        vm.expectRevert(IAtlas.InvalidSigner.selector);

        vm.prank(charlie.addr);
        Atlas(alice.addr).executeCalls(calls, deadline, cnonce, v, r, s);

        // Check balance hasn't changed
        uint256 balance = deadcoin.balanceOf(alice.addr);
        assert(balance == INITIAL_AMOUNT);
    }

    // Replaying the same call twice with the same signature
    function test_replayFail(uint256 amount) public {
        vm.assume(amount <= INITIAL_AMOUNT);

        Atlas.Call memory call =
            IAtlas.Call({to: address(deadcoin), value: 0, data: abi.encodeCall(deadcoin.transfer, (bob.addr, amount))});
        Atlas.Call[] memory calls = new IAtlas.Call[](1);
        calls[0] = call;

        uint256 deadline = block.timestamp + 1;
        uint256 cnonce = vm.randomUint();

        bytes32 digest = getDigest(calls, deadline, cnonce);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alice, digest);

        vm.prank(bob.addr);
        Atlas(alice.addr).executeCalls(calls, deadline, cnonce, v, r, s);

        vm.expectRevert(IAtlas.NonceAlreadyUsed.selector);

        vm.prank(bob.addr);
        Atlas(alice.addr).executeCalls(calls, deadline, cnonce, v, r, s);

        // Check balance has only decreased by 10
        uint256 balance = deadcoin.balanceOf(alice.addr);
        assert(balance == INITIAL_AMOUNT - amount);
    }

    // Sending expired call with correct signature so the call should fail
    function test_expiredDeadline(uint256 amount) public {
        vm.assume(amount <= INITIAL_AMOUNT);

        Atlas.Call memory call =
            IAtlas.Call({to: address(deadcoin), value: 0, data: abi.encodeCall(deadcoin.transfer, (bob.addr, amount))});
        Atlas.Call[] memory calls = new IAtlas.Call[](1);
        calls[0] = call;

        uint256 deadline = block.timestamp + 1;
        uint256 cnonce = vm.randomUint();

        bytes32 digest = getDigest(calls, deadline, cnonce);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alice, digest);

        skip(2);
        vm.expectRevert(IAtlas.ExpiredSignature.selector);
        vm.prank(bob.addr);
        Atlas(alice.addr).executeCalls(calls, deadline, cnonce, v, r, s);

        // Check balance hasn't changed
        uint256 balance = deadcoin.balanceOf(alice.addr);
        assert(balance == INITIAL_AMOUNT);
    }

    // Sucessfully call `executeCall` with a simple call
    function test_simpleCall(uint256 amount) public {
        vm.assume(amount <= INITIAL_AMOUNT);

        Atlas.Call memory call =
            IAtlas.Call({to: address(deadcoin), value: 0, data: abi.encodeCall(deadcoin.transfer, (bob.addr, amount))});

        uint256 deadline = block.timestamp + 1;
        uint256 cnonce = vm.randomUint();

        bytes32 digest = getDigest(call, deadline, cnonce);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alice, digest);

        vm.prank(bob.addr);
        Atlas(alice.addr).executeCall(call, deadline, cnonce, v, r, s);

        // Check balance has decreased
        uint256 balance = deadcoin.balanceOf(alice.addr);
        assert(balance == INITIAL_AMOUNT - amount);
    }

    // Send an invalid signature with our simple call
    function test_simpleCallInvalidSignature(uint256 amount) public {
        vm.assume(amount <= INITIAL_AMOUNT);

        Atlas.Call memory call =
            IAtlas.Call({to: address(deadcoin), value: 0, data: abi.encodeCall(deadcoin.transfer, (bob.addr, amount))});

        uint256 deadline = block.timestamp + 1;
        uint256 cnonce = vm.randomUint();

        bytes32 digest = getDigest(call, deadline, cnonce);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(charlie, digest);

        vm.expectRevert(IAtlas.InvalidSigner.selector);
        vm.prank(charlie.addr);
        Atlas(alice.addr).executeCall(call, deadline, cnonce, v, r, s);

        // Check balance hasn't changed
        uint256 balance = deadcoin.balanceOf(alice.addr);
        assert(balance == INITIAL_AMOUNT);
    }

    // Send an invalid signature with our simple call
    function test_simpleCallReplayFail(uint256 amount) public {
        vm.assume(amount <= INITIAL_AMOUNT);

        Atlas.Call memory call =
            IAtlas.Call({to: address(deadcoin), value: 0, data: abi.encodeCall(deadcoin.transfer, (bob.addr, amount))});

        uint256 deadline = block.timestamp + 1;
        uint256 cnonce = vm.randomUint();

        bytes32 digest = getDigest(call, deadline, cnonce);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alice, digest);

        vm.prank(bob.addr);
        Atlas(alice.addr).executeCall(call, deadline, cnonce, v, r, s);

        vm.expectRevert(IAtlas.NonceAlreadyUsed.selector);
        vm.prank(bob.addr);
        Atlas(alice.addr).executeCall(call, deadline, cnonce, v, r, s);

        // Check balance has only decreased by 10
        uint256 balance = deadcoin.balanceOf(alice.addr);
        assert(balance == INITIAL_AMOUNT - amount);
    }

    // Alice can call her own EOA code should be sucessful
    function test_executeOwnCall(uint256 amount) public {
        vm.assume(amount <= INITIAL_AMOUNT);

        Atlas.Call memory call =
            IAtlas.Call({to: address(deadcoin), value: 0, data: abi.encodeCall(deadcoin.transfer, (bob.addr, amount))});

        vm.prank(alice.addr);
        Atlas(alice.addr).executeCall(call);

        // Check balance has only decreased by 10
        uint256 balance = deadcoin.balanceOf(alice.addr);
        assert(balance == INITIAL_AMOUNT - amount);
    }

    // Alice can call her own EOA code should be sucessful with multiple calls
    function test_executeOwnCallMultipleCalls(uint256 amount) public {
        vm.assume(amount <= INITIAL_AMOUNT / 2);

        Atlas.Call memory call =
            IAtlas.Call({to: address(deadcoin), value: 0, data: abi.encodeCall(deadcoin.transfer, (bob.addr, amount))});
        Atlas.Call[] memory calls = new IAtlas.Call[](2);
        calls[0] = call;
        calls[1] = call;

        vm.prank(alice.addr);
        Atlas(alice.addr).executeCalls(calls);

        // Check balance has decreased
        uint256 balance = deadcoin.balanceOf(alice.addr);
        assert(balance == INITIAL_AMOUNT - (2 * amount));
    }

    // Bob should not be able to call Alice's function without her signature
    function test_bobFailCall(uint256 amount) public {
        vm.assume(amount <= INITIAL_AMOUNT);

        Atlas.Call memory call =
            IAtlas.Call({to: address(deadcoin), value: 0, data: abi.encodeCall(deadcoin.transfer, (bob.addr, amount))});
        Atlas.Call[] memory calls = new IAtlas.Call[](2);
        calls[0] = call;
        calls[1] = call;

        vm.expectRevert(IAtlas.Unauthorized.selector);
        vm.prank(bob.addr);
        Atlas(alice.addr).executeCalls(calls);

        vm.expectRevert(IAtlas.Unauthorized.selector);
        vm.prank(bob.addr);
        Atlas(alice.addr).executeCall(call);

        // Check balance not have changed
        uint256 balance = deadcoin.balanceOf(alice.addr);
        assert(balance == INITIAL_AMOUNT);
    }

    // Alice can't call an unexisting function
    function test_executeCallReverted() public {
        Atlas.Call memory call =
            IAtlas.Call({to: address(deadcoin), value: 0, data: abi.encodeWithSignature("nonExistentFunction()")});

        vm.expectRevert(IAtlas.CallReverted.selector);
        vm.prank(alice.addr);
        Atlas(alice.addr).executeCall(call);
    }
}
