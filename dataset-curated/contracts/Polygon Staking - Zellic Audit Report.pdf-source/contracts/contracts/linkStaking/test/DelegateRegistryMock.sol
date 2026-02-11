// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

import "../interfaces/IDelegateRegistry.sol";

/**
 * @title Delegate Registry Mock
 * @dev Mocks contract for testing
 */
contract DelegateRegistryMock {
    mapping(address => IDelegateRegistry.Delegation[]) public delegationsByAccount;

    function delegateAll(
        address _to,
        bytes32 _rights,
        bool
    ) external payable returns (bytes32 delegationHash) {
        delegationsByAccount[msg.sender].push(
            IDelegateRegistry.Delegation(
                IDelegateRegistry.DelegationType.ALL,
                _to,
                msg.sender,
                _rights,
                msg.sender,
                9,
                100
            )
        );
    }

    function getOutgoingDelegations(
        address _from
    ) external view returns (IDelegateRegistry.Delegation[] memory delegations) {
        return delegationsByAccount[_from];
    }
}
