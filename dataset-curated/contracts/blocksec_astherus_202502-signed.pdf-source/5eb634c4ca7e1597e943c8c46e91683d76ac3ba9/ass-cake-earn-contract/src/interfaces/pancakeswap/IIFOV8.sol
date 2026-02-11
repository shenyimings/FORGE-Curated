// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/** @title IFO V8 interface
 * @notice IFO Pool V8 interface
 */
interface IIFOV8 {
  struct VestingSchedule {
    bool isVestingInitialized;
    address beneficiary;
    uint8 pid;
    uint256 amountTotal;
    uint256 released;
  }

  function addresses(uint256 index) external view returns (address);

  function endTimestamp() external view returns (uint256);

  function startTimestamp() external view returns (uint256);

  function depositPool(uint256 _amount, uint8 _pid) external;

  function harvestPool(uint8 _pid) external;

  function viewPoolTaxRateOverflow(uint8 _pid) external view returns (uint256);

  function viewUserAllocationPools(
    address _user,
    uint8[] calldata _pids
  ) external view returns (uint256[] memory);

  function viewUserInfo(
    address _user,
    uint8[] calldata _pids
  ) external view returns (uint256[] memory, bool[] memory);

  function viewUserOfferingAndRefundingAmountsForPools(
    address _user,
    uint8[] calldata _pids
  ) external view returns (uint256[3][] memory);

  function release(bytes32 _vestingScheduleId) external;

  function viewPoolVestingInformation(
    uint256 _pid
  ) external view returns (uint256, uint256, uint256, uint256);

  function computeVestingScheduleIdForAddressAndPid(
    address _holder,
    uint8 _pid
  ) external view returns (bytes32);

  function computeReleasableAmount(bytes32 _vestingScheduleId) external view returns (uint256);

  function viewPoolInformation(
    uint8 _pid
  )
  external
  view
  returns (
    uint256 raisingAmountPool,
    uint256 offeringAmountPool,
    uint256 limitPerUserInLP,
    bool hasTax,
    uint256 totalAmountPool,
    uint256 sumTaxesOverflow,
    bool isSpecialSale
  );

  function getVestingSchedule(bytes32 _vestingScheduleId) external view returns (VestingSchedule memory);

}
