// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ZkTokenTest} from "test/utils/ZkTokenTest.sol";
import {IMintableAndDelegatable} from "src/interfaces/IMintableAndDelegatable.sol";
import {ZkMerkleDistributor} from "src/ZkMerkleDistributor.sol";
import {Merkle} from "@murky/src/Merkle.sol";
import {console2, stdStorage, StdStorage} from "forge-std/Test.sol";

contract ZkMerkleDistributorTest is ZkTokenTest {
  Merkle merkle;

  error ZkMerkleDistributor__InvalidProof();

  // Type hash of the data that makes up the claim.
  bytes32 public constant ZK_CLAIM_TYPEHASH = keccak256(
    "Claim(uint256 index,address claimant,uint256 amount,bytes32[] merkleProof,address delegatee,uint256 expiry,uint256 nonce)"
  );

  // type hash for the delegation struct used in delegation by signature upon receiving a claim
  bytes32 constant DELEGATION_TYPEHASH = keccak256("Delegation(address delegatee,uint256 nonce,uint256 expiry)");

  struct MakeClaimSignatureParams {
    uint256 claimantPrivateKey;
    uint256 claimIndex;
    address claimant;
    uint256 amount;
    uint256 expiry;
    bytes32[] proof;
    address delegatee;
  }

  function setUp() public virtual override {
    super.setUp();
    merkle = new Merkle();
    vm.label(address(merkle), "merkle");
  }

  // Makes a Merkle tree leaf node for the index, claimant, and amount provided.
  function makeNode(uint256 _index, address _claimant, uint256 _amount) public pure returns (bytes32) {
    return keccak256(abi.encodePacked(_index, _claimant, _amount));
  }

  uint256 MAX_TREE_SIZE = 1000; // 1,000 claimants
  uint256 MAX_AMOUNT = 1_000_000_000 * 1e18; // 1 billion tokens

  // Make an address from two integers.
  function makeAddress(uint256 _a, uint256 _b) public pure returns (address) {
    return address(uint160(uint256(keccak256(abi.encodePacked(_a, _b)))));
  }

  // Builds an array of nodes for a Merkle tree, given a requested size, and a seed for randomness.
  // The function is also given a sample claim index, which will be used to leave an empty spot in the tree for a sample
  // claim.
  // Bot the tree and the total claimable amount in the tree are returned.
  function makeTreeArray(uint256 _treeSize, uint256 _seed, uint256 sampleClaimIndex)
    public
    view
    returns (bytes32[] memory, uint256 _totalClaimableAmountInTree)
  {
    bytes32[] memory _tree = new bytes32[](_treeSize);
    _totalClaimableAmountInTree = 0;
    for (uint256 _index = 0; _index < _treeSize; _index++) {
      uint256 _nodeAmount = bound(_seed, 1, MAX_AMOUNT);
      if (_index != sampleClaimIndex) {
        _tree[_index] = makeNode(_index, makeAddress(_index, _seed), _nodeAmount);
        _totalClaimableAmountInTree += _nodeAmount;
      }
    }
    return (_tree, _totalClaimableAmountInTree);
  }

  // requested claimant and amount stuffed into somewhere. Returns the Merkle root, the total claimable amount,
  // and the proof and index for the claimant.
  // The size of the tree will be _requestedTreeSize, but 0 will result in a large tree up to MAX_TREE_SIZE.
  // The seed is used to create a pseudorandom tree, and the claimant is placed at the index derived from the seed.
  function makeMerkleTreeWithSampleClaim(uint256 _requestedTreeSize, address _claimant, uint256 _amount, uint256 _seed)
    internal
    view
    returns (
      bytes32 _root,
      uint256 _totalClaimableAmountInTree,
      bytes32[] memory _tree,
      bytes32[] memory _proof,
      uint256 _claimantIndex
    )
  {
    uint256 _treeSize = (_requestedTreeSize == 0) ? bound(_seed, 10, MAX_TREE_SIZE) : _requestedTreeSize;
    uint256 _indexSeedHash = uint256(keccak256(abi.encode(_seed)));
    _claimantIndex = bound(_indexSeedHash, 0, _treeSize - 1);

    // create a tree
    (bytes32[] memory _builtTree, uint256 _totalClaimableAmount) = makeTreeArray(_treeSize, _seed, _claimantIndex);

    // stuff the sample claim at the random index in the tree
    _builtTree[_claimantIndex] = makeNode(_claimantIndex, _claimant, _amount);

    // setup to return the tree root, the proof for the claimant, and the total claimable amount in the tree (including
    // the sample claim)
    _tree = _builtTree;
    _root = merkle.getRoot(_tree);
    _proof = merkle.getProof(_tree, _claimantIndex);
    _totalClaimableAmountInTree = _totalClaimableAmount + _amount;
  }

  // Creates a DelegateInfo struct with the provided parameters.
  function createDelegateeInfo(address _delegatee, address _claimant, uint256 _claimantPrivateKey)
    internal
    view
    returns (ZkMerkleDistributor.DelegateInfo memory)
  {
    bytes32 _message =
      keccak256(abi.encode(DELEGATION_TYPEHASH, _delegatee, token.nonces(_claimant), block.timestamp + 12 hours));
    bytes32 _messageHash = keccak256(abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), _message));
    (uint8 _v, bytes32 _r, bytes32 _s) = vm.sign(_claimantPrivateKey, _messageHash);

    return ZkMerkleDistributor.DelegateInfo({
      delegatee: _delegatee,
      nonce: token.nonces(_claimant),
      expiry: block.timestamp + 12 hours,
      v: _v,
      r: _r,
      s: _s
    });
  }

  // Creates a claim signature with the provided parameters.
  function makeClaimSignature(MakeClaimSignatureParams memory _params, ZkMerkleDistributor _distributor)
    internal
    view
    returns (bytes memory _signature)
  {
    // Get nonce, using distributor
    uint256 _nonce = _distributor.nonces(_params.claimant);
    bytes32 _message = keccak256(
      abi.encode(
        ZK_CLAIM_TYPEHASH,
        _params.claimIndex,
        _params.claimant,
        _params.amount,
        _params.proof,
        _params.delegatee,
        _params.expiry,
        _nonce
      )
    );
    bytes32 _messageHash = keccak256(abi.encodePacked("\x19\x01", _distributor.DOMAIN_SEPARATOR(), _message));
    (uint8 _v, bytes32 _r, bytes32 _s) = vm.sign(_params.claimantPrivateKey, _messageHash);
    _signature = abi.encodePacked(_r, _s, _v);
  }

  function calculateDomainSeparator(address _distributor) public view returns (bytes32) {
    return keccak256(
      abi.encode(
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
        keccak256(bytes("ZkMerkleDistributor")),
        keccak256(bytes("1")),
        block.chainid,
        _distributor
      )
    );
  }
}

contract Constructor is ZkMerkleDistributorTest {
  function testFuzz_InitializesTheContractStateWithTheArgumentsPassed(
    address _admin,
    bytes32 _merkleRoot,
    uint256 _maxTotalClaimable,
    uint256 _windowStart,
    uint256 _windowEnd
  ) public {
    ZkMerkleDistributor _distributor = new ZkMerkleDistributor(
      _admin, IMintableAndDelegatable(address(token)), _merkleRoot, _maxTotalClaimable, _windowStart, _windowEnd
    );

    // Verify that the domain separator is setup correctly
    assertEq(_distributor.DOMAIN_SEPARATOR(), calculateDomainSeparator(address(_distributor)));

    vm.prank(admin);
    token.grantRole(MINTER_ROLE, address(_distributor));
    assertEq(address(_distributor.TOKEN()), address(token));
    assertEq(_distributor.ADMIN(), _admin);
    assertEq(_distributor.MERKLE_ROOT(), _merkleRoot);
    assertEq(_distributor.MAXIMUM_TOTAL_CLAIMABLE(), _maxTotalClaimable);
    assertEq(_distributor.WINDOW_START(), _windowStart);
    assertEq(_distributor.WINDOW_END(), _windowEnd);
  }
}

contract Claim is ZkMerkleDistributorTest {
  /// forge-config: default.fuzz.runs = 5
  /// forge-config: ci.fuzz.runs = 5
  /// forge-config: lite.fuzz.runs = 1
  function testFuzz_MintsTokensForAClaimantWithAValidMerkleProof(
    address _admin,
    uint256 _claimantPrivateKey,
    uint256 _amount,
    uint256 _seed,
    address _delegatee
  ) public {
    _amount = bound(_amount, 0, MAX_AMOUNT);
    _claimantPrivateKey = bound(_claimantPrivateKey, 1, 100e18);
    address _claimant = vm.addr(_claimantPrivateKey);
    _assumeNotProxyAdmin(_claimant);
    (bytes32 _merkleRoot, uint256 _totalClaimable,, bytes32[] memory _proof, uint256 _claimIndex) =
      makeMerkleTreeWithSampleClaim(0, _claimant, _amount, _seed);
    ZkMerkleDistributor _distributor = new ZkMerkleDistributor(
      _admin,
      IMintableAndDelegatable(address(token)),
      _merkleRoot,
      _totalClaimable,
      block.timestamp,
      block.timestamp + 1 days
    );
    vm.prank(admin);
    token.grantRole(MINTER_ROLE, address(_distributor));
    ZkMerkleDistributor.DelegateInfo memory _delegateeInfo =
      createDelegateeInfo(_delegatee, _claimant, _claimantPrivateKey);
    vm.warp(block.timestamp + 6 hours);
    vm.prank(_claimant);
    _distributor.claim(_claimIndex, _amount, _proof, _delegateeInfo);
    assertEq(token.balanceOf(_claimant), _amount);
    assertEq(token.delegates(_claimant), _delegatee);
  }

  /// forge-config: default.fuzz.runs = 5
  /// forge-config: ci.fuzz.runs = 5
  /// forge-config: lite.fuzz.runs = 1
  function testFuzz_RevertIf_TheClaimantProvidesAnInvalidMerkleProof(
    address _admin,
    uint256 _badClaimantPrivateKey,
    uint256 _amount,
    uint256 _seed,
    address _delegatee
  ) public {
    _amount = bound(_amount, 0, MAX_AMOUNT);
    _badClaimantPrivateKey = bound(_badClaimantPrivateKey, 1, 100e18);
    address _badClaimant = vm.addr(_badClaimantPrivateKey);
    vm.assume(_badClaimant != _delegatee);

    // create a tree with that doesn't contain the bad claimant
    (bytes32 _merkleRoot, uint256 _totalClaimable,, bytes32[] memory _proof, uint256 _claimIndex) =
      makeMerkleTreeWithSampleClaim(0, _delegatee, _amount, _seed);
    ZkMerkleDistributor _distributor = new ZkMerkleDistributor(
      _admin,
      IMintableAndDelegatable(address(token)),
      _merkleRoot,
      _totalClaimable,
      block.timestamp,
      block.timestamp + 1 days
    );
    vm.prank(admin);
    token.grantRole(MINTER_ROLE, address(_distributor));
    ZkMerkleDistributor.DelegateInfo memory _delegateeInfo =
      createDelegateeInfo(_delegatee, _badClaimant, _badClaimantPrivateKey);
    vm.warp(block.timestamp + 6 hours);
    vm.prank(_badClaimant);
    vm.expectRevert(abi.encodeWithSelector(ZkMerkleDistributor.ZkMerkleDistributor__InvalidProof.selector));
    _distributor.claim(_claimIndex, _amount, _proof, _delegateeInfo);
  }

  /// forge-config: default.fuzz.runs = 5
  /// forge-config: ci.fuzz.runs = 5
  /// forge-config: lite.fuzz.runs = 1
  function testFuzz_RevertIf_TheSameClaimantMakesARepeatClaim(
    address _admin,
    uint256 _claimantPrivateKey,
    uint256 _amount,
    uint256 _seed,
    address _delegatee
  ) public {
    _amount = bound(_amount, 0, MAX_AMOUNT);
    _claimantPrivateKey = bound(_claimantPrivateKey, 1, 100e18);
    address _claimant = vm.addr(_claimantPrivateKey);
    _assumeNotProxyAdmin(_claimant);
    (bytes32 _merkleRoot, uint256 _totalClaimable,, bytes32[] memory _proof, uint256 _claimIndex) =
      makeMerkleTreeWithSampleClaim(0, _claimant, _amount, _seed);
    ZkMerkleDistributor _distributor = new ZkMerkleDistributor(
      _admin,
      IMintableAndDelegatable(address(token)),
      _merkleRoot,
      _totalClaimable,
      block.timestamp,
      block.timestamp + 1 days
    );
    vm.prank(admin);
    token.grantRole(MINTER_ROLE, address(_distributor));
    ZkMerkleDistributor.DelegateInfo memory _delegateeInfo =
      createDelegateeInfo(_delegatee, _claimant, _claimantPrivateKey);
    vm.warp(block.timestamp + 6 hours);
    vm.prank(_claimant);
    _distributor.claim(_claimIndex, _amount, _proof, _delegateeInfo);
    assertEq(token.balanceOf(_claimant), _amount);
    assertEq(token.delegates(_claimant), _delegatee);
    vm.expectRevert(abi.encodeWithSelector(ZkMerkleDistributor.ZkMerkleDistributor__AlreadyClaimed.selector));
    _distributor.claim(_claimIndex, _amount, _proof, _delegateeInfo);
  }

  function testFuzz_RevertIf_TheClaimAmountExceedsTheClaimableCap(
    address _admin,
    uint256 _claimantPrivateKey,
    uint256 _amount,
    uint256 _seed,
    address _delegatee
  ) public {
    _claimantPrivateKey = bound(_claimantPrivateKey, 1, 100e18);
    address _claimant = vm.addr(_claimantPrivateKey);
    _assumeNotProxyAdmin(_claimant);
    _amount = bound(_amount, 0, MAX_AMOUNT);

    (bytes32 _merkleRoot, uint256 _totalClaimable,, bytes32[] memory _proof, uint256 _claimIndex) =
      makeMerkleTreeWithSampleClaim(5, _claimant, _amount, _seed);

    ZkMerkleDistributor _distributor = new ZkMerkleDistributor(
      _admin,
      IMintableAndDelegatable(address(token)),
      _merkleRoot,
      _totalClaimable,
      block.timestamp, // window open
      block.timestamp + 1 days // window close
    );

    vm.prank(admin);
    token.grantRole(MINTER_ROLE, address(_distributor));

    ZkMerkleDistributor.DelegateInfo memory _delegateeInfo =
      createDelegateeInfo(_delegatee, _claimant, _claimantPrivateKey);

    // The user will request some amount above what they're entitled to, that would exceed the
    // cap if the proof were valid.
    uint256 _requestAmount = bound(_amount, _totalClaimable + 1, type(uint208).max);

    vm.prank(_claimant);
    vm.expectRevert(abi.encodeWithSelector(ZkMerkleDistributor.ZkMerkleDistributor__ClaimAmountExceedsMaximum.selector));
    _distributor.claim(_claimIndex, _requestAmount, _proof, _delegateeInfo);
  }

  function testFuzz_RevertIf_AClaimIsMadeBeforeTheWindowIsOpen(
    address _admin,
    uint256 _claimantPrivateKey,
    uint256 _amount,
    uint256 _seed,
    address _delegatee
  ) public {
    _amount = bound(_amount, 0, MAX_AMOUNT);

    _claimantPrivateKey = bound(_claimantPrivateKey, 1, 100e18);
    address _claimant = vm.addr(_claimantPrivateKey);
    _assumeNotProxyAdmin(_claimant);

    (bytes32 _merkleRoot, uint256 _totalClaimable,, bytes32[] memory _proof, uint256 _claimIndex) =
      makeMerkleTreeWithSampleClaim(5, _claimant, _amount, _seed);

    ZkMerkleDistributor _distributor = new ZkMerkleDistributor(
      _admin,
      IMintableAndDelegatable(address(token)),
      _merkleRoot,
      _totalClaimable,
      block.timestamp + 1 days, // window open
      block.timestamp + 2 days // window close
    );

    vm.prank(admin);
    token.grantRole(MINTER_ROLE, address(_distributor));

    ZkMerkleDistributor.DelegateInfo memory _delegateeInfo =
      createDelegateeInfo(_delegatee, _claimant, _claimantPrivateKey);
    vm.warp(block.timestamp + 2 days);

    vm.prank(_claimant);
    vm.expectRevert(abi.encodeWithSelector(ZkMerkleDistributor.ZkMerkleDistributor__ClaimWindowNotOpen.selector));
    _distributor.claim(_claimIndex, _amount, _proof, _delegateeInfo);
  }

  function testFuzz_RevertIf_AClaimIsMadeAfterTheWindowHasClosed(
    address _admin,
    uint256 _claimantPrivateKey,
    uint256 _amount,
    uint256 _seed,
    address _delegatee
  ) public {
    _amount = bound(_amount, 0, MAX_AMOUNT);
    _claimantPrivateKey = bound(_claimantPrivateKey, 1, 100e18);
    address _claimant = vm.addr(_claimantPrivateKey);
    _assumeNotProxyAdmin(_claimant);
    (bytes32 _merkleRoot, uint256 _totalClaimable,, bytes32[] memory _proof, uint256 _claimIndex) =
      makeMerkleTreeWithSampleClaim(5, _claimant, _amount, _seed);
    ZkMerkleDistributor _distributor = new ZkMerkleDistributor(
      _admin,
      IMintableAndDelegatable(address(token)),
      _merkleRoot,
      _totalClaimable,
      block.timestamp,
      block.timestamp + 1 days
    );
    vm.prank(admin);
    token.grantRole(MINTER_ROLE, address(_distributor));
    ZkMerkleDistributor.DelegateInfo memory _delegateeInfo =
      createDelegateeInfo(_delegatee, _claimant, _claimantPrivateKey);
    vm.warp(block.timestamp + 2 days);
    vm.prank(_claimant);
    vm.expectRevert(abi.encodeWithSelector(ZkMerkleDistributor.ZkMerkleDistributor__ClaimWindowNotOpen.selector));
    _distributor.claim(_claimIndex, _amount, _proof, _delegateeInfo);
  }
}

contract ClaimOnBehalf is ZkMerkleDistributorTest {
  /// forge-config: default.fuzz.runs = 5
  /// forge-config: ci.fuzz.runs = 5
  /// forge-config: lite.fuzz.runs = 1
  function testFuzz_CanMakeClaimOnBehalfWithBigTree(
    address _admin,
    uint256 _claimantPrivateKey,
    uint256 _amount,
    uint256 _seed,
    address _delegatee,
    uint256 _expiry
  ) public {
    _amount = bound(_amount, 0, MAX_AMOUNT);
    _claimantPrivateKey = bound(_claimantPrivateKey, 1, 100e18);
    address _claimant = vm.addr(_claimantPrivateKey);
    _assumeNotProxyAdmin(_claimant);
    (bytes32 _merkleRoot, uint256 _totalClaimable,, bytes32[] memory _proof, uint256 _claimIndex) =
      makeMerkleTreeWithSampleClaim(0, _claimant, _amount, _seed);
    ZkMerkleDistributor _distributor = new ZkMerkleDistributor(
      _admin,
      IMintableAndDelegatable(address(token)),
      _merkleRoot,
      _totalClaimable,
      block.timestamp,
      block.timestamp + 1 days
    );
    vm.prank(admin);
    token.grantRole(MINTER_ROLE, address(_distributor));
    ZkMerkleDistributor.DelegateInfo memory _delegateeInfo =
      createDelegateeInfo(_delegatee, _claimant, _claimantPrivateKey);
    vm.warp(block.timestamp + 6 hours);
    _expiry = bound(_expiry, block.timestamp + 6 hours + 1, type(uint256).max);
    bytes memory _claimSignature = makeClaimSignature(
      MakeClaimSignatureParams({
        claimantPrivateKey: _claimantPrivateKey,
        claimIndex: _claimIndex,
        claimant: _claimant,
        amount: _amount,
        expiry: _expiry,
        proof: _proof,
        delegatee: _delegateeInfo.delegatee
      }),
      _distributor
    );

    ZkMerkleDistributor.ClaimSignatureInfo memory _claimSignatureInfo =
      ZkMerkleDistributor.ClaimSignatureInfo({signature: _claimSignature, signingClaimant: _claimant, expiry: _expiry});
    _distributor.claimOnBehalf(_claimIndex, _amount, _proof, _claimSignatureInfo, _delegateeInfo);
    assertEq(token.balanceOf(_claimant), _amount);
    assertEq(token.delegates(_claimant), _delegatee);
  }

  function testFuzz_RevertIf_ClaimOnBehalfAttemptedWithBadSignature(
    address _admin,
    uint256 _claimantPrivateKey,
    uint256 _nonClaimantPrivateKey,
    uint256 _amount,
    uint256 _seed,
    address _delegatee,
    uint256 _expiry
  ) public {
    _amount = bound(_amount, 0, MAX_AMOUNT);
    _claimantPrivateKey = bound(_claimantPrivateKey, 1, 100e18);
    _nonClaimantPrivateKey = bound(_nonClaimantPrivateKey, 1, 100e18);
    vm.assume(_claimantPrivateKey != _nonClaimantPrivateKey);
    address _claimant = vm.addr(_claimantPrivateKey);
    _assumeNotProxyAdmin(_claimant);
    (bytes32 _merkleRoot, uint256 _totalClaimable,, bytes32[] memory _proof, uint256 _claimIndex) =
      makeMerkleTreeWithSampleClaim(10, _claimant, _amount, _seed);
    ZkMerkleDistributor _distributor = new ZkMerkleDistributor(
      _admin,
      IMintableAndDelegatable(address(token)),
      _merkleRoot,
      _totalClaimable,
      block.timestamp,
      block.timestamp + 1 days
    );
    vm.prank(admin);
    token.grantRole(MINTER_ROLE, address(_distributor));
    ZkMerkleDistributor.DelegateInfo memory _delegateeInfo =
      createDelegateeInfo(_delegatee, _claimant, _claimantPrivateKey);
    vm.warp(block.timestamp + 6 hours);
    _expiry = bound(_expiry, block.timestamp + 6 hours + 1, type(uint256).max);
    bytes memory _claimSignature = makeClaimSignature(
      MakeClaimSignatureParams({
        claimantPrivateKey: _nonClaimantPrivateKey,
        claimIndex: _claimIndex,
        claimant: _claimant,
        amount: _amount,
        expiry: _expiry,
        proof: _proof,
        delegatee: _delegateeInfo.delegatee
      }),
      _distributor
    );
    ZkMerkleDistributor.ClaimSignatureInfo memory _claimSignatureInfo =
      ZkMerkleDistributor.ClaimSignatureInfo({signature: _claimSignature, signingClaimant: _claimant, expiry: _expiry});

    vm.expectRevert(abi.encodeWithSelector(ZkMerkleDistributor.ZkMerkleDistributor__InvalidSignature.selector));
    _distributor.claimOnBehalf(_claimIndex, _amount, _proof, _claimSignatureInfo, _delegateeInfo);
  }

  function testFuzz_RevertIf_ClaimOnBehalfAttemptedWithInvalidNonce(
    address _admin,
    uint256 _claimantPrivateKey,
    uint256 _amount,
    uint256 _seed,
    address _delegatee,
    uint256 _expiry
  ) public {
    _amount = bound(_amount, 0, MAX_AMOUNT);
    _claimantPrivateKey = bound(_claimantPrivateKey, 1, 100e18);
    address _claimant = vm.addr(_claimantPrivateKey);
    _assumeNotProxyAdmin(_claimant);
    (bytes32 _merkleRoot, uint256 _totalClaimable,, bytes32[] memory _proof, uint256 _claimIndex) =
      makeMerkleTreeWithSampleClaim(10, _claimant, _amount, _seed);
    ZkMerkleDistributor _distributor = new ZkMerkleDistributor(
      _admin,
      IMintableAndDelegatable(address(token)),
      _merkleRoot,
      _totalClaimable,
      block.timestamp,
      block.timestamp + 1 days
    );
    vm.prank(admin);
    token.grantRole(MINTER_ROLE, address(_distributor));
    ZkMerkleDistributor.DelegateInfo memory _delegateeInfo =
      createDelegateeInfo(_delegatee, _claimant, _claimantPrivateKey);
    vm.warp(block.timestamp + 6 hours);
    _expiry = bound(_expiry, block.timestamp + 6 hours + 1, type(uint256).max);
    bytes memory _claimSignature = makeClaimSignature(
      MakeClaimSignatureParams({
        claimantPrivateKey: _claimantPrivateKey,
        claimIndex: _claimIndex,
        claimant: _claimant,
        amount: _amount,
        expiry: _expiry,
        proof: _proof,
        delegatee: _delegateeInfo.delegatee
      }),
      _distributor
    );
    ZkMerkleDistributor.ClaimSignatureInfo memory _claimSignatureInfo =
      ZkMerkleDistributor.ClaimSignatureInfo({signature: _claimSignature, signingClaimant: _claimant, expiry: _expiry});

    vm.prank(_claimant);
    _distributor.invalidateNonce();

    vm.expectRevert(abi.encodeWithSelector(ZkMerkleDistributor.ZkMerkleDistributor__InvalidSignature.selector));
    _distributor.claimOnBehalf(_claimIndex, _amount, _proof, _claimSignatureInfo, _delegateeInfo);
  }

  function testFuzz_RevertIf_ClaimOnBehalfAttemptedWithExpiredSignature(
    address _admin,
    uint256 _claimantPrivateKey,
    uint256 _amount,
    uint256 _seed,
    address _delegatee,
    uint256 _expiry
  ) public {
    _amount = bound(_amount, 0, MAX_AMOUNT);
    _claimantPrivateKey = bound(_claimantPrivateKey, 1, 100e18);
    address _claimant = vm.addr(_claimantPrivateKey);
    _assumeNotProxyAdmin(_claimant);
    (bytes32 _merkleRoot, uint256 _totalClaimable,, bytes32[] memory _proof, uint256 _claimIndex) =
      makeMerkleTreeWithSampleClaim(10, _claimant, _amount, _seed);
    ZkMerkleDistributor _distributor = new ZkMerkleDistributor(
      _admin,
      IMintableAndDelegatable(address(token)),
      _merkleRoot,
      _totalClaimable,
      block.timestamp,
      block.timestamp + 1 days
    );
    vm.prank(admin);
    token.grantRole(MINTER_ROLE, address(_distributor));
    ZkMerkleDistributor.DelegateInfo memory _delegateeInfo =
      createDelegateeInfo(_delegatee, _claimant, _claimantPrivateKey);

    _expiry = bound(_expiry, 0, block.timestamp + 6 hours);
    vm.warp(block.timestamp + 6 hours);
    bytes memory _claimSignature = makeClaimSignature(
      MakeClaimSignatureParams({
        claimantPrivateKey: _claimantPrivateKey,
        claimIndex: _claimIndex,
        claimant: _claimant,
        amount: _amount,
        expiry: _expiry,
        proof: _proof,
        delegatee: _delegateeInfo.delegatee
      }),
      _distributor
    );
    ZkMerkleDistributor.ClaimSignatureInfo memory _claimSignatureInfo =
      ZkMerkleDistributor.ClaimSignatureInfo({signature: _claimSignature, signingClaimant: _claimant, expiry: _expiry});

    vm.expectRevert(abi.encodeWithSelector(ZkMerkleDistributor.ZkMerkleDistributor__ExpiredSignature.selector));
    _distributor.claimOnBehalf(_claimIndex, _amount, _proof, _claimSignatureInfo, _delegateeInfo);
  }
}

contract SweepUnclaimed is ZkMerkleDistributorTest {
  function testFuzz_AllowsTheAdminToMintAndSweepAllUnclaimedTokensAfterTheWindowHasClosed(
    address _admin,
    uint256 _claimantPrivateKey,
    uint256 _amount,
    uint256 _seed,
    address _delegatee,
    address _unclaimedReceiver
  ) public {
    _amount = bound(_amount, 0, MAX_AMOUNT);
    vm.assume(_unclaimedReceiver != address(0) && _delegatee != address(0) && _delegatee != _unclaimedReceiver);

    _claimantPrivateKey = bound(_claimantPrivateKey, 1, 100e18);
    address _claimant = vm.addr(_claimantPrivateKey);
    _assumeNotProxyAdmin(_claimant);

    (bytes32 _merkleRoot, uint256 _totalClaimable,, bytes32[] memory _proof, uint256 _claimIndex) =
      makeMerkleTreeWithSampleClaim(10, _claimant, _amount, _seed);

    ZkMerkleDistributor _distributor = new ZkMerkleDistributor(
      _admin,
      IMintableAndDelegatable(address(token)),
      _merkleRoot,
      _totalClaimable,
      block.timestamp,
      block.timestamp + 1 days
    );

    uint256 _unclaimedReceiverInitialBalance = token.balanceOf(_unclaimedReceiver);

    vm.prank(admin);
    token.grantRole(MINTER_ROLE, address(_distributor));
    ZkMerkleDistributor.DelegateInfo memory _delegateeInfo =
      createDelegateeInfo(_delegatee, _claimant, _claimantPrivateKey);

    vm.warp(block.timestamp + 6 hours);
    vm.prank(_claimant);
    _distributor.claim(_claimIndex, _amount, _proof, _delegateeInfo);

    assertEq(token.balanceOf(_claimant), _amount);
    assertEq(token.delegates(_claimant), _delegatee);

    vm.warp(block.timestamp + 2 days);
    vm.prank(_admin);
    _distributor.sweepUnclaimed(_unclaimedReceiver);
    assertEq(token.balanceOf(_unclaimedReceiver) - _unclaimedReceiverInitialBalance, _totalClaimable - _amount);
  }

  function testFuzz_RevertIf_TheAdminAttemptsToSweepASecondTime(
    address _admin,
    uint256 _claimantPrivateKey,
    uint256 _amount,
    uint256 _seed,
    address _delegatee,
    address _unclaimedReceiver
  ) public {
    _amount = bound(_amount, 0, MAX_AMOUNT);
    vm.assume(_unclaimedReceiver != address(0));
    vm.assume(_delegatee != address(0));
    vm.assume(_delegatee != _unclaimedReceiver);
    _claimantPrivateKey = bound(_claimantPrivateKey, 1, 100e18);
    address _claimant = vm.addr(_claimantPrivateKey);
    _assumeNotProxyAdmin(_claimant);
    (bytes32 _merkleRoot, uint256 _totalClaimable,, bytes32[] memory _proof, uint256 _claimIndex) =
      makeMerkleTreeWithSampleClaim(10, _claimant, _amount, _seed);
    ZkMerkleDistributor _distributor = new ZkMerkleDistributor(
      _admin,
      IMintableAndDelegatable(address(token)),
      _merkleRoot,
      _totalClaimable,
      block.timestamp,
      block.timestamp + 1 days
    );
    vm.prank(admin);
    token.grantRole(MINTER_ROLE, address(_distributor));
    ZkMerkleDistributor.DelegateInfo memory _delegateeInfo =
      createDelegateeInfo(_delegatee, _claimant, _claimantPrivateKey);
    vm.warp(block.timestamp + 6 hours);
    vm.prank(_claimant);
    _distributor.claim(_claimIndex, _amount, _proof, _delegateeInfo);
    assertEq(token.balanceOf(_claimant), _amount);
    assertEq(token.delegates(_claimant), _delegatee);
    vm.warp(block.timestamp + 2 days);
    vm.prank(_admin);
    _distributor.sweepUnclaimed(_unclaimedReceiver);
    assertEq(token.balanceOf(_unclaimedReceiver), _totalClaimable - _amount);
    vm.prank(_admin);
    vm.expectRevert(abi.encodeWithSelector(ZkMerkleDistributor.ZkMerkleDistributor__SweepAlreadyDone.selector));
    _distributor.sweepUnclaimed(_unclaimedReceiver);
  }

  function testFuzz_RevertIf_TheClaimWindowHasNotYetOpened(
    address _admin,
    uint256 _claimantPrivateKey,
    uint256 _amount,
    uint256 _seed,
    address _delegatee,
    address _unclaimedReceiver
  ) public {
    _amount = bound(_amount, 0, MAX_AMOUNT);
    vm.assume(_unclaimedReceiver != address(0) && _delegatee != address(0) && _delegatee != _unclaimedReceiver);
    _claimantPrivateKey = bound(_claimantPrivateKey, 1, 100e18);
    address _claimant = vm.addr(_claimantPrivateKey);
    _assumeNotProxyAdmin(_claimant);

    (bytes32 _merkleRoot, uint256 _totalClaimable,,,) = makeMerkleTreeWithSampleClaim(5, _claimant, _amount, _seed);

    ZkMerkleDistributor _distributor = new ZkMerkleDistributor(
      _admin,
      IMintableAndDelegatable(address(token)),
      _merkleRoot,
      _totalClaimable,
      block.timestamp + 1 days,
      block.timestamp + 2 days
    );

    vm.prank(admin);
    token.grantRole(MINTER_ROLE, address(_distributor));

    vm.prank(_admin);
    vm.expectRevert(abi.encodeWithSelector(ZkMerkleDistributor.ZkMerkleDistributor__ClaimWindowNotYetClosed.selector));
    _distributor.sweepUnclaimed(_unclaimedReceiver);
  }

  function testFuzz_RevertIf_TheClaimWindowIsOpen(
    address _admin,
    uint256 _claimantPrivateKey,
    uint256 _amount,
    uint256 _seed,
    address _delegatee,
    address _unclaimedReceiver
  ) public {
    _amount = bound(_amount, 0, MAX_AMOUNT);
    vm.assume(_unclaimedReceiver != address(0));
    vm.assume(_delegatee != address(0));
    vm.assume(_delegatee != _unclaimedReceiver);
    _claimantPrivateKey = bound(_claimantPrivateKey, 1, 100e18);
    address _claimant = vm.addr(_claimantPrivateKey);
    _assumeNotProxyAdmin(_claimant);
    (bytes32 _merkleRoot, uint256 _totalClaimable,, bytes32[] memory _proof, uint256 _claimIndex) =
      makeMerkleTreeWithSampleClaim(5, _claimant, _amount, _seed);
    ZkMerkleDistributor _distributor = new ZkMerkleDistributor(
      _admin,
      IMintableAndDelegatable(address(token)),
      _merkleRoot,
      _totalClaimable,
      block.timestamp,
      block.timestamp + 1 days
    );
    vm.prank(admin);
    token.grantRole(MINTER_ROLE, address(_distributor));
    ZkMerkleDistributor.DelegateInfo memory _delegateeInfo =
      createDelegateeInfo(_delegatee, _claimant, _claimantPrivateKey);
    vm.warp(block.timestamp + 6 hours);
    vm.prank(_claimant);
    _distributor.claim(_claimIndex, _amount, _proof, _delegateeInfo);
    assertEq(token.balanceOf(_claimant), _amount);
    assertEq(token.delegates(_claimant), _delegatee);
    vm.warp(block.timestamp + 6 hours);
    vm.prank(_admin);
    vm.expectRevert(abi.encodeWithSelector(ZkMerkleDistributor.ZkMerkleDistributor__ClaimWindowNotYetClosed.selector));
    _distributor.sweepUnclaimed(_unclaimedReceiver);
  }

  function testFuzz_RevertIf_SweepUnclaimedAttemptedByNonAdmin(
    address _admin,
    uint256 _seed,
    address _unclaimedReceiver,
    address _nonAdmin
  ) public {
    vm.assume(_unclaimedReceiver != address(0));
    vm.assume(_nonAdmin != _admin);
    (bytes32 _merkleRoot, uint256 _totalClaimable,,,) = makeMerkleTreeWithSampleClaim(5, address(0), 0, _seed);
    ZkMerkleDistributor _distributor = new ZkMerkleDistributor(
      _admin,
      IMintableAndDelegatable(address(token)),
      _merkleRoot,
      _totalClaimable,
      block.timestamp,
      block.timestamp + 1 days
    );
    vm.prank(admin);
    token.grantRole(MINTER_ROLE, address(_distributor));
    vm.warp(block.timestamp + 2 days);
    vm.prank(_nonAdmin);
    vm.expectRevert(abi.encodeWithSelector(ZkMerkleDistributor.ZkMerkleDistributor__Unauthorized.selector, _nonAdmin));
    _distributor.sweepUnclaimed(_unclaimedReceiver);
  }
}

contract IsClaimed is ZkMerkleDistributorTest {
  function testFuzz_ReturnsFalseWhenTheClaimantHasNotYetClaimedTokens(address _admin, uint256 _seed) public {
    (bytes32 _merkleRoot, uint256 _totalClaimable,,, uint256 _claimIndex) =
      makeMerkleTreeWithSampleClaim(5, address(0), 0, _seed);
    ZkMerkleDistributor _distributor = new ZkMerkleDistributor(
      _admin,
      IMintableAndDelegatable(address(token)),
      _merkleRoot,
      _totalClaimable,
      block.timestamp,
      block.timestamp + 1 days
    );
    vm.prank(admin);
    token.grantRole(MINTER_ROLE, address(_distributor));
    vm.warp(block.timestamp + 6 hours);
    assertFalse(_distributor.isClaimed(_claimIndex));
  }

  function testFuzz_ReturnsTrueWhenTheClaimantHasClaimedTokens(address _admin, uint256 _seed) public {
    (address _claimant, uint256 _claimantPrivateKey) = makeAddrAndKey("claimant");
    uint256 _amount = 512e18;
    (bytes32 _merkleRoot, uint256 _totalClaimable,, bytes32[] memory _proof, uint256 _claimIndex) =
      makeMerkleTreeWithSampleClaim(5, _claimant, _amount, _seed);
    ZkMerkleDistributor _distributor = new ZkMerkleDistributor(
      _admin,
      IMintableAndDelegatable(address(token)),
      _merkleRoot,
      _totalClaimable,
      block.timestamp,
      block.timestamp + 1 days
    );
    vm.prank(admin);
    token.grantRole(MINTER_ROLE, address(_distributor));
    vm.warp(block.timestamp + 6 hours);

    ZkMerkleDistributor.DelegateInfo memory _delegateeInfo =
      createDelegateeInfo(makeAddr("delegatee"), _claimant, _claimantPrivateKey);

    vm.prank(_claimant);
    _distributor.claim(_claimIndex, _amount, _proof, _delegateeInfo);

    assertTrue(_distributor.isClaimed(_claimIndex));
  }

  function testFuzz_ReturnsTheCorrectClaimStatusForMultipleClaimants(
    address _admin,
    uint256 _claimantPrivateKey1,
    uint256 _claimantPrivateKey2,
    uint256 _amount1,
    uint256 _amount2,
    uint256 _seed,
    address _delegatee
  ) public {
    _amount1 = bound(_amount1, 0, MAX_AMOUNT);
    _amount2 = bound(_amount2, 0, MAX_AMOUNT);
    _claimantPrivateKey1 = bound(_claimantPrivateKey1, 1, 100e18);
    _claimantPrivateKey2 = bound(_claimantPrivateKey2, 1, 100e18);
    address _claimant1 = vm.addr(_claimantPrivateKey1);
    address _claimant2 = vm.addr(_claimantPrivateKey2);
    vm.assume(_claimant1 != _claimant2);

    // create a small tree with two claims (set claimant index on call such that no claim spot is left open)
    (bytes32[] memory _tree, uint256 _totalClaimable) = makeTreeArray(10, _seed, 11);
    _tree[3] = makeNode(3, _claimant1, _amount1);
    _tree[7] = makeNode(7, _claimant2, _amount2);
    bytes32 _merkleRoot = merkle.getRoot(_tree);
    _totalClaimable += _amount1 + _amount2;
    ZkMerkleDistributor _distributor = new ZkMerkleDistributor(
      _admin,
      IMintableAndDelegatable(address(token)),
      _merkleRoot,
      _totalClaimable,
      block.timestamp,
      block.timestamp + 1 days
    );
    vm.prank(admin);
    token.grantRole(MINTER_ROLE, address(_distributor));
    ZkMerkleDistributor.DelegateInfo memory _delegateeInfo1 =
      createDelegateeInfo(_delegatee, _claimant1, _claimantPrivateKey1);
    ZkMerkleDistributor.DelegateInfo memory _delegateeInfo2 =
      createDelegateeInfo(_delegatee, _claimant2, _claimantPrivateKey2);
    vm.warp(block.timestamp + 6 hours);
    bytes32[] memory _theProof = merkle.getProof(_tree, 3);
    vm.prank(_claimant1);
    _distributor.claim(3, _amount1, _theProof, _delegateeInfo1);
    _theProof = merkle.getProof(_tree, 7);
    vm.prank(_claimant2);
    _distributor.claim(7, _amount2, _theProof, _delegateeInfo2);
    assert(_distributor.isClaimed(3));
    assert(!_distributor.isClaimed(5));
    assert(_distributor.isClaimed(7));
  }
}

contract InvalidateNonce is ZkMerkleDistributorTest {
  using stdStorage for StdStorage;

  function testFuzz_InvalidateNonceForAMsgSender(address _caller, uint256 _initialNonce, uint256 _seed, address _admin)
    public
  {
    vm.assume(_caller != address(0));
    _initialNonce = bound(_initialNonce, 0, type(uint256).max - 1);

    (bytes32[] memory _tree, uint256 _totalClaimable) = makeTreeArray(10, _seed, 11);
    bytes32 _merkleRoot = merkle.getRoot(_tree);

    ZkMerkleDistributor _distributor = new ZkMerkleDistributor(
      _admin,
      IMintableAndDelegatable(address(token)),
      _merkleRoot,
      _totalClaimable,
      block.timestamp,
      block.timestamp + 1 days
    );
    stdstore.target(address(_distributor)).sig("nonces(address)").with_key(_caller).checked_write(_initialNonce);

    vm.prank(_caller);
    _distributor.invalidateNonce();

    uint256 _currentNonce = _distributor.nonces(_caller);
    assertEq(_currentNonce, _initialNonce + 1);
  }

  function testFuzz_InvalidateNonceForAMsgSenderMultipleTimes(
    address _caller,
    uint256 _initialNonce,
    uint256 _seed,
    address _admin
  ) public {
    vm.assume(_caller != address(0));
    _initialNonce = bound(_initialNonce, 0, type(uint256).max - 2);

    (bytes32[] memory _tree, uint256 _totalClaimable) = makeTreeArray(10, _seed, 11);
    bytes32 _merkleRoot = merkle.getRoot(_tree);

    ZkMerkleDistributor _distributor = new ZkMerkleDistributor(
      _admin,
      IMintableAndDelegatable(address(token)),
      _merkleRoot,
      _totalClaimable,
      block.timestamp,
      block.timestamp + 1 days
    );
    stdstore.target(address(_distributor)).sig("nonces(address)").with_key(_caller).checked_write(_initialNonce);

    vm.prank(_caller);
    _distributor.invalidateNonce();

    vm.prank(_caller);
    _distributor.invalidateNonce();

    uint256 _currentNonce = _distributor.nonces(_caller);
    assertEq(_currentNonce, _initialNonce + 2);
  }
}
