// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2024 Fireblocks <support@fireblocks.com>
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.
pragma solidity 0.8.20;

import {ERC2771Context} from "@openzeppelin/contracts-v5/metatx/ERC2771Context.sol";
import {Address} from "@openzeppelin/contracts-v5/utils/Address.sol";
import {Create2} from "@openzeppelin/contracts-v5/utils/Create2.sol";
import {Context} from "@openzeppelin/contracts-v5/utils/Context.sol";
import {Multicall} from "@openzeppelin/contracts-v5/utils/Multicall.sol";
import {LibErrors} from "../library/Errors/LibErrors.sol";

/**
 * @title GaslessFactory
 * @author Fireblocks
 * @notice A factory contract that deploys contracts and executes functions on them.
 *
 * This contract serves as a factory designed to deploy contracts and execute post deployment functions on the deployed
 * contract. This unopinionated factory is capable of deploying any arbitrary bytecode and execute corresponding
 * post-deployment functions. This factory allows the deployment of contracts using the provided bytecode and inputs.
 *
 * @dev This factory contract supports both normal and deterministic deployments of contracts. The deployment process
 * accepts the contract bytecode and inputs, allowing for flexibility in creating various types of contracts.
 *
 * If a `postConfig` is provided, it is treated as a single unit of post-deployment configuration. The entire set of
 * `postConfig` must execute successfully; otherwise, the deployment will be considered a failure, and the contract
 * will not be deployed.
 *
 * This factory contract also offers the ability to deploy contracts deterministically using the `create2` opcode when
 * desired. This allows pre-computation of contract addresses. In cases where a set of `postConfig` exists, it is
 * executed immediately after deployment, and if any part of the `postConfig` instructions fail, the entire deployment
 * is reverted to maintain atomicity.
 *
 * @custom:security-contact support@fireblocks.com
 */
contract GaslessFactory is ERC2771Context, Multicall {
	using Address for address;
	/// Events

	/**
	 * @notice This event is logged  whenever a contract is deployed through the factory.
	 * @param from The (indexed) address of the user that initiated the contract deployment request.
	 * @param deployedAddress The (indexed) address of the deployed contract.
	 * @param bytecodeHash The (indexed) hash of the bytecode of the deployed contract (without constructor inputs).
	 * @param inputs The constructor inputs that were appended to the bytecode.
	 * @param isDeterministic A boolean indicating whether the deployment was deterministic or not.
	 * @param salt The salt used for the deployment.
	 */
	event ContractDeployed(
		address indexed from,
		address indexed deployedAddress,
		bytes32 indexed bytecodeHash,
		bytes inputs,
		bool isDeterministic,
		bytes32 salt
	);

	/**
	 * @notice This event is logged whenever a function is executed on a deployed contract.
	 * @param executor The (indexed) address of the user that executed the function.
	 * @param target The (indexed) address of the contract on which the function was executed.
	 * @param data The raw calldata that was passed to the function.
	 * @param result The raw returned data from the function call.
	 */
	event FunctionExecuted(address indexed executor, address indexed target, bytes data, bytes result);

	/// Functions

	/**
	 * @notice This function acts as the constructor of the contract.
	 * @dev This function initializes the contract with the provided trusted forwarder.
	 *
	 * @param trustedForwarder_ The address of the trusted forwarder.
	 */
	constructor(address trustedForwarder_) ERC2771Context(trustedForwarder_) {}

	/**
	 * @notice This function deploys a contract using the provided bytecode and inputs.
	 * @dev Appends the inputs to the bytecode and deploys it using assembly. Executes post-deployment
	 * configuration.
	 *
	 * Calling Conditions:
	 *
	 * - The bytecode must not be empty.
	 *
	 * This function emits a {ContractDeployed} event after a successful deployment.
	 * This function might emit a {FunctionExecuted} event if a set of post-deployment configurations were provided and
	 * executed successfully.
	 *
	 * @param bytecode The bytecode of the contract to be deployed.
	 * @param inputs The constructor inputs to be appended to the bytecode.
	 * @param postConfig A set of configurations to be executed after deployment.
	 * @return deployedAddress The address of the deployed contract.
	 * @return postConfigResults A list of raw returned data corresponding to each function call in the post-deployment
	 */
	function deploy(
		bytes calldata bytecode,
		bytes calldata inputs,
		bytes[] calldata postConfig
	) external virtual returns (address deployedAddress, bytes[] memory postConfigResults) {
		if (bytecode.length == 0) {
			revert LibErrors.EmptyBytecode();
		}
		bytes memory finalCode = abi.encodePacked(bytecode, inputs);

		assembly ("memory-safe") {
			deployedAddress := create(0, add(finalCode, 0x20), mload(finalCode))

			if and(iszero(deployedAddress), not(iszero(returndatasize()))) {
				let returndata := mload(0x40)
				returndatacopy(returndata, 0, returndatasize())
				revert(returndata, returndatasize())
			}
		}

		if (deployedAddress == address(0)) {
			revert LibErrors.DeploymentFailed();
		}
		emit ContractDeployed(_msgSender(), deployedAddress, bytes32(keccak256(bytecode)), inputs, false, bytes32(""));

		postConfigResults = new bytes[](postConfig.length);
		// Execute post-deployment configuration
		for (uint256 i = 0; i < postConfig.length; i++) {
			postConfigResults[i] = _execute(deployedAddress, postConfig[i]);
		}
	}

	/**
	 * @notice This function deploys a contract using the provided bytecode and inputs deterministically.
	 * @dev Appends the inputs to the bytecode and deploys it using {Create2} library. Executes post-deployment
	 * configuration.
	 *
	 * Calling Conditions:
	 *
	 * - The bytecode must not be empty (checked internally by {Create2}.{deploy}).
	 *
	 * This function emits a {ContractDeployed} event after a successful deployment.
	 * This function might emit a {FunctionExecuted} event if a set of post-deployment configurations were provided and
	 * executed successfully.
	 *
	 * @param bytecode The bytecode of the contract to be deployed.
	 * @param inputs The constructor inputs to be appended to the bytecode.
	 * @param postConfig A set of configurations to be executed after deployment.
	 * @param salt The salt to be used for the deployment.
	 * @return deployedAddress The address of the deployed contract.
	 * @return postConfigResults A list of raw returned data corresponding to each function call in the post-deployment
	 * configuration.
	 */
	function deployDeterministic(
		bytes calldata bytecode,
		bytes calldata inputs,
		bytes[] calldata postConfig,
		bytes32 salt
	) external virtual returns (address deployedAddress, bytes[] memory postConfigResults) {
		bytes memory finalCode = abi.encodePacked(bytecode, inputs);

		deployedAddress = Create2.deploy(0, salt, finalCode);
		emit ContractDeployed(_msgSender(), deployedAddress, bytes32(keccak256(bytecode)), inputs, true, salt);

		postConfigResults = new bytes[](postConfig.length);
		// Execute post-deployment configuration
		for (uint256 i = 0; i < postConfig.length; i++) {
			postConfigResults[i] = _execute(deployedAddress, postConfig[i]);
		}
	}

	/**
	 * @notice This function computes the address of a contract that would be deployed using the provided salt.
	 * @dev Computes the address of the contract that would be deployed by making a call to
	 * {Create2}.{computeAddress}
	 *
	 * Calling Conditions:
	 *
	 * - The bytecode must not be empty.
	 *
	 * @param salt The salt to be used for the deployment.
	 * @param bytecode The bytecode of the contract to be deployed.
	 * @param inputs The constructor inputs to be appended to the bytecode (if any).
	 * @return address The computed address based on the provided parameters.
	 */
	function computeAddress(
		bytes32 salt,
		bytes calldata bytecode,
		bytes calldata inputs
	) external view virtual returns (address) {
		if (bytecode.length == 0) {
			revert LibErrors.EmptyBytecode();
		}
		bytes memory finalCode = abi.encodePacked(bytecode, inputs);
		return Create2.computeAddress(salt, keccak256(finalCode));
	}

	/**
	 * @dev This function allows the factory to execute any function on any contract.
	 *
	 * Calling Conditions:
	 *
	 * - The call data must not be empty.
	 *
	 * This function emits a {FunctionExecuted} event after a successful execution.
	 * Also note that the function does not check if the target address is zero or not as it is internal function and
	 * the address is already validated in the public function after deployment.
	 *
	 * @param target The address of the contract on which the function will be executed.
	 * @param data The function calldata that will be executed on the contract.
	 * @return result The raw returned data from the function call.
	 */
	function _execute(address target, bytes calldata data) internal virtual returns (bytes memory result) {
		if (data.length == 0) {
			revert LibErrors.EmptyCallData();
		}

		emit FunctionExecuted(_msgSender(), target, data, result);
		result = target.functionCall(data);
	}

	/**
	 * @notice This function is used to retrieve the sender of the transaction.
	 * @dev This function is an override of the logic provided by {Context} contract. Instead it uses the
	 * {ERC2771Context}.{_msgSender} function to retrieve the sender.
	 * @return The address of the sender.
	 */
	function _msgSender() internal view virtual override(Context, ERC2771Context) returns (address) {
		return super._msgSender();
	}

	/**
	 * @notice This function is used to retrieve the data of the transaction.
	 * @dev This function is an override of the logic provided by {Context} contract. Instead it uses the
	 * {ERC2771Context}.{_msgData} function to retrieve the data.
	 * @return The data of the transaction.
	 */
	function _msgData() internal view virtual override(Context, ERC2771Context) returns (bytes calldata) {
		return super._msgData();
	}

	/**
	 * @notice This function is used to retrieve the suffix length of the context.
	 * @dev This function is an override of the logic provided by {Context} contract. Instead it uses the
	 * {ERC2771Context}.{_contextSuffixLength} function to retrieve the suffix length.
	 * @return uint256 The suffix length of the context.
	 */
	function _contextSuffixLength() internal view virtual override(Context, ERC2771Context) returns (uint256) {
		return super._contextSuffixLength();
	}
}
