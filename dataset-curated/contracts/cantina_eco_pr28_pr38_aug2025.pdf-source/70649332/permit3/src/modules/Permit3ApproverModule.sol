// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {
    CallType,
    ERC7579Utils,
    ExecType,
    Mode,
    ModePayload,
    ModeSelector
} from "@openzeppelin/contracts/account/utils/draft-ERC7579Utils.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { Execution, IERC7579Execution, IERC7579Module } from "@openzeppelin/contracts/interfaces/draft-IERC7579.sol";

/**
 * @title Permit3ApproverModule
 * @notice ERC-7579 executor module that allows anyone to approve tokens to Permit3 on behalf of the account
 * @dev This module integrates with smart accounts using executeFromExecutor
 *      It allows permissionless approval of tokens to the Permit3 contract
 *
 * @dev Implementation details:
 *      - Uses ERC7579Utils for proper mode encoding (CALLTYPE_BATCH with EXECTYPE_DEFAULT)
 *      - Encodes executions using ERC7579Utils.encodeBatch()
 *      - Fully compliant with EIP-7579 executor module specification
 */
contract Permit3ApproverModule is IERC7579Module {
    /// @notice The Permit3 contract address that will receive approvals
    address public immutable PERMIT3;

    /// @notice Module type identifier for ERC-7579
    uint256 public constant MODULE_TYPE = 2; // Executor module

    /// @notice Name of the module
    string private constant NAME = "Permit3ApproverModule";

    /// @notice Version of the module
    string private constant VERSION = "1.0.0";

    /// @notice Thrown when no tokens are provided for approval
    error NoTokensProvided();

    /// @notice Thrown when a zero address is provided where it's not allowed
    error ZeroAddress(string parameterName);

    /**
     * @notice Constructor to set the Permit3 contract address
     * @param permit3 Address of the Permit3 contract
     */
    constructor(
        address permit3
    ) {
        if (permit3 == address(0)) {
            revert ZeroAddress("permit3");
        }
        PERMIT3 = permit3;
    }

    /**
     * @notice Initialize the module for an account
     * @dev No initialization data needed for this module
     * @param data Initialization data (unused)
     */
    function onInstall(
        bytes calldata data
    ) external override {
        // No initialization needed
    }

    /**
     * @notice Deinitialize the module for an account
     * @dev No cleanup needed for this module
     * @param data Deinitialization data (unused)
     */
    function onUninstall(
        bytes calldata data
    ) external override {
        // No cleanup needed
    }

    /**
     * @notice Get the type of the module
     * @return moduleTypeId The module type identifier
     */
    function isModuleType(
        uint256 moduleTypeId
    ) external pure override returns (bool) {
        return moduleTypeId == MODULE_TYPE;
    }

    /**
     * @notice Execute approval of tokens to Permit3
     * @dev Implements ERC-7579 Executor behavior by calling executeFromExecutor
     * @param account The smart account executing the approval
     * @param data Encoded array of token addresses to approve
     */
    function execute(address account, bytes calldata data) external {
        // Decode the token addresses from the data
        address[] memory tokens = abi.decode(data, (address[]));

        uint256 tokensLength = tokens.length;
        if (tokensLength == 0) {
            revert NoTokensProvided();
        }

        // Create execution array for approvals
        Execution[] memory executions = new Execution[](tokensLength);

        for (uint256 i = 0; i < tokensLength; ++i) {
            if (tokens[i] == address(0)) {
                revert ZeroAddress("token");
            }

            // Create execution for each token approval
            executions[i] = Execution({
                target: tokens[i],
                value: 0,
                callData: abi.encodeCall(IERC20.approve, (PERMIT3, type(uint256).max))
            });
        }

        // Encode executions for batch mode using ERC7579Utils
        bytes memory executionCalldata = ERC7579Utils.encodeBatch(executions);

        // Create proper mode encoding for batch execution that reverts on failure
        Mode mode = ERC7579Utils.encodeMode(
            ERC7579Utils.CALLTYPE_BATCH,
            ERC7579Utils.EXECTYPE_DEFAULT,
            ModeSelector.wrap(bytes4(0)),
            ModePayload.wrap(bytes22(0))
        );

        // Call executeFromExecutor on the smart account
        IERC7579Execution(account).executeFromExecutor(Mode.unwrap(mode), executionCalldata);
    }

    /**
     * @notice Get the execution data for approving tokens
     * @dev Helper function to encode the data for the execute function
     * @param tokens Array of token addresses to approve
     * @return data Encoded data for the execute function
     */
    function getExecutionData(
        address[] calldata tokens
    ) external pure returns (bytes memory data) {
        return abi.encode(tokens);
    }

    /**
     * @notice Get the name of the module
     * @return The module name
     */
    function name() external pure returns (string memory) {
        return NAME;
    }

    /**
     * @notice Get the version of the module
     * @return The module version
     */
    function version() external pure returns (string memory) {
        return VERSION;
    }

    /**
     * @notice Check if a specific module type is supported
     * @param interfaceId The interface identifier to check
     * @return True if the interface is supported
     */
    function supportsInterface(
        bytes4 interfaceId
    ) external pure returns (bool) {
        return interfaceId == type(IERC7579Module).interfaceId;
    }
}
