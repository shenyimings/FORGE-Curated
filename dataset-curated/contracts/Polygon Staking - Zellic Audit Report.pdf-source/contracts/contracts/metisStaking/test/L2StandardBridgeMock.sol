// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

interface Burnable {
    function burn(address _from, uint256 _amount) external;
}

/**
 * @title L2 Standard Bridge Mock
 * @dev Mocks contract for testing
 */
contract L2StandardBridgeMock {
    struct LastTransfer {
        address to;
        uint256 amount;
        uint32 l1Gas;
        bytes data;
    }

    LastTransfer public lastTransfer;

    Burnable public token;

    constructor(address _token) {
        token = Burnable(_token);
    }

    function withdrawMetisTo(
        address _to,
        uint256 _amount,
        uint32 _l1Gas,
        bytes calldata _data
    ) external payable {
        token.burn(msg.sender, _amount);
        lastTransfer = LastTransfer(_to, _amount, _l1Gas, _data);
    }
}
