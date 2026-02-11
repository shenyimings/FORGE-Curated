// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.30;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IStrategyCallForwarder} from "src/interfaces/IStrategyCallForwarder.sol";

contract StrategyCallForwarder is
    Initializable,
    ReentrancyGuardUpgradeable,
    OwnableUpgradeable,
    IStrategyCallForwarder
{
    using SafeERC20 for IERC20;

    constructor() {
        _disableInitializers();
    }

    function initialize(address _owner) external initializer {
        __ReentrancyGuard_init();
        __Ownable_init(_owner);
    }

    /// @notice Function for receiving native assets
    receive() external payable {}

    /**
     * @notice Executes a call on the target contract
     * @dev Only callable by owner. To convert to the expected return value, use abi.decode.
     * @param _target The address of the target contract
     * @param _data The call data
     * @return data The raw returned data.
     */
    function doCall(address _target, bytes calldata _data) external onlyOwner returns (bytes memory data) {
        data = Address.functionCall(_target, _data);
    }

    /**
     * @notice Executes a call on the target contract, but also transferring value wei to the target.
     * @dev Only callable by owner. To convert to the expected return value, use abi.decode.
     * @param _target The address of the target contract
     * @param _data The call data
     * @param _value The value to send with the call
     * @return Returns the raw returned data.
     */
    function doCallWithValue(address _target, bytes calldata _data, uint256 _value)
        external
        onlyOwner
        returns (bytes memory)
    {
        return Address.functionCallWithValue(_target, _data, _value);
    }

    /**
     * @notice sends `_amount` wei to `_recipient`
     * @param _recipient The address to send the value to
     * @param _amount The amount of value to send
     */
    function sendValue(address payable _recipient, uint256 _amount) external onlyOwner nonReentrant {
        Address.sendValue(_recipient, _amount);
    }

    /**
     * @notice Executes a safe transfer of ERC20 tokens
     * @dev Only callable by owner.
     * @param _token The address of the ERC20 token
     * @param _recipient The address to send the tokens to
     * @param _amount The amount of tokens to transfer
     */
    function safeTransferERC20(address _token, address _recipient, uint256 _amount) external onlyOwner {
        IERC20(_token).safeTransfer(_recipient, _amount);
    }
}
