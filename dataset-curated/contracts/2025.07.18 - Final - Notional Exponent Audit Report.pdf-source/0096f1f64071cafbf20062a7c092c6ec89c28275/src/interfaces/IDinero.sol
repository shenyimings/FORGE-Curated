// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC1155} from "@openzeppelin/contracts/interfaces/IERC1155.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

interface IPirexETH {
    error StatusNotDissolvedOrSlashed();
    error NotEnoughETH();

    enum ValidatorStatus {
        // The validator is not staking and has no defined status.
        None,
        // The validator is actively participating in the staking process.
        // It could be in one of the following states: pending_initialized, pending_queued, or active_ongoing.
        Staking,
        // The validator has proceed with the withdrawal process.
        // It represents a meta state for active_exiting, exited_unslashed, and the withdrawal process being possible.
        Withdrawable,
        // The validator's status indicating that ETH is released to the pirexEthValidators
        // It represents the withdrawal_done status.
        Dissolved,
        // The validator's status indicating that it has been slashed due to misbehavior.
        // It serves as a meta state encompassing active_slashed, exited_slashed,
        // and the possibility of starting the withdrawal process (withdrawal_possible) or already completed (withdrawal_done)
        // with the release of ETH, subject to a penalty for the misbehavior.
        Slashed
    }

    function batchId() external view returns (uint256);
    function initiateRedemption(uint256 assets, address receiver, bool shouldTriggerValidatorExit) external;
    function deposit(address receiver, bool shouldCompound) external payable;
    function instantRedeemWithPxEth(uint256 _assets, address _receiver) external;
    function redeemWithUpxEth(uint256 _tokenId, uint256 _assets, address _receiver) external;
    function outstandingRedemptions() external view returns (uint256);

    function dissolveValidator(bytes calldata validator) external payable;
    function rewardRecipient() external view returns (address);
    function batchIdToValidator(uint256 batchId) external view returns (bytes memory);
    function status(bytes calldata validator) external view returns (ValidatorStatus);
}

IPirexETH constant PirexETH = IPirexETH(0xD664b74274DfEB538d9baC494F3a4760828B02b0);
ERC20 constant pxETH = ERC20(0x04C154b66CB340F3Ae24111CC767e0184Ed00Cc6);
IERC4626 constant apxETH = IERC4626(0x9Ba021B0a9b958B5E75cE9f6dff97C7eE52cb3E6);
IERC1155 constant upxETH = IERC1155(0x5BF2419a33f82F4C1f075B4006d7fC4104C43868);