// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {IAny2EVMMessageReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IAny2EVMMessageReceiver.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/// @title CCIPReceiver - Base contract for CCIP applications that can receive messages.
/// @dev copied from https://github.com/smartcontractkit and modified to be upgradeable and make i_router settable
abstract contract CCIPReceiverUpgradeable is
    IAny2EVMMessageReceiver,
    IERC165,
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable
{
    address internal i_router;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function __CCIPReceiverUpgradeable_init(address _router) public onlyInitializing {
        __UUPSUpgradeable_init();
        __Ownable_init();

        if (_router == address(0)) revert InvalidRouter(address(0));
        i_router = _router;
    }

    /// @notice IERC165 supports an interfaceId
    /// @param _interfaceId The interfaceId to check
    /// @return true if the interfaceId is supported
    /// @dev Should indicate whether the contract implements IAny2EVMMessageReceiver
    /// e.g. return interfaceId == type(IAny2EVMMessageReceiver).interfaceId || interfaceId == type(IERC165).interfaceId
    /// This allows CCIP to check if ccipReceive is available before calling it.
    /// If this returns false or reverts, only tokens are transferred to the receiver.
    /// If this returns true, tokens are transferred and ccipReceive is called atomically.
    /// Additionally, if the receiver address does not have code associated with
    /// it at the time of execution (EXTCODESIZE returns 0), only tokens will be transferred.
    function supportsInterface(bytes4 _interfaceId) public pure virtual override returns (bool) {
        return
            _interfaceId == type(IAny2EVMMessageReceiver).interfaceId ||
            _interfaceId == type(IERC165).interfaceId;
    }

    /// @inheritdoc IAny2EVMMessageReceiver
    function ccipReceive(
        Client.Any2EVMMessage calldata _message
    ) external virtual override onlyRouter {
        _ccipReceive(_message);
    }

    /// @notice Override this function in your implementation.
    /// @param _message Any2EVMMessage
    function _ccipReceive(Client.Any2EVMMessage memory _message) internal virtual;

    /////////////////////////////////////////////////////////////////////
    // Plumbing
    /////////////////////////////////////////////////////////////////////

    /// @notice Return the current router
    /// @return i_router address
    function getRouter() public view returns (address) {
        return address(i_router);
    }

    /// @notice Sets the router
    /// @param _router router address
    function setRouter(address _router) external virtual onlyOwner {
        if (_router == address(0)) revert InvalidRouter(address(0));
        i_router = _router;
    }

    error InvalidRouter(address router);

    /// @dev only calls from the set router are accepted.
    modifier onlyRouter() {
        if (msg.sender != address(i_router)) revert InvalidRouter(msg.sender);
        _;
    }
}
