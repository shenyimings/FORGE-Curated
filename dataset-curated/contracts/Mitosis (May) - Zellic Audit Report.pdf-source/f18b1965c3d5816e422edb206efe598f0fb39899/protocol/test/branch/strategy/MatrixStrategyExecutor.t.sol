// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { console } from '@std/console.sol';

import { IERC20 } from '@oz/interfaces/IERC20.sol';
import { ERC1967Proxy } from '@oz/proxy/ERC1967/ERC1967Proxy.sol';
import { Strings } from '@oz/utils/Strings.sol';

import { MitosisVault, AssetAction } from '../../../src/branch/MitosisVault.sol';
import {
  MatrixStrategyExecutor, IMatrixStrategyExecutor
} from '../../../src/branch/strategy/MatrixStrategyExecutor.sol';
import { IMitosisVault } from '../../../src/interfaces/branch/IMitosisVault.sol';
import { IMitosisVaultEntrypoint } from '../../../src/interfaces/branch/IMitosisVaultEntrypoint.sol';
import { IMitosisVaultEOL, EOLAction } from '../../../src/interfaces/branch/IMitosisVaultEOL.sol';
import { IMitosisVaultMatrix, MatrixAction } from '../../../src/interfaces/branch/IMitosisVaultMatrix.sol';
import { StdError } from '../../../src/lib/StdError.sol';
import { MockERC20Snapshots } from '../../mock/MockERC20Snapshots.t.sol';
import { MockManagerWithMerkleVerification } from '../../mock/MockManagerWithMerkleVerification.t.sol';
import { MockMitosisVaultEntrypoint } from '../../mock/MockMitosisVaultEntrypoint.t.sol';
import { MockTestVault } from '../../mock/MockTestVault.t.sol';
import { MockTestVaultDecoderAndSanitizer } from '../../mock/MockTestVaultDecoderAndSanitizer.t.sol';
import { MockTestVaultTally } from '../../mock/MockTestVaultTally.t.sol';
import { Toolkit } from '../../util/Toolkit.sol';

contract MatrixStrategyExecutorTest is Toolkit {
  MitosisVault internal _mitosisVault;
  MatrixStrategyExecutor internal _matrixStrategyExecutor;
  MockManagerWithMerkleVerification internal _managerWithMerkleVerification;
  MockMitosisVaultEntrypoint internal _mitosisVaultEntrypoint;
  MockERC20Snapshots internal _token;
  MockTestVault internal _testVault;
  MockTestVaultDecoderAndSanitizer internal _testVaultDecoderAndSanitizer;
  MockTestVaultTally internal _testVaultTally;

  address immutable owner = makeAddr('owner');
  address immutable mitosis = makeAddr('mitosis');
  address immutable hubMatrixVault = makeAddr('hubMatrixVault');

  function setUp() public {
    _mitosisVault = MitosisVault(
      payable(new ERC1967Proxy(address(new MitosisVault()), abi.encodeCall(MitosisVault.initialize, (owner))))
    );

    _mitosisVaultEntrypoint = new MockMitosisVaultEntrypoint();

    _token = new MockERC20Snapshots();
    _token.initialize('Token', 'TKN');

    _matrixStrategyExecutor = MatrixStrategyExecutor(
      payable(
        _proxy(
          address(new MatrixStrategyExecutor()),
          abi.encodeCall(MatrixStrategyExecutor.initialize, (_mitosisVault, _token, hubMatrixVault, owner))
        )
      )
    );

    _managerWithMerkleVerification = new MockManagerWithMerkleVerification();

    _testVault = new MockTestVault(address(_token));
    _testVaultTally = new MockTestVaultTally(address(_token), address(_testVault));
    _testVaultDecoderAndSanitizer = new MockTestVaultDecoderAndSanitizer();

    vm.startPrank(owner);

    _mitosisVault.setEntrypoint(address(_mitosisVaultEntrypoint));

    _matrixStrategyExecutor.setTally(address(_testVaultTally));
    _matrixStrategyExecutor.setExecutor(address(_managerWithMerkleVerification));

    vm.stopPrank();
  }

  function test_execute() public {
    (
      bytes32[][] memory manageProofs,
      address[] memory decodersAndSanitizers,
      address[] memory targets,
      bytes[] memory targetData,
      uint256[] memory values
    ) = _makeTestVaultManageVaultWithMerkleVerificationParams(makeAddr('user1'), 100 ether);

    vm.prank(owner);
    _token.mint(makeAddr('user1'), 100 ether);
    vm.prank(makeAddr('user1'));
    _token.approve(address(_testVault), 100 ether);

    assertEq(_token.balanceOf(makeAddr('user1')), 100 ether);
    assertEq(_token.balanceOf(address(_testVault)), 0);
    assertEq(_testVaultTally.totalBalance(''), 0);

    _managerWithMerkleVerification.manageVaultWithMerkleVerification(
      address(_matrixStrategyExecutor), manageProofs, decodersAndSanitizers, targets, targetData, values
    );

    assertEq(_token.balanceOf(makeAddr('user1')), 0);
    assertEq(_token.balanceOf(address(_testVault)), 100 ether);
    assertEq(_testVaultTally.totalBalance(''), 100 ether);
  }

  function test_execute_InvalidAddress_executor() public {
    vm.prank(owner);
    _matrixStrategyExecutor.setExecutor(makeAddr('fakeExecutor'));

    (
      bytes32[][] memory manageProofs,
      address[] memory decodersAndSanitizers,
      address[] memory targets,
      bytes[] memory targetData,
      uint256[] memory values
    ) = _makeTestVaultManageVaultWithMerkleVerificationParams(makeAddr('user1'), 100 ether);

    vm.prank(owner);
    _token.mint(makeAddr('user1'), 100 ether);
    vm.prank(makeAddr('user1'));
    _token.approve(address(_testVault), 100 ether);

    assertEq(_token.balanceOf(makeAddr('user1')), 100 ether);
    assertEq(_token.balanceOf(address(_testVault)), 0);
    assertEq(_testVaultTally.totalBalance(''), 0);

    vm.expectRevert(StdError.Unauthorized.selector);
    _managerWithMerkleVerification.manageVaultWithMerkleVerification(
      address(_matrixStrategyExecutor), manageProofs, decodersAndSanitizers, targets, targetData, values
    );
  }

  function test_execute_InvalidAddress_TallyNotSet() public {
    (
      bytes32[][] memory manageProofs,
      address[] memory decodersAndSanitizers,
      address[] memory targets,
      bytes[] memory targetData,
      uint256[] memory values
    ) = _makeTestVaultManageVaultWithMerkleVerificationParams(makeAddr('user1'), 100 ether);

    MockTestVault testVault2 = new MockTestVault(address(_token));
    targets[0] = address(testVault2);

    vm.prank(owner);
    _token.mint(makeAddr('user1'), 100 ether);
    vm.prank(makeAddr('user1'));
    _token.approve(address(testVault2), 100 ether);

    vm.expectRevert(_errTallyNotSet(address(testVault2)));
    _managerWithMerkleVerification.manageVaultWithMerkleVerification(
      address(_matrixStrategyExecutor), manageProofs, decodersAndSanitizers, targets, targetData, values
    );
  }

  function _makeTestVaultManageVaultWithMerkleVerificationParams(address from, uint256 amount)
    internal
    view
    returns (
      bytes32[][] memory manageProofs,
      address[] memory decodersAndSanitizers,
      address[] memory targets,
      bytes[] memory targetData,
      uint256[] memory values
    )
  {
    manageProofs = new bytes32[][](1);
    manageProofs[0] = new bytes32[](1);

    decodersAndSanitizers = new address[](1);

    targets = new address[](1);
    targets[0] = address(_testVault);

    targetData = new bytes[](1);
    targetData[0] = abi.encodeCall(_testVault.deposit, (from, amount));

    values = new uint256[](1);
    values[0] = 0;
  }

  function _errTallyNotSet(address implementation) internal pure returns (bytes memory) {
    return abi.encodeWithSelector(IMatrixStrategyExecutor.IMatrixStrategyExecutor__TallyNotSet.selector, implementation);
  }
}
