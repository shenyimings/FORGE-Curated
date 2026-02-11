// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ZkTokenV1, Initializable} from "src/ZkTokenV1.sol";
import {ZkTokenTest} from "test/utils/ZkTokenTest.sol";
import {ZkTokenFakeV2ClockChange} from "test/harnesses/ZkTokenFakeV2ClockChange.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";

contract Initialize is ZkTokenTest {
  function calculateDomainSeparator(ZkTokenV1 _token) public view returns (bytes32) {
    return keccak256(
      abi.encode(
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
        keccak256(bytes("zkSync")),
        keccak256(bytes("1")),
        block.chainid,
        address(_token)
      )
    );
  }

  function test_InitializesTheTokenWithTheCorrectConfigurationWhenDeployedViaUpgrades() public {
    assertEq(token.symbol(), "ZK");
    assertEq(token.name(), "zkSync");

    // verify that the domain separator is setup correctly
    assertEq(token.DOMAIN_SEPARATOR(), calculateDomainSeparator(token));

    // The mint receiver has received the full minted distribution
    assertEq(token.balanceOf(initMintReceiver), INITIAL_MINT_AMOUNT);
    assertEq(token.totalSupply(), INITIAL_MINT_AMOUNT);

    // The admin has all three administrative roles after initialization
    assertTrue(token.hasRole(DEFAULT_ADMIN_ROLE, admin));
    assertTrue(token.hasRole(MINTER_ADMIN_ROLE, admin));
    assertTrue(token.hasRole(BURNER_ADMIN_ROLE, admin));

    // The administrative roles have the proper association with each role
    assertEq(token.getRoleAdmin(MINTER_ROLE), MINTER_ADMIN_ROLE);
    assertEq(token.getRoleAdmin(BURNER_ROLE), BURNER_ADMIN_ROLE);

    // The administrative role of the administrative roles are the default admin
    assertEq(token.getRoleAdmin(MINTER_ADMIN_ROLE), DEFAULT_ADMIN_ROLE);
    assertEq(token.getRoleAdmin(BURNER_ADMIN_ROLE), DEFAULT_ADMIN_ROLE);

    // The default administrative role self administers
    assertEq(token.getRoleAdmin(DEFAULT_ADMIN_ROLE), DEFAULT_ADMIN_ROLE);
  }

  function testFuzz_InitializesTheTokenWithTheCorrectConfigurationWhenCalledDirectly(
    address _admin,
    address _initMintReceiver,
    uint256 _mintAmount
  ) public {
    vm.assume(_admin != address(0) && _initMintReceiver != address(0) && _admin != _initMintReceiver);
    _mintAmount = bound(_mintAmount, 0, MAX_MINT_SUPPLY);

    ZkTokenV1 _token = new ZkTokenV1();
    _token.initialize(_admin, _initMintReceiver, _mintAmount);

    // Same assertions as upgradeable deploy test
    assertEq(_token.balanceOf(_initMintReceiver), _mintAmount);
    assertEq(_token.totalSupply(), _mintAmount);
    assertEq(_token.symbol(), "ZK");
    assertEq(_token.name(), "zkSync");
    assertTrue(_token.hasRole(DEFAULT_ADMIN_ROLE, _admin));
    assertTrue(_token.hasRole(MINTER_ADMIN_ROLE, _admin));
    assertTrue(_token.hasRole(BURNER_ADMIN_ROLE, _admin));
    assertEq(_token.getRoleAdmin(MINTER_ROLE), MINTER_ADMIN_ROLE);
    assertEq(_token.getRoleAdmin(BURNER_ROLE), BURNER_ADMIN_ROLE);
    assertEq(_token.getRoleAdmin(MINTER_ADMIN_ROLE), DEFAULT_ADMIN_ROLE);
    assertEq(_token.getRoleAdmin(BURNER_ADMIN_ROLE), DEFAULT_ADMIN_ROLE);
    assertEq(_token.getRoleAdmin(DEFAULT_ADMIN_ROLE), DEFAULT_ADMIN_ROLE);
  }

  function testFuzz_InitializesTheTokenSuchThatTheAdminRolesCanGrantTheRoleToOthers(address _newAdmin) public {
    vm.assume(_newAdmin != admin);

    // The default admin can add another default admin
    vm.prank(admin);
    token.grantRole(DEFAULT_ADMIN_ROLE, _newAdmin);
    assertTrue(token.hasRole(DEFAULT_ADMIN_ROLE, _newAdmin));

    // The new default admin can add other minter/burner admins
    vm.prank(_newAdmin);
    token.grantRole(MINTER_ADMIN_ROLE, _newAdmin);
    assertTrue(token.hasRole(MINTER_ADMIN_ROLE, _newAdmin));
    vm.prank(_newAdmin);
    token.grantRole(BURNER_ADMIN_ROLE, _newAdmin);
    assertTrue(token.hasRole(BURNER_ADMIN_ROLE, _newAdmin));

    // The new default admin can revoke the default role from the original admin
    vm.prank(_newAdmin);
    token.revokeRole(DEFAULT_ADMIN_ROLE, admin);
    assertFalse(token.hasRole(DEFAULT_ADMIN_ROLE, admin));
  }

  function testFuzz_RevertIf_TheInitializerIsCalledTwice(address _admin, address _receiver, uint256 _amount) public {
    vm.expectRevert("Initializable: contract is already initialized");
    token.initialize(_admin, _receiver, _amount);
  }
}

contract Clock is ZkTokenTest {
  function testFuzz_ClockMatchesBlockTimestamp(uint48 _timestamp) public {
    vm.warp(_timestamp);
    assertEq(token.clock(), block.timestamp);
  }
}

contract CLOCK_MODE is ZkTokenTest {
  function test_ClockModeMachineReadableStringIsTimestamp() public {
    assertEq(token.CLOCK_MODE(), "mode=timestamp");
  }

  function testFuzz_RevertIf_TokenUpgradedWithNewClock(uint256 _initialValue, uint24 _warpAhead) public {
    vm.assume(_warpAhead != 0);
    ZkTokenFakeV2ClockChange token = new ZkTokenFakeV2ClockChange();
    token.initializeFakeV2(_initialValue);
    vm.expectRevert(ZkTokenV1.ERC6372InconsistentClock.selector);
    vm.warp(block.timestamp + _warpAhead);
    token.CLOCK_MODE();
  }
}

contract Mint is ZkTokenTest {
  function testFuzz_AllowsAnAccountWithTheMinterRoleToMintTokensWithoutProxy(
    address _minter,
    address _receiver,
    uint256 _amount
  ) public {
    vm.assume(_receiver != address(0) && _receiver != initMintReceiver);
    _amount = bound(_amount, 0, MAX_MINT_SUPPLY);

    ZkTokenV1 token = new ZkTokenV1();
    token.initialize(admin, initMintReceiver, INITIAL_MINT_AMOUNT);

    vm.prank(admin);
    token.grantRole(MINTER_ROLE, _minter);

    vm.prank(_minter);
    token.mint(_receiver, _amount);

    assertEq(token.balanceOf(_receiver), _amount);
  }

  function testFuzz_AllowsAnAccountWithTheMinterRoleToMintTokens(address _minter, address _receiver, uint256 _amount)
    public
  {
    vm.assume(_receiver != address(0) && _receiver != initMintReceiver);
    _amount = bound(_amount, 0, MAX_MINT_SUPPLY);

    vm.prank(admin);
    token.grantRole(MINTER_ROLE, _minter);

    vm.prank(_minter);
    token.mint(_receiver, _amount);

    assertEq(token.balanceOf(_receiver), _amount);
  }

  function testFuzz_AllowsMultipleAccountsWithTheMinterRoleToMintTokens(
    address _minter1,
    address _receiver1,
    uint256 _amount1,
    address _minter2,
    address _receiver2,
    uint256 _amount2
  ) public {
    vm.assume(
      _receiver1 != address(0) && _receiver1 != initMintReceiver && _receiver2 != address(0)
        && _receiver2 != initMintReceiver && _receiver1 != _receiver2
    );
    _amount1 = bound(_amount1, 0, MAX_MINT_SUPPLY / 2);
    _amount2 = bound(_amount2, 0, MAX_MINT_SUPPLY / 2);

    // grant minter role to multiple accounts
    vm.startPrank(admin);
    token.grantRole(MINTER_ROLE, _minter1);
    token.grantRole(MINTER_ROLE, _minter2);
    vm.stopPrank();

    // first minter mints some tokens
    vm.prank(_minter1);
    token.mint(_receiver1, _amount1);

    // second minter mints some tokens
    vm.prank(_minter2);
    token.mint(_receiver2, _amount2);

    assertEq(token.balanceOf(_receiver1), _amount1);
    assertEq(token.balanceOf(_receiver2), _amount2);
  }

  function testFuzz_RevertIf_AnAccountWithoutTheMinterRoleAttemptsToMint(
    address _notMinter,
    address _receiver,
    uint256 _amount
  ) public {
    vm.assume(_receiver != address(0));
    _amount = bound(_amount, 0, MAX_MINT_SUPPLY);

    vm.expectRevert(); // The expected error message requires string concatenation so we avoid it
    vm.prank(_notMinter);
    token.mint(_receiver, _amount);
  }

  function testFuzz_RevertIf_AnAccountThatHasHadTheMinterRoleRevokedAttemptsToMint(
    address _formerMinter,
    address _receiver,
    uint256 _amount
  ) public {
    vm.assume(_receiver != address(0));
    _amount = bound(_amount, 0, MAX_MINT_SUPPLY);

    // grant the account the minter role and exercise minting rights
    vm.prank(admin);
    token.grantRole(MINTER_ROLE, _formerMinter);
    vm.prank(_formerMinter);
    token.mint(_receiver, _amount);

    // revoke the minter role from the account
    vm.prank(admin);
    token.revokeRole(MINTER_ROLE, _formerMinter);

    // attempting to mint should now cause the contract to revert
    vm.expectRevert();
    vm.prank(_formerMinter);
    token.mint(_receiver, _amount);
  }
}

contract ZkTokenV1BurnTest is ZkTokenTest {
  address minter = makeAddr("Minter");

  function setUp() public virtual override {
    super.setUp();

    // grant appropriate role to the minting address
    vm.prank(admin);
    token.grantRole(MINTER_ROLE, minter);
  }

  function _assumeSafeReceiverBoundAndMint(address _to, uint256 _amount) public returns (uint256 _boundedAmount) {
    _boundedAmount = _assumeSafeReceiverBoundAndMint(_to, _amount, MAX_MINT_SUPPLY);
  }

  function _assumeSafeReceiverBoundAndMint(address _to, uint256 _amount, uint256 _maxAmount)
    public
    returns (uint256 _boundedAmount)
  {
    vm.assume(_to != address(0) && _to != initMintReceiver);
    _boundedAmount = bound(_amount, 0, _maxAmount);

    vm.prank(minter);
    token.mint(_to, _boundedAmount);
  }
}

contract Burn is ZkTokenV1BurnTest {
  function testFuzz_AllowsAnAccountWithTheBurnerRoleToBurnTokensWithoutProxy(
    address _burner,
    address _receiver,
    uint256 _mintAmount,
    uint256 _burnAmount
  ) public {
    vm.assume(_receiver != initMintReceiver);
    _mintAmount = _assumeSafeReceiverBoundAndMint(_receiver, _mintAmount);
    _burnAmount = bound(_burnAmount, 0, _mintAmount);

    ZkTokenV1 token = new ZkTokenV1();
    token.initialize(admin, initMintReceiver, INITIAL_MINT_AMOUNT);

    vm.prank(admin);
    token.grantRole(MINTER_ROLE, _burner);

    vm.prank(_burner);
    token.mint(_receiver, _mintAmount);

    vm.prank(admin);
    token.grantRole(BURNER_ROLE, _burner);

    vm.prank(_burner);
    token.burn(_receiver, _burnAmount);

    assertEq(token.balanceOf(_receiver), _mintAmount - _burnAmount);
  }

  function testFuzz_AllowsAnAccountWithTheBurnerRoleToBurnTokens(
    address _burner,
    address _receiver,
    uint256 _mintAmount,
    uint256 _burnAmount
  ) public {
    _mintAmount = _assumeSafeReceiverBoundAndMint(_receiver, _mintAmount);
    _burnAmount = bound(_burnAmount, 0, _mintAmount);

    vm.prank(admin);
    token.grantRole(BURNER_ROLE, _burner);

    vm.prank(_burner);
    token.burn(_receiver, _burnAmount);

    assertEq(token.balanceOf(_receiver), _mintAmount - _burnAmount);
  }

  function testFuzz_AllowsMultipleAccountsWithTheBurnerRoleToBurnTokens(
    address _burner1,
    address _receiver1,
    uint256 _mintAmount1,
    uint256 _burnAmount1,
    address _burner2,
    address _receiver2,
    uint256 _mintAmount2,
    uint256 _burnAmount2
  ) public {
    vm.assume(_receiver1 != _receiver2);
    _mintAmount1 = _assumeSafeReceiverBoundAndMint(_receiver1, _mintAmount1, MAX_MINT_SUPPLY / 2);
    _burnAmount1 = bound(_burnAmount1, 0, _mintAmount1);
    _mintAmount2 = _assumeSafeReceiverBoundAndMint(_receiver2, _mintAmount2, MAX_MINT_SUPPLY / 2);
    _burnAmount2 = bound(_burnAmount2, 0, _mintAmount2);

    // grant burner role to multiple accounts
    vm.startPrank(admin);
    token.grantRole(BURNER_ROLE, _burner1);
    token.grantRole(BURNER_ROLE, _burner2);
    vm.stopPrank();

    // first burner burns some tokens
    vm.prank(_burner1);
    token.burn(_receiver1, _burnAmount1);

    // second burner burns some tokens
    vm.prank(_burner2);
    token.burn(_receiver2, _burnAmount2);

    assertEq(token.balanceOf(_receiver1), _mintAmount1 - _burnAmount1);
    assertEq(token.balanceOf(_receiver2), _mintAmount2 - _burnAmount2);
  }

  function testFuzz_RevertIf_AnAccountWithoutTheBurnerRoleAttemptsToBurnTokens(
    address _notBurner,
    address _receiver,
    uint256 _mintAmount,
    uint256 _burnAmount
  ) public {
    _mintAmount = _assumeSafeReceiverBoundAndMint(_receiver, _mintAmount);
    _burnAmount = bound(_burnAmount, 0, _mintAmount);

    vm.expectRevert();
    vm.prank(_notBurner);
    token.burn(_receiver, _burnAmount);
  }

  function testFuzz_RevertIf_AnAccountThatHasHadTheBurnerRoleRevokedAttemptsToBurn(
    address _formerBurner,
    address _receiver,
    uint256 _mintAmount,
    uint256 _burnAmount
  ) public {
    _mintAmount = _assumeSafeReceiverBoundAndMint(_receiver, _mintAmount);
    _burnAmount = bound(_burnAmount, 0, _mintAmount / 2); // divide by 2 so two burns _should_ be possible

    // grant the burner role
    vm.prank(admin);
    token.grantRole(BURNER_ROLE, _formerBurner);

    // burn some tokens
    vm.prank(_formerBurner);
    token.burn(_receiver, _burnAmount);

    // revoke the burner role
    vm.prank(admin);
    token.revokeRole(BURNER_ROLE, _formerBurner);

    // Attempting to burn now should revert with access error
    vm.expectRevert();
    vm.prank(_formerBurner);
    token.burn(_receiver, _burnAmount);
  }
}

contract Permit is ZkTokenTest {
  bytes32 constant PERMIT_TYPEHASH =
    keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

  function testFuzz_PerformsTheApprovalByCallingPermitThenPerformsTransfer(
    uint256 _ownerPrivateKey,
    uint256 _amount,
    address _spender,
    address _receiver,
    uint256 _deadline
  ) public {
    vm.assume(_spender != address(0) && _receiver != address(0) && _receiver != initMintReceiver);
    _deadline = bound(_deadline, block.timestamp + 1, type(uint256).max);
    _ownerPrivateKey = bound(_ownerPrivateKey, 1, 100e18);
    address _owner = vm.addr(_ownerPrivateKey);
    _amount = bound(_amount, 0, MAX_MINT_SUPPLY);

    vm.prank(admin);
    token.grantRole(MINTER_ROLE, _owner);
    vm.prank(_owner);
    token.mint(_owner, _amount);

    // verify the owner has the expected balance
    assertEq(token.balanceOf(_owner), _amount);

    bytes32 _message =
      keccak256(abi.encode(PERMIT_TYPEHASH, _owner, _spender, _amount, token.nonces(_owner), _deadline));

    bytes32 _messageHash = keccak256(abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), _message));
    (uint8 _v, bytes32 _r, bytes32 _s) = vm.sign(_ownerPrivateKey, _messageHash);

    vm.prank(_spender);
    token.permit(_owner, _spender, _amount, _deadline, _v, _r, _s);

    vm.prank(_spender);
    token.transferFrom(_owner, _receiver, _amount);

    // verify the receiver has the expected balance
    assertEq(token.balanceOf(_receiver), _amount);

    // verify the owner has the zero balance
    assertEq(token.balanceOf(_owner), 0);
  }

  function testFuzz_RevertIf_ThePermitSignatureIsInvalid(
    address _notOwner,
    uint256 _ownerPrivateKey,
    uint256 _amount,
    address _spender,
    address _receiver,
    uint256 _deadline
  ) public {
    vm.assume(_spender != address(0) && _receiver != address(0) && _notOwner != address(0));

    _deadline = bound(_deadline, block.timestamp + 1, type(uint256).max);
    _ownerPrivateKey = bound(_ownerPrivateKey, 1, 100e18);
    address _owner = vm.addr(_ownerPrivateKey);
    vm.assume(_notOwner != _owner);
    _amount = bound(_amount, 0, MAX_MINT_SUPPLY);

    vm.prank(admin);
    token.grantRole(MINTER_ROLE, _owner);
    vm.prank(_owner);
    token.mint(_owner, _amount);

    // verify the owner has the expected balance
    assertEq(token.balanceOf(_owner), _amount);

    bytes32 _message =
      keccak256(abi.encode(PERMIT_TYPEHASH, _notOwner, _spender, _amount, token.nonces(_notOwner), _deadline));

    bytes32 _messageHash = keccak256(abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), _message));
    (uint8 _v, bytes32 _r, bytes32 _s) = vm.sign(_ownerPrivateKey, _messageHash);

    // verify the permit signature is invalid
    vm.prank(_spender);
    vm.expectRevert("ERC20Permit: invalid signature");
    token.permit(_notOwner, _spender, _amount, _deadline, _v, _r, _s);
  }

  function testFuzz_PerformsTheApprovalByCallingPermitThenPerformsTransferWithoutProxy(
    uint256 _ownerPrivateKey,
    uint256 _amount,
    address _spender,
    address _receiver,
    uint256 _deadline
  ) public {
    vm.assume(_spender != address(0) && _receiver != address(0) && _receiver != initMintReceiver);
    _deadline = bound(_deadline, block.timestamp + 1, type(uint256).max);
    _ownerPrivateKey = bound(_ownerPrivateKey, 1, 100e18);
    address _owner = vm.addr(_ownerPrivateKey);

    _amount = bound(_amount, 0, MAX_MINT_SUPPLY);

    ZkTokenV1 token = new ZkTokenV1();
    token.initialize(admin, initMintReceiver, INITIAL_MINT_AMOUNT);

    vm.prank(admin);
    token.grantRole(MINTER_ROLE, _owner);
    vm.prank(_owner);
    token.mint(_owner, _amount);

    // verify the owner has the expected balance
    assertEq(token.balanceOf(_owner), _amount);

    bytes32 _message =
      keccak256(abi.encode(PERMIT_TYPEHASH, _owner, _spender, _amount, token.nonces(_owner), _deadline));

    bytes32 _messageHash = keccak256(abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), _message));
    (uint8 _v, bytes32 _r, bytes32 _s) = vm.sign(_ownerPrivateKey, _messageHash);

    vm.prank(_spender);
    token.permit(_owner, _spender, _amount, _deadline, _v, _r, _s);

    vm.prank(_spender);
    token.transferFrom(_owner, _receiver, _amount);

    // verify the receiver has the expected balance
    assertEq(token.balanceOf(_receiver), _amount);

    // verify the owner has the zero balance
    assertEq(token.balanceOf(_owner), 0);
  }

  function testFuzz_RevertIf_ThePermitSignatureIsInvalidWithoutProxy(
    address _notOwner,
    uint256 _ownerPrivateKey,
    uint256 _amount,
    address _spender,
    address _receiver,
    uint256 _deadline
  ) public {
    vm.assume(_spender != address(0) && _receiver != address(0) && _notOwner != address(0));

    _deadline = bound(_deadline, block.timestamp + 1, type(uint256).max);
    _ownerPrivateKey = bound(_ownerPrivateKey, 1, 100e18);
    address _owner = vm.addr(_ownerPrivateKey);

    vm.assume(_notOwner != _owner);
    _amount = bound(_amount, 0, MAX_MINT_SUPPLY);

    ZkTokenV1 token = new ZkTokenV1();
    token.initialize(admin, initMintReceiver, INITIAL_MINT_AMOUNT);

    vm.prank(admin);
    token.grantRole(MINTER_ROLE, _owner);
    vm.prank(_owner);
    token.mint(_owner, _amount);

    // verify the owner has the expected balance
    assertEq(token.balanceOf(_owner), _amount);

    bytes32 _messageHash = keccak256(
      abi.encodePacked(
        "\x19\x01",
        token.DOMAIN_SEPARATOR(),
        keccak256(abi.encode(PERMIT_TYPEHASH, _notOwner, _spender, _amount, token.nonces(_notOwner), _deadline))
      )
    );
    (uint8 _v, bytes32 _r, bytes32 _s) = vm.sign(_ownerPrivateKey, _messageHash);

    // verify the permit signature is invalid
    vm.prank(_spender);
    vm.expectRevert("ERC20Permit: invalid signature");
    token.permit(_notOwner, _spender, _amount, _deadline, _v, _r, _s);
  }
}

/// @dev Used to test the ERC20VotesUpgradeable nonces method for coverage purposes as it is inherited from
/// ERC20VotesUpgradeable
contract Nonces is ZkTokenTest {
  function testFuzz_NoncesWithoutProxy(address _owner) public {
    vm.assume(_owner != address(0));
    ZkTokenV1 token = new ZkTokenV1();
    token.initialize(admin, initMintReceiver, INITIAL_MINT_AMOUNT);
    uint256 _nonce = token.nonces(_owner);
    assertEq(token.nonces(_owner), _nonce);
  }
}

contract DelegateOnBehalf is ZkTokenTest {
  /// @notice Type hash used when encoding data for `delegateOnBehalf` calls.
  bytes32 public constant DELEGATION_TYPEHASH =
    keccak256("Delegation(address owner,address delegatee,uint256 nonce,uint256 expiry)");

  function testFuzz_RevertIf_ExpiredSignatureDelegateOnBehalf(
    uint256 _signerPrivateKey,
    uint256 _amount,
    address _delegatee,
    uint256 _expiry
  ) public {
    vm.assume(_delegatee != address(0));
    _expiry = bound(_expiry, 0, block.timestamp - 1);
    _signerPrivateKey = bound(_signerPrivateKey, 1, 100e18);
    address _signer = vm.addr(_signerPrivateKey);
    _amount = bound(_amount, 0, MAX_MINT_SUPPLY);

    vm.prank(admin);
    token.grantRole(MINTER_ROLE, _signer);
    vm.prank(_signer);
    token.mint(_signer, _amount);

    // verify the owner has the expected balance
    assertEq(token.balanceOf(_signer), _amount);

    // verify the signer has no delegate
    assertEq(token.delegates(_signer), address(0));

    vm.expectRevert(abi.encodeWithSelector(ZkTokenV1.DelegateSignatureExpired.selector, _expiry));
    token.delegateOnBehalf(_signer, _delegatee, _expiry, "");
  }

  function testFuzz_PerformsDelegationByCallingDelegateOnBehalfECDSA(
    uint256 _signerPrivateKey,
    uint256 _amount,
    address _delegatee,
    uint256 _expiry
  ) public {
    vm.assume(_delegatee != address(0));
    _expiry = bound(_expiry, block.timestamp, type(uint256).max);
    _signerPrivateKey = bound(_signerPrivateKey, 1, 100e18);
    address _signer = vm.addr(_signerPrivateKey);
    _amount = bound(_amount, 0, MAX_MINT_SUPPLY);

    vm.prank(admin);
    token.grantRole(MINTER_ROLE, _signer);
    vm.prank(_signer);
    token.mint(_signer, _amount);

    // verify the owner has the expected balance
    assertEq(token.balanceOf(_signer), _amount);

    bytes32 _message = keccak256(abi.encode(DELEGATION_TYPEHASH, _signer, _delegatee, token.nonces(_signer), _expiry));

    bytes32 _messageHash = keccak256(abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), _message));
    (uint8 _v, bytes32 _r, bytes32 _s) = vm.sign(_signerPrivateKey, _messageHash);

    // verify the signer has no delegate
    assertEq(token.delegates(_signer), address(0));

    token.delegateOnBehalf(_signer, _delegatee, _expiry, abi.encodePacked(_r, _s, _v));

    // verify the signer has delegate
    assertEq(token.delegates(_signer), _delegatee);
  }

  function testFuzz_PerformsDelegationByCallingDelegateOnBehalfEIP1271(
    uint256 _signerPrivateKey,
    uint256 _amount,
    address _delegatee,
    uint256 _expiry
  ) public {
    vm.assume(_delegatee != address(0));
    _expiry = bound(_expiry, block.timestamp, type(uint256).max);
    _signerPrivateKey = bound(_signerPrivateKey, 1, 100e18);
    address _signer = vm.addr(_signerPrivateKey);
    _amount = bound(_amount, 0, MAX_MINT_SUPPLY);

    vm.prank(admin);
    token.grantRole(MINTER_ROLE, _signer);
    vm.prank(_signer);
    token.mint(_signer, _amount);

    // verify the owner has the expected balance
    assertEq(token.balanceOf(_signer), _amount);

    bytes32 _message = keccak256(abi.encode(DELEGATION_TYPEHASH, _signer, _delegatee, token.nonces(_signer), _expiry));

    bytes32 _messageHash = keccak256(abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), _message));

    // verify the signer has no delegate
    assertEq(token.delegates(_signer), address(0));

    vm.mockCall(
      _signer,
      abi.encodeWithSelector(IERC1271.isValidSignature.selector, _messageHash),
      abi.encode(IERC1271.isValidSignature.selector)
    );

    token.delegateOnBehalf(_signer, _delegatee, _expiry, "");

    // verify the signer has delegate
    assertEq(token.delegates(_signer), _delegatee);
  }

  function testFuzz_RevertIf_InvalidECDSASignature(
    address _notSigner,
    uint256 _signerPrivateKey,
    uint256 _amount,
    address _delegatee,
    uint256 _expiry
  ) public {
    vm.assume(_delegatee != address(0));
    _expiry = bound(_expiry, block.timestamp, type(uint256).max);
    _signerPrivateKey = bound(_signerPrivateKey, 1, 100e18);
    address _signer = vm.addr(_signerPrivateKey);
    _amount = bound(_amount, 0, MAX_MINT_SUPPLY);

    vm.prank(admin);
    token.grantRole(MINTER_ROLE, _signer);
    vm.prank(_signer);
    token.mint(_signer, _amount);

    // verify the owner has the expected balance
    assertEq(token.balanceOf(_signer), _amount);

    bytes32 _message =
      keccak256(abi.encode(DELEGATION_TYPEHASH, _notSigner, _delegatee, token.nonces(_notSigner), _expiry));

    bytes32 _messageHash = keccak256(abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), _message));
    (uint8 _v, bytes32 _r, bytes32 _s) = vm.sign(_signerPrivateKey, _messageHash);
    // check both ECDSA and EIP-1271 signature verification in one test
    vm.mockCall(
      _signer,
      abi.encodeWithSelector(IERC1271.isValidSignature.selector, _messageHash),
      abi.encode(IERC1271.isValidSignature.selector)
    );

    // verify the signer has no delegate
    assertEq(token.delegates(_signer), address(0));

    vm.expectRevert(ZkTokenV1.DelegateSignatureIsInvalid.selector);
    token.delegateOnBehalf(_signer, _delegatee, _expiry, abi.encodePacked(_r, _s, _v));
  }
}
