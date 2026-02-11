// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title TadleConnectorsInterface
 * @notice Interface for managing and validating connector contracts
 * @dev Provides functionality to verify connector existence and retrieve addresses
 */
interface TadleConnectorsInterface {
    /// @notice Validate connector names and return their addresses
    /// @param connectorNames Array of connector names to validate
    /// @return isValid True if all connectors exist, false otherwise
    /// @return addresses Array of connector contract addresses
    function isConnectors(
        string[] calldata connectorNames
    ) external view returns (bool isValid, address[] memory addresses);
}

/**
 * @title IAuth
 * @notice Interface for authentication and access control
 * @dev Provides sandbox admin verification functionality
 */
interface IAuth {
    /// @notice Check if an address is a sandbox administrator for a specific account
    /// @param sandboxAccount The sandbox account to check against
    /// @param admin The address to verify admin status for
    /// @return True if the address is a sandbox admin, false otherwise
    function isSandboxAdmin(
        address sandboxAccount,
        address admin
    ) external view returns (bool);
}

/**
 * @title Constants
 * @notice Base contract holding core system addresses
 * @dev Provides immutable references to auth and connectors contracts
 * @custom:security Ensures core addresses cannot be modified after deployment
 */
contract Constants {
    /// @dev Auth contract address for access control
    /// @notice Immutable reference to the authentication contract
    address internal immutable auth;

    /// @dev Connectors registry address
    /// @notice Immutable reference to the connectors registry contract
    address public immutable connectors;

    /**
     * @dev Initialize contract with core system addresses
     * @param _auth Address of the authentication contract
     * @param _connectors Address of the connectors registry contract
     * @custom:validation Ensures both addresses are non-zero
     */
    constructor(address _auth, address _connectors) {
        require(_auth != address(0), "Constants: auth address cannot be zero");
        require(
            _connectors != address(0),
            "Constants: connectors address cannot be zero"
        );
        connectors = _connectors;
        auth = _auth;
    }
}

/**
 * @title TadleImplementationV1
 * @author Tadle Team
 * @notice Smart contract wallet implementation for Tadle platform
 * @dev Enables modular functionality through connectors with delegatecall execution
 * @custom:security Implements access control and safe delegatecall patterns
 * @custom:modularity Supports dynamic connector-based functionality
 */
contract TadleImplementationV1 is Constants {
    /// @dev Emitted when connector functions are executed
    /// @param account The account that executed the cast
    /// @param targetsNames Array of connector names that were called
    /// @param targets Array of connector addresses that were called
    /// @param eventNames Array of event names returned by connectors
    /// @param eventParams Array of event parameters returned by connectors
    event LogCast(
        address indexed account,
        string[] targetsNames,
        address[] targets,
        string[] eventNames,
        bytes[] eventParams
    );

    /**
     * @dev Initialize the implementation with core system addresses
     * @param _auth Address of the authentication contract
     * @param _connectors Address of the connectors registry contract
     * @notice Sets up the wallet implementation with required system contracts
     */
    constructor(
        address _auth,
        address _connectors
    ) Constants(_auth, _connectors) {}

    /**
     * @dev Decode event data from connector response
     * @param response Raw bytes response from connector
     * @return _eventCode Event identifier string
     * @return _eventParams Encoded event parameters
     * @notice Safely decodes connector response data
     * @custom:decoding Handles empty responses gracefully
     */
    function decodeEvent(
        bytes memory response
    )
        internal
        pure
        returns (string memory _eventCode, bytes memory _eventParams)
    {
        if (response.length > 0) {
            (_eventCode, _eventParams) = abi.decode(response, (string, bytes));
        }
    }

    /**
     * @dev Delegate call to connector with safety checks
     * @param _target Connector address to call
     * @param _data Encoded function call data
     * @return response Raw response from connector
     * @notice Executes delegatecall to connector and handles return data
     * @custom:security Validates target address and handles call failures
     * @custom:gas-optimization Uses assembly for efficient delegatecall execution
     */
    function spell(
        address _target,
        bytes memory _data
    ) internal returns (bytes memory response) {
        require(
            _target != address(0),
            "TadleImplementationV1: target address cannot be zero"
        );
        assembly {
            let succeeded := delegatecall(
                gas(),
                _target,
                add(_data, 0x20),
                mload(_data),
                0,
                0
            )
            let size := returndatasize()

            response := mload(0x40)
            mstore(
                0x40,
                add(response, and(add(add(size, 0x20), 0x1f), not(0x1f)))
            )
            mstore(response, size)
            returndatacopy(add(response, 0x20), 0, size)

            switch iszero(succeeded)
            case 1 {
                returndatacopy(0x00, 0x00, size)
                revert(0x00, size)
            }
        }
    }

    /**
     * @dev Execute multiple connector calls in a single transaction
     * @param _targetNames Array of connector names to call
     * @param _datas Array of encoded function calls
     * @notice Batch execution of connector functions with access control
     * @custom:access-control Only sandbox admins can execute casts
     * @custom:validation Validates input arrays and prevents ETH transfers
     * @custom:batch-execution Supports multiple connector calls in one transaction
     */
    function cast(
        string[] calldata _targetNames,
        bytes[] calldata _datas
    ) external payable {
        require(
            IAuth(auth).isSandboxAdmin(address(this), msg.sender),
            "TadleImplementationV1: caller must be sandbox admin"
        );
        require(
            msg.value == 0,
            "TadleImplementationV1: ETH transfers not allowed"
        );
        uint256 _length = _targetNames.length;
        require(
            _length != 0,
            "TadleImplementationV1: connector array cannot be empty"
        );
        require(
            _length == _datas.length,
            "TadleImplementationV1: array length mismatch"
        );

        string[] memory eventNames = new string[](_length);
        bytes[] memory eventParams = new bytes[](_length);

        (bool isOk, address[] memory _targets) = TadleConnectorsInterface(
            connectors
        ).isConnectors(_targetNames);

        require(
            isOk,
            "TadleImplementationV1: invalid connector names provided"
        );

        for (uint256 i = 0; i < _length; i++) {
            bytes memory response = spell(_targets[i], _datas[i]);
            (eventNames[i], eventParams[i]) = decodeEvent(response);
        }

        emit LogCast(
            address(this),
            _targetNames,
            _targets,
            eventNames,
            eventParams
        );
    }

    /**
     * @dev Fallback function to receive ETH transfers
     * @notice Enables the contract to accept plain ETH transfers
     * @custom:payable Accepts ETH without function call data
     */
    receive() external payable {}
}
