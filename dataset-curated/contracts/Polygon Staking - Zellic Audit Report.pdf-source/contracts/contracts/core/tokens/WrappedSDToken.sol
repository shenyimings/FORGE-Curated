// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

import "./base/ERC677.sol";
import "../interfaces/IStakingRewardsPool.sol";

/**
 * @title Wrapped Staking Derivative Token
 * @notice Wraps rebasing derivative tokens with a normal ERC20 token
 */
contract WrappedSDToken is ERC677 {
    IStakingRewardsPool public immutable sdToken;

    constructor(
        address _stakingRewardsPool,
        string memory _name,
        string memory _symbol
    ) ERC677(_name, _symbol, 0) {
        sdToken = IStakingRewardsPool(_stakingRewardsPool);
    }

    /**
     * @notice ERC677 implementation that proxies wrapping
     * @param _sender of the token transfer
     * @param _value of the token transfer
     **/
    function onTokenTransfer(address _sender, uint256 _value, bytes calldata) external {
        require(msg.sender == address(sdToken), "Sender must be staking derivative token");
        _wrap(_sender, _value);
    }

    /**
     * @notice wraps tokens
     * @param _amount amount of unwrapped tokens to wrap
     */
    function wrap(uint256 _amount) external {
        sdToken.transferFrom(msg.sender, address(this), _amount);
        _wrap(msg.sender, _amount);
    }

    /**
     * @notice unwraps tokens
     * @param _amount amount of wrapped tokens to unwrap
     */
    function unwrap(uint256 _amount) external {
        require(_amount > 0, "Amount must be > 0");
        uint256 unwrappedAmount = sdToken.getStakeByShares(_amount);
        _burn(msg.sender, _amount);
        sdToken.transfer(msg.sender, unwrappedAmount);
    }

    /**
     * @notice Returns amount of wrapped tokens for an amount of unwrapped tokens
     * @param _amount amount of unwrapped tokens
     * @return amount of wrapped tokens
     */
    function getWrappedByUnderlying(uint256 _amount) external view returns (uint256) {
        return sdToken.getSharesByStake(_amount);
    }

    /**
     * @notice Returns amount of unwrapped tokens for an amount of wrapped tokens
     * @param _amount amount of wrapped tokens
     * @return amount of unwrapped tokens
     */
    function getUnderlyingByWrapped(uint256 _amount) external view returns (uint256) {
        return sdToken.getStakeByShares(_amount);
    }

    /**
     * @notice wraps tokens
     * @param _account account to wrap tokens for
     * @param _amount amount of unwrapped tokens to wrap
     */
    function _wrap(address _account, uint256 _amount) private {
        require(_amount > 0, "Amount must be > 0");
        uint256 wrappedAmount = sdToken.getSharesByStake(_amount);
        _mint(_account, wrappedAmount);
    }
}
