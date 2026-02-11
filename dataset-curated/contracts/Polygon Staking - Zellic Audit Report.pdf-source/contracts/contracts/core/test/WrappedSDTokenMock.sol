// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

import "../tokens/base/ERC677.sol";

/**
 * @title Wrapped Staking Derivative Token
 * @notice Mocks contract for testing
 */
contract WrappedSDTokenMock is ERC677 {
    IERC20 public immutable sdToken;
    uint256 multiplier;

    constructor(address _sdToken) ERC677("test", "test", 0) {
        sdToken = IERC20(_sdToken);
        multiplier = 2;
    }

    /**
     * @notice ERC677 implementation that proxies wrapping
     * @param _sender of the token transfer
     * @param _value of the token transfer
     **/
    function onTokenTransfer(address _sender, uint256 _value, bytes calldata) external {
        require(msg.sender == address(sdToken), "Sender must be staking derivative token");
        uint256 wrappedAmount = getWrappedByUnderlying(_value);
        _mint(_sender, wrappedAmount);
    }

    /**
     * @notice unwraps tokens
     * @param _amount amount of wrapped tokens to unwrap
     */
    function unwrap(uint256 _amount) external {
        require(_amount > 0, "Amount must be > 0");
        uint256 unwrappedAmount = getUnderlyingByWrapped(_amount);
        _burn(msg.sender, _amount);
        sdToken.transfer(msg.sender, unwrappedAmount);
    }

    /**
     * @notice Returns amount of wrapped tokens for an amount of unwrapped tokens
     * @param _amount amount of unwrapped tokens
     * @return amount of wrapped tokens
     */
    function getWrappedByUnderlying(uint256 _amount) public view returns (uint256) {
        return _amount / multiplier;
    }

    /**
     * @notice Returns amount of unwrapped tokens for an amount of wrapped tokens
     * @param _amount amount of wrapped tokens
     * @return amount of unwrapped tokens
     */
    function getUnderlyingByWrapped(uint256 _amount) public view returns (uint256) {
        return _amount * multiplier;
    }

    function setMultiplier(uint256 _multiplier) external {
        multiplier = _multiplier;
    }
}
