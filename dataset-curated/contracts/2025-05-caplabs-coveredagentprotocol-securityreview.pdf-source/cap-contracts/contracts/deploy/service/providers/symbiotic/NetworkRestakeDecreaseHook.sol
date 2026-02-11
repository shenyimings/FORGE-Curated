// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { INetworkRestakeDecreaseHook } from
    "@symbioticfi/hooks/src/interfaces/networkRestakeDelegator/INetworkRestakeDecreaseHook.sol";

import { IEntity } from "@symbioticfi/core/src/interfaces/common/IEntity.sol";
import { IDelegatorHook } from "@symbioticfi/core/src/interfaces/delegator/IDelegatorHook.sol";
import { INetworkRestakeDelegator } from "@symbioticfi/core/src/interfaces/delegator/INetworkRestakeDelegator.sol";
import { IBaseSlasher } from "@symbioticfi/core/src/interfaces/slasher/IBaseSlasher.sol";
import { ISlasher } from "@symbioticfi/core/src/interfaces/slasher/ISlasher.sol";
import { IVetoSlasher } from "@symbioticfi/core/src/interfaces/slasher/IVetoSlasher.sol";

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

contract NetworkRestakeDecreaseHook is INetworkRestakeDecreaseHook {
    using Math for uint256;

    /**
     * @inheritdoc IDelegatorHook
     */
    function onSlash(
        bytes32 subnetwork,
        address operator,
        uint256 slashedAmount,
        uint48 captureTimestamp,
        bytes calldata data
    ) external {
        if (IEntity(msg.sender).TYPE() != 0) {
            revert NotNetworkRestakeDelegator();
        }

        if (slashedAmount == 0) {
            return;
        }

        IBaseSlasher.GeneralDelegatorData memory generalData = abi.decode(data, (IBaseSlasher.GeneralDelegatorData));
        uint256 stakeAt;
        if (generalData.slasherType == 0) {
            ISlasher.DelegatorData memory delegatorData = abi.decode(generalData.data, (ISlasher.DelegatorData));
            stakeAt = delegatorData.stakeAt;
        } else if (generalData.slasherType == 1) {
            IVetoSlasher.DelegatorData memory delegatorData = abi.decode(generalData.data, (IVetoSlasher.DelegatorData));
            stakeAt = delegatorData.stakeAt;
        } else {
            stakeAt = INetworkRestakeDelegator(msg.sender).stakeAt(subnetwork, operator, captureTimestamp, new bytes(0));
        }

        uint256 networkLimit = INetworkRestakeDelegator(msg.sender).networkLimit(subnetwork);
        if (networkLimit != 0) {
            INetworkRestakeDelegator(msg.sender).setNetworkLimit(
                subnetwork, networkLimit - Math.min(slashedAmount, networkLimit)
            );
        }

        uint256 operatorNetworkSharesAt = INetworkRestakeDelegator(msg.sender).operatorNetworkSharesAt(
            subnetwork, operator, captureTimestamp, new bytes(0)
        );
        uint256 operatorNetworkShares = INetworkRestakeDelegator(msg.sender).operatorNetworkShares(subnetwork, operator);
        if (operatorNetworkShares != 0) {
            operatorNetworkShares -= Math.min(
                slashedAmount.mulDiv(operatorNetworkSharesAt, stakeAt, Math.Rounding.Ceil), operatorNetworkShares
            );
            INetworkRestakeDelegator(msg.sender).setOperatorNetworkShares(subnetwork, operator, operatorNetworkShares);
        }
    }
}
