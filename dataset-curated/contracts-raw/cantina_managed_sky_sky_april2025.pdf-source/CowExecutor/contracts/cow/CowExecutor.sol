// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@1inch/solidity-utils/contracts/libraries/RevertReasonParser.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../libs/TokenLibrary.sol";
import "../Errors.sol";
import "./CowKyberExecutor.sol";
import "./CowMaverickExecutor.sol";
import "./CowMaverickV2Executor.sol";
import "./CowPancakeV3Executor.sol";
import "./CowUniswapV3Executor.sol";
import "../libs/SafeERC20Ext.sol";

contract CowExecutor is
    CowKyberExecutor,
    CowMaverickExecutor,
    CowMaverickV2Executor,
    CowPancakeV3Executor,
    CowUniswapV3Executor
{
    using TokenLibrary for IERC20;
    using SafeERC20Ext for IERC20;
    using SafeERC20 for IERC20;


    error Unauthorized();
    error ReceivedLessThanMinReturn(uint256, uint256);

    string public constant DESCRIPTION = "CowExecutor";

    address private immutable cowSettlementContract;

    uint256 private constant MIN_ALLOWANCE_REQUIRED = 2**250;

    constructor(address _cowSettlementContract) {
        cowSettlementContract = _cowSettlementContract;
    }

    modifier onlyCowSettlementContract() {
        if (msg.sender != cowSettlementContract) {
            revert Unauthorized();
        }
        _;
    }

    function guardedUnlimitedApprovedInteractionCall(uint256 minReturn, IERC20 sourceToken, IERC20 targetToken, address approveTarget, bool shouldTransfer, address target, bytes memory data) external payable onlyCowSettlementContract() {
        {
            bool shouldRevert;
            assembly {
                let sig := and(mload(add(data, 0x20)), 0xffffffff00000000000000000000000000000000000000000000000000000000)
                shouldRevert := eq(sig, 0x23b872dd00000000000000000000000000000000000000000000000000000000)
            }
            if (shouldRevert) {
                revert TransferFromNotAllowed();
            }
        }

        uint256 currentAllowance = sourceToken.allowance(address(this), approveTarget);
        if (currentAllowance < MIN_ALLOWANCE_REQUIRED) {
            if (currentAllowance > 0) {
                sourceToken.setAllowance(approveTarget, 0);
            }
            sourceToken.setAllowance(approveTarget, type(uint256).max);
        }

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory result) = target.call{value: msg.value}(data);
        if (!success) {
            string memory reason = RevertReasonParser.parse(
                result,
                "CowEx: "
            );
            revert(reason);
        }

        // decode response as uint256
        uint256 received;
        assembly {
            received := mload(add(result, 0x20))
        }

        if (received < minReturn) {
            revert ReceivedLessThanMinReturn(received, minReturn);
        }
        if (shouldTransfer) {
            targetToken.safeTransfer(msg.sender, received);
        }
    }

    function guardedUnlimitedApprovedInteractionValidatedBalanceCall(uint256 minReturn, IERC20 sourceToken, IERC20 targetToken, address approveTarget, address target, address recipient, bytes memory data) external payable onlyCowSettlementContract() {
        {
            bool shouldRevert;
            assembly {
                let sig := and(mload(add(data, 0x20)), 0xffffffff00000000000000000000000000000000000000000000000000000000)
                shouldRevert := eq(sig, 0x23b872dd00000000000000000000000000000000000000000000000000000000)
            }
            if (shouldRevert) {
                revert TransferFromNotAllowed();
            }
        }

        uint256 currentAllowance = sourceToken.allowance(address(this), approveTarget);
        if (currentAllowance < MIN_ALLOWANCE_REQUIRED) {
            if (currentAllowance > 0) {
                sourceToken.setAllowance(approveTarget, 0);
            }
            sourceToken.setAllowance(approveTarget, type(uint256).max);
        }

        uint256 targetBalanceBefore = targetToken.balanceOf(address(recipient));

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory result) = target.call{value: msg.value}(data);
        if (!success) {
            string memory reason = RevertReasonParser.parse(
                result,
                "CowEx: "
            );
            revert(reason);
        }

        uint256 received = targetToken.balanceOf(address(recipient)) - targetBalanceBefore;

        if (received < minReturn) {
            revert ReceivedLessThanMinReturn(received, minReturn);
        }

        if (recipient == address(this)) {
            targetToken.safeTransfer(msg.sender, received);
        }
    }

    function guardedReturnAmountCall(uint256 minReturn, address target, bytes memory data) external payable onlyCowSettlementContract() {
        {
            bool shouldRevert;
            assembly {
                let sig := and(mload(add(data, 0x20)), 0xffffffff00000000000000000000000000000000000000000000000000000000)
                shouldRevert := eq(sig, 0x23b872dd00000000000000000000000000000000000000000000000000000000)
            }
            if (shouldRevert) {
                revert TransferFromNotAllowed();
            }
        }

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory result) = target.call{value: msg.value}(data);
        if (!success) {
            string memory reason = RevertReasonParser.parse(
                result,
                "CowEx: "
            );
            revert(reason);
        }

        // decode response as uint256
        uint256 received;
        assembly {
            received := mload(add(result, 0x20))
        }

        if (received < minReturn) {
            revert ReceivedLessThanMinReturn(received, minReturn);
        }
    }

    function guardedUncheckedCall(address target, bytes memory data) external payable onlyCowSettlementContract() {
        {
            bool shouldRevert;
            assembly {
                let sig := and(mload(add(data, 0x20)), 0xffffffff00000000000000000000000000000000000000000000000000000000)
                shouldRevert := eq(sig, 0x23b872dd00000000000000000000000000000000000000000000000000000000)
            }
            if (shouldRevert) {
                revert TransferFromNotAllowed();
            }
        }

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory result) = target.call{value: msg.value}(data);
        if (!success) {
            string memory reason = RevertReasonParser.parse(
                result,
                "CowEx: "
            );
            revert(reason);
        }
    }
}
