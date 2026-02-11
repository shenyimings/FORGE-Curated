// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import {ClaimVault} from "../src/ClaimVault.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ERC20Mock {
    string public name;
    string public symbol;
    uint8 public immutable decimals = 18;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );

    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
    }

    function mint(address to, uint256 amount) external {
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        require(allowed >= amount, "allowance");
        if (allowed != type(uint256).max) {
            allowance[from][msg.sender] = allowed - amount;
        }
        _transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal {
        require(balanceOf[from] >= amount, "balance");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
    }
}

contract ClaimVaultTest is Test {
    ClaimVault internal vault;
    IERC20 internal token = IERC20(0xfAB99fCF605fD8f4593EDb70A43bA56542777777);

    address internal owner;
    address internal user1;
    address internal user2;

    uint256 internal signerPk;
    address internal signerAddr;

    uint256 internal defaultEpochDuration = 1 hours;
    uint256 internal defaultGlobalCap = 100_000 ether;
    uint256 internal defaultUserCap = 50_000 ether;

    function setUp() public {
        vm.createSelectFork(
            "https://api.zan.top/node/v1/bsc/mainnet/82c8237102ea47baaa7b49e5510997ee"
        );
        owner = makeAddr("owner");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        signerPk = 0xA11CE;
        signerAddr = vm.addr(signerPk);

        vm.startPrank(owner);
        vault = new ClaimVault(address(token), signerAddr);
        vm.stopPrank();

        deal(address(token), address(vault), 10_000_000 ether);

        assertEq(address(token), address(vault.ZBT()));
        assertEq(vault.signer(), signerAddr);
        assertEq(vault.owner(), owner);
        assertEq(vault.epochDuration(), defaultEpochDuration);
        assertEq(vault.globalCapPerEpoch(), defaultGlobalCap);
        assertEq(vault.userCapPerEpoch(), defaultUserCap);
    }

    function _signClaimDigest(
        address user,
        uint256 amount,
        uint256 nonce,
        uint256 expiry,
        uint256 chainId
    ) internal view returns (bytes memory sig) {
        bytes32 digest = vault.calculateClaimZBTHash(
            user,
            amount,
            nonce,
            chainId,
            expiry
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        sig = abi.encodePacked(r, s, v);
    }

    function _currentEpochId() internal view returns (uint256) {
        return (block.timestamp - vault.startClaimTimestamp()) / vault.epochDuration();
    }

    function test_Claim_Succeeds_BalancesCapsNonceAndEvent() public {
        uint256 amount = 1_000 ether;
        uint256 expiry = block.timestamp + 600;
        uint256 nonce = vault.userNonce(user1);
        uint256 chainId = block.chainid;

        bytes memory sig = _signClaimDigest(
            user1,
            amount,
            nonce,
            expiry,
            chainId
        );

        // Expect event
        vm.expectEmit(true, true, false, true, address(vault));
        emit ClaimVault.Claimed(user1, amount, block.timestamp - defaultEpochDuration, defaultEpochDuration, nonce);

        // Call as user1
        vm.prank(user1);
        vault.Claim(user1, amount, expiry, sig);

        // Check balances
        assertEq(token.balanceOf(user1), amount);
        assertEq(token.balanceOf(address(vault)), 10_000_000 ether - amount);

        // Caps updated
        uint256 epochId = _currentEpochId();
        assertEq(vault.claimedByEpoch(defaultEpochDuration,epochId), amount);
        assertEq(vault.userClaimedByEpoch(defaultEpochDuration,user1, epochId), amount);

        // Nonce incremented
        assertEq(vault.userNonce(user1), nonce + 1);
    }

    function test_Replay_Reverts_InvalidSignature() public {
        uint256 amount = 500 ether;
        uint256 expiry = block.timestamp + 600;
        uint256 nonce = vault.userNonce(user1);
        bytes memory sig = _signClaimDigest(
            user1,
            amount,
            nonce,
            expiry,
            block.chainid
        );

        // First claim ok
        vm.prank(user1);
        vault.Claim(user1, amount, expiry, sig);

        // Replay the exact same signature should fail (nonce consumed)
        vm.expectRevert(bytes("Invalid signature"));
        vm.prank(user1);
        vault.Claim(user1, amount, expiry, sig);
    }

    function test_WrongSigner_Reverts_InvalidSignature() public {
        uint256 amount = 100 ether;
        uint256 expiry = block.timestamp + 600;
        uint256 nonce = vault.userNonce(user1);

        // Sign with a different private key
        uint256 otherPk = 0xB0B;
        bytes32 digest = vault.calculateClaimZBTHash(
            user1,
            amount,
            nonce,
            block.chainid,
            expiry
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(otherPk, digest);
        bytes memory badSig = abi.encodePacked(r, s, v);

        vm.expectRevert(bytes("Invalid signature"));
        vm.prank(user1);
        vault.Claim(user1, amount, expiry, badSig);
    }

    function test_ChainId_Mismatch_Reverts_InvalidSignature() public {
        uint256 amount = 100 ether;
        uint256 expiry = block.timestamp + 600;
        uint256 nonce = vault.userNonce(user1);

        // Sign for current chainId
        uint256 signedChainId = block.chainid;
        bytes memory sig = _signClaimDigest(
            user1,
            amount,
            nonce,
            expiry,
            signedChainId
        );

        // Change chainId (simulate a different domain)
        vm.chainId(signedChainId + 1);

        vm.expectRevert(bytes("Invalid signature"));
        vm.prank(user1);
        vault.Claim(user1, amount, expiry, sig);

        // Restore chainId for subsequent tests
        vm.chainId(signedChainId);
    }

    function test_Revert_InvalidSender() public {
        uint256 amount = 100 ether;
        uint256 expiry = block.timestamp + 600;
        uint256 nonce = vault.userNonce(user1);

        bytes memory sig = _signClaimDigest(
            user1,
            amount,
            nonce,
            expiry,
            block.chainid
        );

        // msg.sender != user parameter: pass user1, call from user2
        vm.expectRevert(bytes("Invalid sender"));
        vm.prank(user2);
        vault.Claim(user1, amount, expiry, sig);
    }

    function test_Revert_ZeroAmount() public {
        uint256 amount = 0;
        uint256 expiry = block.timestamp + 600;
        uint256 nonce = vault.userNonce(user1);

        bytes memory sig = _signClaimDigest(
            user1,
            amount,
            nonce,
            expiry,
            block.chainid
        );

        vm.expectRevert(bytes("Zero ZBT number"));
        vm.prank(user1);
        vault.Claim(user1, amount, expiry, sig);
    }

    function test_Revert_ExpiredSignature() public {
        uint256 amount = 100 ether;
        uint256 expiry = block.timestamp;
        uint256 nonce = vault.userNonce(user1);

        bytes memory sig = _signClaimDigest(
            user1,
            amount,
            nonce,
            expiry,
            block.chainid
        );

        vm.expectRevert(bytes("Signature expired"));
        vm.prank(user1);
        vault.Claim(user1, amount, expiry, sig);
    }

    function test_GlobalCap_Exceeded_Reverts() public {
        vm.startPrank(owner);
        vault.setEpochConfig(vault.epochDuration(), 1_000 ether, 1_000 ether);
        vm.stopPrank();

        uint256 epochId = _currentEpochId();
        assertEq(vault.claimedByEpoch(defaultEpochDuration,epochId), 0);

        // user1 claims 900
        {
            uint256 amount = 900 ether;
            uint256 expiry = block.timestamp + 600;
            uint256 nonce = vault.userNonce(user1);
            bytes memory sig = _signClaimDigest(
                user1,
                amount,
                nonce,
                expiry,
                block.chainid
            );
            vm.prank(user1);
            vault.Claim(user1, amount, expiry, sig);
        }

        // user2 tries to claim 200 (would exceed 1,000)
        {
            uint256 amount = 200 ether;
            uint256 expiry = block.timestamp + 600;
            uint256 nonce = vault.userNonce(user2);
            bytes memory sig = _signClaimDigest(
                user2,
                amount,
                nonce,
                expiry,
                block.chainid
            );

            vm.expectRevert(bytes("Global cap exceeded"));
            vm.prank(user2);
            vault.Claim(user2, amount, expiry, sig);
        }
    }

    function test_UserCap_Exceeded_Reverts() public {
        vm.startPrank(owner);
        vault.setEpochConfig(
            vault.epochDuration(),
            vault.globalCapPerEpoch(),
            1_000 ether
        );
        vm.stopPrank();

        // First claim 800 OK
        {
            uint256 amount = 800 ether;
            uint256 expiry = block.timestamp + 600;
            uint256 nonce = vault.userNonce(user1);
            bytes memory sig = _signClaimDigest(
                user1,
                amount,
                nonce,
                expiry,
                block.chainid
            );
            vm.prank(user1);
            vault.Claim(user1, amount, expiry, sig);
        }

        // Second claim 300 (would exceed 1,000 per-user)
        {
            uint256 amount = 300 ether;
            uint256 expiry = block.timestamp + 600;
            uint256 nonce = vault.userNonce(user1);
            bytes memory sig = _signClaimDigest(
                user1,
                amount,
                nonce,
                expiry,
                block.chainid
            );

            vm.expectRevert(bytes("User cap exceeded"));
            vm.prank(user1);
            vault.Claim(user1, amount, expiry, sig);
        }
    }

    function test_Caps_Reset_NextEpoch() public {
        vm.startPrank(owner);
        vault.setEpochConfig(
            vault.epochDuration(),
            vault.globalCapPerEpoch(),
            1_000 ether
        );
        vm.stopPrank();

        uint256 amount = 1_000 ether;
        uint256 expiry = block.timestamp + 600;
        uint256 nonce = vault.userNonce(user1);
        bytes memory sig = _signClaimDigest(
            user1,
            amount,
            nonce,
            expiry,
            block.chainid
        );

        vm.prank(user1);
        vault.Claim(user1, amount, expiry, sig);

        // Same epoch: next 1 wei should fail
        {
            uint256 amt2 = 1;
            uint256 exp2 = block.timestamp + 600;
            uint256 nonce2 = vault.userNonce(user1);
            bytes memory sig2 = _signClaimDigest(
                user1,
                amt2,
                nonce2,
                exp2,
                block.chainid
            );

            vm.expectRevert(bytes("User cap exceeded"));
            vm.prank(user1);
            vault.Claim(user1, amt2, exp2, sig2);
        }

        vm.warp(block.timestamp + vault.epochDuration());
        uint256 nonce3 = vault.userNonce(user1);
        bytes memory sig3 = _signClaimDigest(
            user1,
            amount,
            nonce3,
            block.timestamp + vault.epochDuration() + 600,
            block.chainid
        );

        vm.startPrank(user1);
        vault.Claim(
            user1,
            amount,
            block.timestamp + vault.epochDuration() + 600,
            sig3
        );
        vm.stopPrank();

        // Check the two epoch buckets
        uint256 epochNow = _currentEpochId();
        assertEq(vault.userClaimedByEpoch(defaultEpochDuration,user1, epochNow), amount);
        assertEq(vault.userClaimedByEpoch(defaultEpochDuration,user1, epochNow - 1), amount);
    }

    function test_InsufficientBalance_Reverts() public {
        vm.prank(owner);
        vault.emergencyWithdraw(address(token), owner);

        // Mint only 100 to vault
        deal(address(token), address(vault), 100 ether);

        uint256 amount = 200 ether;
        uint256 expiry = block.timestamp + 600;
        uint256 nonce = vault.userNonce(user1);
        bytes memory sig = _signClaimDigest(
            user1,
            amount,
            nonce,
            expiry,
            block.chainid
        );

        vm.expectRevert(bytes("Insufficient Balance"));
        vm.prank(user1);
        vault.Claim(user1, amount, expiry, sig);
    }

    function test_Pause_Unpause() public {
        // Pause by owner
        vm.prank(owner);
        vault.pause();

        uint256 amount = 100 ether;
        uint256 expiry = block.timestamp + 600;
        uint256 nonce = vault.userNonce(user1);
        bytes memory sig = _signClaimDigest(
            user1,
            amount,
            nonce,
            expiry,
            block.chainid
        );

        vm.expectRevert();
        vm.prank(user1);
        vault.Claim(user1, amount, expiry, sig);

        // Unpause and try again
        vm.prank(owner);
        vault.unpause();

        vm.prank(user1);
        vault.Claim(user1, amount, expiry, sig);

        assertEq(token.balanceOf(user1), amount);
    }

    function test_SetSigner_OnlyOwner_And_Event() public {
        address newSigner = makeAddr("newSigner");

        vm.expectEmit(true, true, false, true, address(vault));
        emit ClaimVault.UpdateSigner(signerAddr, newSigner);

        vm.prank(owner);
        vault.setSigner(newSigner);

        assertEq(vault.signer(), newSigner);

        uint256 amount = 1 ether;
        uint256 expiry = block.timestamp + 600;
        uint256 nonce = vault.userNonce(user1);
        bytes memory oldSig = _signClaimDigest(
            user1,
            amount,
            nonce,
            expiry,
            block.chainid
        );

        vm.expectRevert(bytes("Invalid signature"));
        vm.prank(user1);
        vault.Claim(user1, amount, expiry, oldSig);
    }

    function test_SetEpochConfig_Validations_And_Event() public {
        // Expect event
        vm.expectEmit(true, true, true, true, address(vault));
        emit ClaimVault.UpdateEpochConfig(
            2 hours,
            2_000_000 ether,
            500_000 ether
        );

        vm.prank(owner);
        vault.setEpochConfig(2 hours, 2_000_000 ether, 500_000 ether);

        assertEq(vault.epochDuration(), 2 hours);
        assertEq(vault.globalCapPerEpoch(), 2_000_000 ether);
        assertEq(vault.userCapPerEpoch(), 500_000 ether);
    }

    function test_SetEpochConfig_Revert_BadParams() public {
        vm.prank(owner);
        vm.expectRevert(bytes("epochDuration can not be zero"));
        vault.setEpochConfig(0, 1 ether, 1 ether);

        vm.prank(owner);
        vm.expectRevert(bytes("globalCapPerEpoch must greater than zero"));
        vault.setEpochConfig(1 hours, 0, 1);

        vm.prank(owner);
        vm.expectRevert(
            bytes(
                "_userCapPerEpoch must greater than zero and less than _globalCapPerEpoch"
            )
        );
        vault.setEpochConfig(1 hours, 100, 0);

        vm.prank(owner);
        vm.expectRevert(
            bytes(
                "_userCapPerEpoch must greater than zero and less than _globalCapPerEpoch"
            )
        );
        vault.setEpochConfig(1 hours, 100, 200);
    }

    function test_EmergencyWithdraw_OnlyOwner_MovesFunds_And_Event() public {
        // Mint another token and send to vault
        ERC20Mock other = new ERC20Mock("OTHER", "OTH");
        other.mint(address(vault), 777 ether);
        assertEq(other.balanceOf(address(vault)), 777 ether);

        // Expect event
        vm.expectEmit(true, true, false, true, address(vault));
        emit ClaimVault.EmergencyWithdrawal(address(other), owner);

        // Withdraw by owner
        vm.prank(owner);
        vault.emergencyWithdraw(address(other), owner);

        assertEq(other.balanceOf(address(vault)), 0);
        assertEq(other.balanceOf(owner), 777 ether);
    }
}
