// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface IOriginVault {
    struct WithdrawalQueueMetadata {
        // cumulative total of all withdrawal requests included the ones that have already been claimed
        uint128 queued;
        // cumulative total of all the requests that can be claimed including the ones that have already been claimed
        uint128 claimable;
        // total of all the requests that have been claimed
        uint128 claimed;
        // index of the next withdrawal request starting at 0
        uint128 nextWithdrawalIndex;
    }

    struct WithdrawalRequest {
        address withdrawer;
        bool claimed;
        uint40 timestamp; // timestamp of the withdrawal request
        // Amount of oTokens to redeem. eg OETH
        uint128 amount;
        // cumulative total of all withdrawal requests including this one.
        // this request can be claimed when this queued amount is less than or equal to the queue's claimable amount.
        uint128 queued;
    }

    function withdrawalRequests(uint256 requestId) external view returns (WithdrawalRequest memory);
    function withdrawalClaimDelay() external view returns (uint256);
    function withdrawalQueueMetadata() external view returns (WithdrawalQueueMetadata memory);
    function requestWithdrawal(uint256 amount) external returns (uint256 requestId, uint256 queued);
    function mint(address token, uint256 amount, uint256 minAmountOut) external;
    function claimWithdrawal(uint256 requestId) external returns (uint256 amount);
    function addWithdrawalQueueLiquidity() external;
}

IOriginVault constant OriginVault = IOriginVault(0x39254033945AA2E4809Cc2977E7087BEE48bd7Ab);
ERC20 constant oETH = ERC20(0x856c4Efb76C1D1AE02e20CEB03A2A6a08b0b8dC3);

