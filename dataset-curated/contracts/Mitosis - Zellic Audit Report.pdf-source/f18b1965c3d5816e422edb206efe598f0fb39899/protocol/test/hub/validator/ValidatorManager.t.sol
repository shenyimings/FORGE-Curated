// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { console } from '@std/console.sol';
import { stdJson } from '@std/StdJson.sol';
import { Vm } from '@std/Vm.sol';

import { ERC1967Proxy } from '@oz/proxy/ERC1967/ERC1967Proxy.sol';
import { SafeCast } from '@oz/utils/math/SafeCast.sol';
import { Time } from '@oz/utils/types/Time.sol';

import { LibClone } from '@solady/utils/LibClone.sol';
import { LibString } from '@solady/utils/LibString.sol';

import { EpochFeeder } from '../../../src/hub/validator/EpochFeeder.sol';
import { ValidatorManager } from '../../../src/hub/validator/ValidatorManager.sol';
import { IConsensusValidatorEntrypoint } from
  '../../../src/interfaces/hub/consensus-layer/IConsensusValidatorEntrypoint.sol';
import { IEpochFeeder } from '../../../src/interfaces/hub/validator/IEpochFeeder.sol';
import { IValidatorManager } from '../../../src/interfaces/hub/validator/IValidatorManager.sol';
import { LibSecp256k1 } from '../../../src/lib/LibSecp256k1.sol';
import { MockContract } from '../../util/MockContract.sol';
import { Toolkit } from '../../util/Toolkit.sol';

contract ValidatorManagerTest is Toolkit {
  using SafeCast for uint256;
  using stdJson for string;
  using LibSecp256k1 for bytes;
  using LibString for *;

  struct ValidatorKey {
    address addr;
    uint256 privKey;
    bytes pubKey; // uncompressed
  }

  address owner = makeAddr('owner');
  uint256 jsonNonce = 0;
  uint256 epochInterval = 100 seconds;

  MockContract entrypoint;
  EpochFeeder epochFeeder;
  ValidatorManager manager;

  function setUp() public {
    entrypoint = new MockContract();

    epochFeeder = EpochFeeder(
      _proxy(
        address(new EpochFeeder()), //
        abi.encodeCall(
          EpochFeeder.initialize, (owner, Time.timestamp() + epochInterval.toUint48(), epochInterval.toUint48())
        )
      )
    );

    IValidatorManager.GenesisValidatorSet[] memory genesisValidators = new IValidatorManager.GenesisValidatorSet[](0);
    manager = ValidatorManager(
      _proxy(
        address(new ValidatorManager(epochFeeder, IConsensusValidatorEntrypoint(address(entrypoint)))),
        abi.encodeCall(
          ValidatorManager.initialize,
          (
            owner,
            1 ether,
            IValidatorManager.SetGlobalValidatorConfigRequest({
              initialValidatorDeposit: 1000 ether,
              collateralWithdrawalDelaySeconds: 1000 seconds,
              minimumCommissionRate: 100, // 1 %
              commissionRateUpdateDelayEpoch: 3 // 3 * 100 seconds
             }),
            genesisValidators
          )
        )
      )
    );
  }

  function test_init() public view {
    assertEq(manager.owner(), owner);
    assertEq(address(manager.epochFeeder()), address(epochFeeder));
    assertEq(address(manager.entrypoint()), address(entrypoint));

    IValidatorManager.GlobalValidatorConfigResponse memory config = manager.globalValidatorConfig();
    assertEq(config.initialValidatorDeposit, 1000 ether);
    assertEq(config.collateralWithdrawalDelaySeconds, 1000 seconds);
    assertEq(config.minimumCommissionRate, 100);
    assertEq(config.commissionRateUpdateDelayEpoch, 3);

    assertEq(manager.fee(), 1 ether);
    assertEq(manager.validatorCount(), 0);
  }

  function test_createValidator(string memory name) public returns (ValidatorKey memory) {
    ValidatorKey memory val = _makePubKey(name);

    uint256 fee = manager.fee();
    uint256 amount = 1000 ether;

    vm.deal(val.addr, amount + fee);

    bytes memory metadata = _buildMetadata(name, 'test-val', 'test validator of mitosis');

    uint256 validatorCount = manager.validatorCount();
    bytes memory compPubKey = LibSecp256k1.compressPubkey(val.pubKey);

    entrypoint.setCall(IConsensusValidatorEntrypoint.registerValidator.selector);
    entrypoint.setRet(
      abi.encodeCall(IConsensusValidatorEntrypoint.registerValidator, (val.addr, compPubKey, val.addr)), false, ''
    );

    vm.prank(val.addr);
    manager.createValidator{ value: amount + fee }(
      compPubKey,
      IValidatorManager.CreateValidatorRequest({
        operator: val.addr,
        withdrawalRecipient: val.addr,
        rewardManager: val.addr,
        commissionRate: 100,
        metadata: metadata
      })
    );

    entrypoint.assertLastCall(
      abi.encodeCall(IConsensusValidatorEntrypoint.registerValidator, (val.addr, compPubKey, val.addr)), amount
    );

    assertEq(manager.validatorCount(), validatorCount + 1);
    assertEq(manager.validatorAt(validatorCount + 1), val.addr);
    assertTrue(manager.isValidator(val.addr));

    IValidatorManager.ValidatorInfoResponse memory info = manager.validatorInfo(val.addr);
    assertEq(info.valAddr, val.addr);
    assertEq(info.operator, val.addr);
    assertEq(info.rewardManager, val.addr);
    assertEq(info.commissionRate, 100);
    assertEq(info.metadata, metadata);

    return val;
  }

  function test_createValidator_with_zero_fee() public {
    uint256 prevFee = manager.fee();

    vm.prank(owner);
    manager.setFee(0);

    test_createValidator('zero_fee');

    vm.prank(owner);
    manager.setFee(prevFee);
  }

  function test_depositCollateral() public {
    ValidatorKey memory val = test_createValidator('val-1');
    address operator = makeAddr('operator');
    address withdrawalRecipient = makeAddr('withdrawalRecipient');

    entrypoint.setCall(IConsensusValidatorEntrypoint.depositCollateral.selector);
    entrypoint.setRet(
      abi.encodeCall(IConsensusValidatorEntrypoint.depositCollateral, (val.addr, withdrawalRecipient)), false, ''
    );

    vm.prank(val.addr);
    manager.updateOperator(val.addr, operator);
    vm.prank(operator);
    manager.updateWithdrawalRecipient(val.addr, withdrawalRecipient);

    uint256 fee = manager.fee();
    uint256 amount = 1000 ether;

    vm.deal(operator, amount + fee);
    vm.prank(operator);
    manager.depositCollateral{ value: amount + fee }(val.addr);

    entrypoint.assertLastCall(
      abi.encodeCall(IConsensusValidatorEntrypoint.depositCollateral, (val.addr, withdrawalRecipient)), amount
    );
  }

  function test_depositCollateral_with_zero_fee() public {
    uint256 prevFee = manager.fee();

    vm.prank(owner);
    manager.setFee(0);

    test_depositCollateral();

    vm.prank(owner);
    manager.setFee(prevFee);
  }

  function test_withdrawCollateral() public {
    ValidatorKey memory val = test_createValidator('val-1');
    address operator = makeAddr('operator');
    address withdrawalRecipient = makeAddr('withdrawalRecipient');

    uint256 fee = manager.fee();
    uint256 amount = 1000 ether;

    entrypoint.setCall(IConsensusValidatorEntrypoint.withdrawCollateral.selector);
    entrypoint.setRet(
      abi.encodeCall(
        IConsensusValidatorEntrypoint.withdrawCollateral,
        (val.addr, amount, withdrawalRecipient, _now48() + 1000 seconds)
      ),
      false,
      ''
    );

    vm.prank(val.addr);
    manager.updateOperator(val.addr, operator);
    vm.prank(operator);
    manager.updateWithdrawalRecipient(val.addr, withdrawalRecipient);

    vm.prank(operator);
    if (fee != 0) {
      vm.expectRevert(IValidatorManager.IValidatorManager__InsufficientFee.selector);
    }
    manager.withdrawCollateral(val.addr, amount);

    vm.deal(operator, fee);

    vm.prank(operator);
    manager.withdrawCollateral{ value: fee }(val.addr, amount);

    entrypoint.assertLastCall(
      abi.encodeCall(
        IConsensusValidatorEntrypoint.withdrawCollateral,
        (val.addr, amount, withdrawalRecipient, _now48() + 1000 seconds)
      )
    );
  }

  function test_withdrawCollateral_with_zero_fee() public {
    uint256 prevFee = manager.fee();

    vm.prank(owner);
    manager.setFee(0);

    test_withdrawCollateral();

    vm.prank(owner);
    manager.setFee(prevFee);
  }

  function test_unjailValidator() public {
    ValidatorKey memory val = test_createValidator('val-1');
    address operator = makeAddr('operator');

    entrypoint.setCall(IConsensusValidatorEntrypoint.unjail.selector);
    entrypoint.setRet(abi.encodeCall(IConsensusValidatorEntrypoint.unjail, (val.addr)), false, '');

    vm.prank(val.addr);
    manager.updateOperator(val.addr, operator);

    uint256 fee = manager.fee();

    vm.prank(operator);
    if (fee != 0) {
      vm.expectRevert(IValidatorManager.IValidatorManager__InsufficientFee.selector);
    }
    manager.unjailValidator(val.addr);

    vm.deal(operator, fee);

    vm.prank(operator);
    manager.unjailValidator{ value: fee }(val.addr);

    entrypoint.assertLastCall(abi.encodeCall(IConsensusValidatorEntrypoint.unjail, (val.addr)));
  }

  function test_unjailValidator_with_zero_fee() public {
    uint256 prevFee = manager.fee();

    vm.prank(owner);
    manager.setFee(0);

    test_unjailValidator();

    vm.prank(owner);
    manager.setFee(prevFee);
  }

  function test_setFee() public {
    assertEq(manager.fee(), 1 ether);

    vm.expectRevert(_errOwnableUnauthorizedAccount(address(this)));
    manager.setFee(5 ether);

    vm.prank(owner);
    manager.setFee(5 ether);
    assertEq(manager.fee(), 5 ether);

    vm.prank(owner);
    manager.setFee(0);
    assertEq(manager.fee(), 0);

    vm.prank(owner);
    manager.setFee(1 ether);
  }

  function test_updateOperator() public {
    ValidatorKey memory val = test_createValidator('val-1');
    address newOperator = makeAddr('newOperator');

    vm.prank(val.addr);
    manager.updateOperator(val.addr, newOperator);

    assertEq(manager.validatorInfo(val.addr).operator, newOperator);
  }

  function test_updateRewardManager() public {
    ValidatorKey memory val = test_createValidator('val-1');
    address newOperator = makeAddr('newOperator');
    address newManager = makeAddr('newManager');

    vm.prank(val.addr);
    manager.updateOperator(val.addr, newOperator);

    vm.prank(newOperator);
    manager.updateRewardManager(val.addr, newManager);

    assertEq(manager.validatorInfo(val.addr).rewardManager, newManager);
  }

  function test_updateMetadata() public {
    ValidatorKey memory val = test_createValidator('val-1');
    address newOperator = makeAddr('newOperator');
    bytes memory newMetadata = _buildMetadata('val-2', 'test-val-2', 'test validator of mitosis-2');

    vm.prank(val.addr);
    manager.updateOperator(val.addr, newOperator);

    vm.prank(newOperator);
    manager.updateMetadata(val.addr, newMetadata);

    assertEq(manager.validatorInfo(val.addr).metadata, newMetadata);
  }

  function test_updateRewardConfig() public {
    ValidatorKey memory val = test_createValidator('val-1');

    uint256 newCommissionRate = 200;
    uint256 previousCommissionRate = manager.validatorInfo(val.addr).commissionRate;
    uint256 commissionRateUpdateDelayEpoch = manager.globalValidatorConfig().commissionRateUpdateDelayEpoch;

    vm.prank(val.addr);
    manager.updateRewardConfig(
      val.addr, IValidatorManager.UpdateRewardConfigRequest({ commissionRate: newCommissionRate })
    );

    assertEq(manager.validatorInfo(val.addr).commissionRate, previousCommissionRate);

    vm.warp(block.timestamp + epochInterval * commissionRateUpdateDelayEpoch);
    assertEq(manager.validatorInfo(val.addr).commissionRate, newCommissionRate);

    assertEq(manager.validatorInfoAt(0, val.addr).commissionRate, previousCommissionRate);
    assertEq(manager.validatorInfoAt(1, val.addr).commissionRate, previousCommissionRate);
    assertEq(manager.validatorInfoAt(2, val.addr).commissionRate, previousCommissionRate);
    assertEq(manager.validatorInfoAt(3, val.addr).commissionRate, newCommissionRate);

    previousCommissionRate = newCommissionRate;
    newCommissionRate = 300;

    vm.prank(val.addr);
    manager.updateRewardConfig(
      val.addr, IValidatorManager.UpdateRewardConfigRequest({ commissionRate: newCommissionRate })
    );

    vm.warp(block.timestamp + epochInterval * commissionRateUpdateDelayEpoch);
    assertEq(manager.validatorInfo(val.addr).commissionRate, newCommissionRate);

    assertEq(manager.validatorInfoAt(3, val.addr).commissionRate, previousCommissionRate);
    assertEq(manager.validatorInfoAt(4, val.addr).commissionRate, previousCommissionRate);
    assertEq(manager.validatorInfoAt(5, val.addr).commissionRate, previousCommissionRate);
    assertEq(manager.validatorInfoAt(6, val.addr).commissionRate, newCommissionRate);
  }

  function _makePubKey(string memory name) internal returns (ValidatorKey memory) {
    (address addr, uint256 privKey) = makeAddrAndKey(name);
    Vm.Wallet memory wallet = vm.createWallet(privKey);
    bytes memory pubKey = abi.encodePacked(hex'04', wallet.publicKeyX, wallet.publicKeyY);

    // verify
    LibSecp256k1.verifyUncmpPubkey(pubKey);
    LibSecp256k1.verifyUncmpPubkeyWithAddress(pubKey, addr);

    return ValidatorKey({ addr: addr, privKey: privKey, pubKey: pubKey });
  }

  function _buildMetadata(string memory name, string memory moniker, string memory description)
    internal
    returns (bytes memory)
  {
    string memory key = string.concat('metadata', (jsonNonce++).toString());
    string memory out;

    out = key.serialize('name', name);
    out = key.serialize('moniker', moniker);
    out = key.serialize('description', description);
    out = key.serialize('website', string('https://mitosis.org'));
    out = key.serialize('image_url', string('https://picsum.photos/200/300'));

    return bytes(out);
  }
}
