// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ZkTokenTest} from "test/utils/ZkTokenTest.sol";
import {IMintableAndDelegatable} from "src/interfaces/IMintableAndDelegatable.sol";
import {ZkCappedMinter} from "src/ZkCappedMinter.sol";
import {console2} from "forge-std/Test.sol";

contract ZkCappedMinterTest is ZkTokenTest {
  function setUp() public virtual override {
    super.setUp();
  }

  function createCappedMinter(address _admin, uint256 _cap) internal returns (ZkCappedMinter) {
    ZkCappedMinter cappedMinter = new ZkCappedMinter(IMintableAndDelegatable(address(token)), _admin, _cap);
    vm.prank(admin);
    token.grantRole(MINTER_ROLE, address(cappedMinter));
    return cappedMinter;
  }
}

contract Constructor is ZkCappedMinterTest {
  function testFuzz_InitializesTheCappedMinterForAssociationAndFoundation(address _cappedMinterAdmin, uint256 _cap)
    public
  {
    _cap = bound(_cap, 0, MAX_MINT_SUPPLY);
    ZkCappedMinter cappedMinter = createCappedMinter(_cappedMinterAdmin, _cap);
    assertEq(address(cappedMinter.TOKEN()), address(token));
    assertEq(cappedMinter.ADMIN(), _cappedMinterAdmin);
    assertEq(cappedMinter.CAP(), _cap);
  }
}

contract Mint is ZkCappedMinterTest {
  function testFuzz_MintsNewTokensWhenTheAmountRequestedIsBelowTheCap(
    address _cappedMinterAdmin,
    address _receiver,
    uint256 _cap,
    uint256 _amount
  ) public {
    _cap = bound(_cap, 0, MAX_MINT_SUPPLY);
    _amount = bound(_amount, 1, MAX_MINT_SUPPLY);
    vm.assume(_cap > _amount);
    vm.assume(_receiver != address(0) && _receiver != initMintReceiver);
    ZkCappedMinter cappedMinter = createCappedMinter(_cappedMinterAdmin, _cap);
    vm.prank(_cappedMinterAdmin);
    cappedMinter.mint(_receiver, _amount);
    assertEq(token.balanceOf(_receiver), _amount);
  }

  function testFuzz_MintsNewTokensInSuccessionToDifferentAccountsWhileRemainingBelowCap(
    address _cappedMinterAdmin,
    address _receiver1,
    address _receiver2,
    uint256 _cap,
    uint256 _amount1,
    uint256 _amount2
  ) public {
    _cap = bound(_cap, 0, MAX_MINT_SUPPLY);
    vm.assume(_amount1 < MAX_MINT_SUPPLY / 2);
    vm.assume(_amount2 < MAX_MINT_SUPPLY / 2);
    vm.assume(_amount1 + _amount2 < _cap);
    vm.assume(_receiver1 != address(0) && _receiver1 != initMintReceiver);
    vm.assume(_receiver2 != address(0) && _receiver2 != initMintReceiver);
    vm.assume(_receiver1 != _receiver2);
    ZkCappedMinter cappedMinter = createCappedMinter(_cappedMinterAdmin, _cap);
    vm.startPrank(_cappedMinterAdmin);
    cappedMinter.mint(_receiver1, _amount1);
    cappedMinter.mint(_receiver2, _amount2);
    vm.stopPrank();
    assertEq(token.balanceOf(_receiver1), _amount1);
    assertEq(token.balanceOf(_receiver2), _amount2);
  }

  function testFuzz_RevertIf_MintAttemptedByNonAdmin(address _cappedMinterAdmin, uint256 _cap, address _nonAdmin)
    public
  {
    _cap = bound(_cap, 0, MAX_MINT_SUPPLY);
    vm.assume(_nonAdmin != _cappedMinterAdmin);

    ZkCappedMinter cappedMinter = createCappedMinter(_cappedMinterAdmin, _cap);
    vm.expectRevert(abi.encodeWithSelector(ZkCappedMinter.ZkCappedMinter__Unauthorized.selector, _nonAdmin));
    vm.startPrank(_nonAdmin);
    cappedMinter.mint(_nonAdmin, _cap);
  }

  function testFuzz_RevertIf_CapExceededOnMint(address _cappedMinterAdmin, address _receiver, uint256 _cap) public {
    _cap = bound(_cap, 4, MAX_MINT_SUPPLY);
    vm.assume(_receiver != address(0) && _receiver != initMintReceiver);
    ZkCappedMinter cappedMinter = createCappedMinter(_cappedMinterAdmin, _cap);
    vm.prank(_cappedMinterAdmin);
    cappedMinter.mint(_receiver, _cap);
    assertEq(token.balanceOf(_receiver), _cap);
    vm.expectRevert(
      abi.encodeWithSelector(ZkCappedMinter.ZkCappedMinter__CapExceeded.selector, _cappedMinterAdmin, _cap)
    );
    vm.prank(_cappedMinterAdmin);
    cappedMinter.mint(_receiver, _cap);
  }
}
