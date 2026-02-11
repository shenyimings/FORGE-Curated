// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ZkTokenV1, Initializable} from "src/ZkTokenV1.sol";
import {ZkTokenTest} from "test/utils/ZkTokenTest.sol";
import {Upgrades, Options} from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {ZkTokenFakeV2} from "test/harnesses/ZkTokenFakeV2.sol";
import {ERC20PermitUpgradeable} from
  "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";

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
    _assumeNotProxyAdmin(_newAdmin);
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
    vm.expectRevert(Initializable.InvalidInitialization.selector);
    token.initialize(_admin, _receiver, _amount);
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
    _assumeNotProxyAdmin(_minter);
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
    _assumeNotProxyAdmin(_minter1);
    _assumeNotProxyAdmin(_minter2);
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
    _assumeNotProxyAdmin(_notMinter);
    vm.assume(_receiver != address(0));
    _amount = bound(_amount, 0, MAX_MINT_SUPPLY);

    vm.expectRevert(
      abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, _notMinter, MINTER_ROLE)
    );
    vm.prank(_notMinter);
    token.mint(_receiver, _amount);
  }

  function testFuzz_RevertIf_AnAccountThatHasHadTheMinterRoleRevokedAttemptsToMint(
    address _formerMinter,
    address _receiver,
    uint256 _amount
  ) public {
    _assumeNotProxyAdmin(_formerMinter);
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
    vm.expectRevert(
      abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, _formerMinter, MINTER_ROLE)
    );
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
    _assumeNotProxyAdmin(_burner);
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
    _assumeNotProxyAdmin(_burner1);
    _assumeNotProxyAdmin(_burner2);
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
    _assumeNotProxyAdmin(_notBurner);
    _mintAmount = _assumeSafeReceiverBoundAndMint(_receiver, _mintAmount);
    _burnAmount = bound(_burnAmount, 0, _mintAmount);

    vm.expectRevert(
      abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, _notBurner, BURNER_ROLE)
    );
    vm.prank(_notBurner);
    token.burn(_receiver, _burnAmount);
  }

  function testFuzz_RevertIf_AnAccountThatHasHadTheBurnerRoleRevokedAttemptsToBurn(
    address _formerBurner,
    address _receiver,
    uint256 _mintAmount,
    uint256 _burnAmount
  ) public {
    _assumeNotProxyAdmin(_formerBurner);
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
    vm.expectRevert(
      abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, _formerBurner, BURNER_ROLE)
    );
    vm.prank(_formerBurner);
    token.burn(_receiver, _burnAmount);
  }
}

contract Upgrade is ZkTokenTest {
  function _upgradeProxyOpts() public view returns (Options memory) {
    return Options({
      unsafeSkipAllChecks: vm.envOr("SKIP_SAFETY_CHECK_IN_UPGRADE_TEST", false),
      referenceContract: "",
      constructorData: "",
      unsafeAllow: "",
      unsafeAllowRenames: false,
      unsafeSkipStorageCheck: false
    });
  }

  // We limit the fuzz runs of this test because it performs FFI actions to run the node script, which takes
  // significant time and resources
  /// forge-config: default.fuzz.runs = 3
  /// forge-config: ci.fuzz.runs = 5
  /// forge-config: lite.fuzz.runs = 1
  function testFuzz_PerformsAndInitializesAnUpgradeThatAddsNewFunctionalityToTheToken(
    uint256 _initialValue,
    address _minter,
    uint256 _mintAmount,
    address _burner,
    uint256 _burnAmount,
    uint256 _nextValue
  ) public {
    _assumeNotProxyAdmin(_minter);
    _assumeNotProxyAdmin(_burner);
    vm.assume(_minter != address(0) && _burner != address(0));
    _mintAmount = bound(_mintAmount, 0, MAX_MINT_SUPPLY);
    _burnAmount = bound(_burnAmount, 0, _mintAmount);

    // Assign the burner role before performing the upgrade
    vm.prank(admin);
    token.grantRole(BURNER_ROLE, _burner);
    assertTrue(token.hasRole(BURNER_ROLE, _burner));

    // Perform the upgrade
    vm.startPrank(proxyOwner);
    Upgrades.upgradeProxy(
      address(token),
      "ZkTokenFakeV2.sol",
      abi.encodeCall(ZkTokenFakeV2.initializeFakeV2, (_initialValue)),
      _upgradeProxyOpts()
    );
    vm.stopPrank();

    // Ensure the contract is initialized correctly
    ZkTokenFakeV2 _tokenV2 = ZkTokenFakeV2(address(token));
    assertEq(_tokenV2.fakeStateVar(), _initialValue);

    // Grant the minter role
    vm.prank(admin);
    _tokenV2.grantRole(MINTER_ROLE, _minter);
    assertTrue(_tokenV2.hasRole(MINTER_ROLE, _minter));

    // Ensure we can exercise pre-upgrade functionality, such as minting
    vm.prank(_minter);
    _tokenV2.mint(_minter, _mintAmount);
    assertEq(_tokenV2.balanceOf(_minter), _mintAmount);

    // Ensure a role applied pre-upgrade, in this case the burner, still functions as expected
    vm.prank(_burner);
    _tokenV2.burn(_minter, _burnAmount);
    assertEq(_tokenV2.balanceOf(_minter), _mintAmount - _burnAmount);

    // Ensure we can exercise some new functionality included in the upgrade
    vm.prank(_minter);
    vm.expectEmit();
    emit ZkTokenFakeV2.FakeStateVarSet(_initialValue, _nextValue);
    _tokenV2.setFakeStateVar(_nextValue);
    assertEq(_tokenV2.fakeStateVar(), _nextValue);

    // Ensure the role ACL applied to the new method works
    address _notMinter = address(uint160(uint256(keccak256(abi.encode(_minter)))));
    vm.expectRevert(
      abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, _notMinter, MINTER_ROLE)
    );
    vm.prank(_notMinter);
    token.mint(_notMinter, _mintAmount);

    // Ensure initialization cannot be called again
    vm.expectRevert(Initializable.InvalidInitialization.selector);
    _tokenV2.initialize(_minter, initMintReceiver, INITIAL_MINT_AMOUNT);
    vm.expectRevert(Initializable.InvalidInitialization.selector);
    _tokenV2.initializeFakeV2(_nextValue);
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
    _assumeNotProxyAdmin(_spender);
    _deadline = bound(_deadline, block.timestamp + 1, type(uint256).max);
    _ownerPrivateKey = bound(_ownerPrivateKey, 1, 100e18);
    address _owner = vm.addr(_ownerPrivateKey);
    _assumeNotProxyAdmin(_owner);
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
    _assumeNotProxyAdmin(_spender);

    _deadline = bound(_deadline, block.timestamp + 1, type(uint256).max);
    _ownerPrivateKey = bound(_ownerPrivateKey, 1, 100e18);
    address _owner = vm.addr(_ownerPrivateKey);
    _assumeNotProxyAdmin(_owner);
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
    vm.expectRevert(abi.encodeWithSelector(ERC20PermitUpgradeable.ERC2612InvalidSigner.selector, _owner, _notOwner));
    token.permit(_notOwner, _spender, _amount, _deadline, _v, _r, _s);
  }

  function testFuzz_PerformsTheApprovalByCallingPermitThenPerformsTransferWithoutProxy(
    uint256 _ownerPrivateKey,
    uint256 _amount,
    address _spender,
    address _receiver,
    uint256 _deadline
  ) public {
    _assumeNotProxyAdmin(_spender);
    vm.assume(_spender != address(0) && _receiver != address(0) && _receiver != initMintReceiver);
    _deadline = bound(_deadline, block.timestamp + 1, type(uint256).max);
    _ownerPrivateKey = bound(_ownerPrivateKey, 1, 100e18);
    address _owner = vm.addr(_ownerPrivateKey);
    _assumeNotProxyAdmin(_owner);
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
    _assumeNotProxyAdmin(_spender);
    _deadline = bound(_deadline, block.timestamp + 1, type(uint256).max);
    _ownerPrivateKey = bound(_ownerPrivateKey, 1, 100e18);
    address _owner = vm.addr(_ownerPrivateKey);
    _assumeNotProxyAdmin(_owner);
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
    vm.expectRevert(abi.encodeWithSelector(ERC20PermitUpgradeable.ERC2612InvalidSigner.selector, _owner, _notOwner));
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
