// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {BytecodeRepository} from "../../global/BytecodeRepository.sol";
import {IBytecodeRepository} from "../../interfaces/IBytecodeRepository.sol";
import {Bytecode, AuditorSignature} from "../../interfaces/Types.sol";
import {LibString} from "@solady/utils/LibString.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {IVersion} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IVersion.sol";
import {MockedVersionContract} from "../mocks/MockedVersionContract.sol";

contract BytecodeRepositoryTest is Test {
    using LibString for bytes32;
    using ECDSA for bytes32;

    BytecodeRepository public repository;
    address public owner;
    address public auditor;
    address public author;

    uint256 public auditorPK = vm.randomUint();

    uint256 public authorPK = vm.randomUint();

    bytes32 private constant _TEST_CONTRACT = "TEST_CONTRACT";
    uint256 private constant _TEST_VERSION = 310;
    string private constant _TEST_SOURCE = "ipfs://test";
    bytes32 private constant _TEST_SALT = bytes32(uint256(1));

    function setUp() public {
        owner = makeAddr("owner");
        auditor = vm.addr(auditorPK);
        author = vm.addr(authorPK);

        vm.startPrank(owner);
        repository = new BytecodeRepository(owner);
        repository.addAuditor(auditor, "Test Auditor");
        vm.stopPrank();
    }

    function _getMockBytecode(bytes32 _contractType, uint256 _version) internal pure returns (bytes memory) {
        return abi.encodePacked(type(MockedVersionContract).creationCode, abi.encode(_contractType, _version));
    }

    function _uploadTestBytecode() internal returns (bytes32 bytecodeHash) {
        bytes memory bytecode = _getMockBytecode(_TEST_CONTRACT, _TEST_VERSION);

        Bytecode memory bc = Bytecode({
            contractType: _TEST_CONTRACT,
            version: _TEST_VERSION,
            initCode: bytecode,
            author: author,
            source: _TEST_SOURCE,
            authorSignature: bytes("")
        });

        bytecodeHash = repository.computeBytecodeHash(bc);

        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(authorPK, repository.domainSeparatorV4().toTypedDataHash(bytecodeHash));
        bc.authorSignature = abi.encodePacked(r, s, v);

        vm.prank(author);
        repository.uploadBytecode(bc);
    }

    /// UPLOAD BYTECODE TESTS

    function test_BCR_01_uploadBytecode_works() public {
        bytes memory bytecode = _getMockBytecode(_TEST_CONTRACT, _TEST_VERSION);

        Bytecode memory bc = Bytecode({
            contractType: _TEST_CONTRACT,
            version: _TEST_VERSION,
            initCode: bytecode,
            author: author,
            source: _TEST_SOURCE,
            authorSignature: bytes("")
        });

        bytes32 bytecodeHash = repository.computeBytecodeHash(bc);

        // Sign bytecode hash with author's key
        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(authorPK, repository.domainSeparatorV4().toTypedDataHash(bytecodeHash));
        bc.authorSignature = abi.encodePacked(r, s, v);

        vm.prank(author);
        repository.uploadBytecode(bc);

        // Verify bytecode was stored
        assertTrue(repository.isBytecodeUploaded(bytecodeHash));

        Bytecode memory storedBc = repository.bytecodeByHash(bytecodeHash);
        assertEq(storedBc.contractType, _TEST_CONTRACT);
        assertEq(storedBc.version, _TEST_VERSION);
        assertEq(storedBc.author, author);
        assertEq(storedBc.source, _TEST_SOURCE);
    }

    function test_BCR_02_uploadBytecode_reverts_if_already_exists() public {
        bytes memory bytecode = _getMockBytecode(_TEST_CONTRACT, _TEST_VERSION);

        Bytecode memory bc = Bytecode({
            contractType: _TEST_CONTRACT,
            version: _TEST_VERSION,
            initCode: bytecode,
            author: author,
            source: _TEST_SOURCE,
            authorSignature: bytes("")
        });

        bytes32 bytecodeHash = repository.computeBytecodeHash(bc);

        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(authorPK, repository.domainSeparatorV4().toTypedDataHash(bytecodeHash));
        bc.authorSignature = abi.encodePacked(r, s, v);

        vm.startPrank(author);
        repository.uploadBytecode(bc);

        vm.expectRevert(IBytecodeRepository.BytecodeAlreadyExistsException.selector);
        repository.uploadBytecode(bc);
        vm.stopPrank();
    }

    function test_BCR_03_uploadBytecode_reverts_if_invalid_signature() public {
        bytes memory bytecode = _getMockBytecode(_TEST_CONTRACT, _TEST_VERSION);

        Bytecode memory bc = Bytecode({
            contractType: _TEST_CONTRACT,
            version: _TEST_VERSION,
            initCode: bytecode,
            author: author,
            source: _TEST_SOURCE,
            authorSignature: bytes("invalid signature")
        });

        vm.prank(author);
        vm.expectRevert("ECDSA: invalid signature length");
        repository.uploadBytecode(bc);
    }

    /// AUDITOR SIGNATURE TESTS

    function test_BCR_04_signBytecodeHash_works() public {
        // First upload bytecode
        bytes32 bytecodeHash = _uploadTestBytecode();

        // Now sign as auditor
        string memory reportUrl = "https://audit.report";
        bytes32 signatureHash = repository.domainSeparatorV4().toTypedDataHash(
            keccak256(abi.encode(repository.AUDITOR_SIGNATURE_TYPEHASH(), bytecodeHash, keccak256(bytes(reportUrl))))
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(auditorPK, signatureHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.prank(auditor);
        repository.signBytecodeHash(bytecodeHash, reportUrl, signature);

        // Verify signature was stored
        assertTrue(repository.isAuditBytecode(bytecodeHash));

        AuditorSignature[] memory sigs = repository.auditorSignaturesByHash(bytecodeHash);
        assertEq(sigs.length, 1);
        assertEq(sigs[0].auditor, auditor);
        assertEq(sigs[0].reportUrl, reportUrl);
        assertEq(sigs[0].signature, signature);
    }

    function test_BCR_05_signBytecodeHash_reverts_if_not_auditor() public {
        // First upload bytecode
        bytes32 bytecodeHash = _uploadTestBytecode();

        // Now sign as auditor
        string memory reportUrl = "https://audit.report";
        bytes32 signatureHash = repository.domainSeparatorV4().toTypedDataHash(
            keccak256(abi.encode(repository.AUDITOR_SIGNATURE_TYPEHASH(), bytecodeHash, keccak256(bytes(reportUrl))))
        );

        uint256 notAuditorPK = vm.randomUint();
        address notAuditor = vm.addr(notAuditorPK);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(notAuditorPK, signatureHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.prank(notAuditor);
        vm.expectRevert(abi.encodeWithSelector(IBytecodeRepository.SignerIsNotAuditorException.selector, notAuditor));
        repository.signBytecodeHash(bytecodeHash, reportUrl, signature);
    }

    /// DEPLOYMENT TESTS

    function test_BCR_06_deploy_works() public {
        // First upload bytecode
        bytes32 bytecodeHash = _uploadTestBytecode();

        // Now sign as auditor
        string memory reportUrl = "https://audit.report";
        bytes32 signatureHash = repository.domainSeparatorV4().toTypedDataHash(
            keccak256(abi.encode(repository.AUDITOR_SIGNATURE_TYPEHASH(), bytecodeHash, keccak256(bytes(reportUrl))))
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(auditorPK, signatureHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.prank(auditor);
        repository.signBytecodeHash(bytecodeHash, reportUrl, signature);

        // Mark as system contract to auto-approve
        vm.prank(owner);
        repository.allowSystemContract(bytecodeHash);

        // Now deploy
        address deployer = makeAddr("deployer");
        vm.prank(deployer);
        address deployed = repository.deploy(_TEST_CONTRACT, _TEST_VERSION, "", _TEST_SALT);

        // Verify deployment
        assertTrue(deployed.code.length > 0);
        assertEq(repository.deployedContracts(deployed), bytecodeHash);

        IVersion version = IVersion(deployed);
        assertEq(version.contractType(), _TEST_CONTRACT);
        assertEq(version.version(), _TEST_VERSION);
    }

    function test_BCR_07_deploy_reverts_if_not_approved() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IBytecodeRepository.BytecodeIsNotApprovedException.selector, _TEST_CONTRACT, _TEST_VERSION
            )
        );
        repository.deploy(_TEST_CONTRACT, _TEST_VERSION, "", _TEST_SALT);
    }

    function test_BCR_08_deploy_reverts_if_not_audited() public {
        // Upload but don't audit
        bytes memory bytecode = _getMockBytecode(_TEST_CONTRACT, _TEST_VERSION);

        Bytecode memory bc = Bytecode({
            contractType: _TEST_CONTRACT,
            version: _TEST_VERSION,
            initCode: bytecode,
            author: author,
            source: _TEST_SOURCE,
            authorSignature: bytes("")
        });

        bytes32 bytecodeHash = repository.computeBytecodeHash(bc);

        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(authorPK, repository.domainSeparatorV4().toTypedDataHash(bytecodeHash));
        bc.authorSignature = abi.encodePacked(r, s, v);

        vm.prank(author);
        repository.uploadBytecode(bc);

        // Mark as system contract to auto-approve
        vm.prank(owner);
        repository.allowSystemContract(bytecodeHash);

        vm.expectRevert(
            abi.encodeWithSelector(
                IBytecodeRepository.BytecodeIsNotApprovedException.selector, _TEST_CONTRACT, _TEST_VERSION
            )
        );
        repository.deploy(_TEST_CONTRACT, _TEST_VERSION, "", _TEST_SALT);
    }
}
