// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {IERC165} from "./interfaces/IERC165.sol";
import {Enum} from "./libraries/Enum.sol";
import {IModuleGuard} from "./interfaces/IModuleGuard.sol";

import {ISafe} from "./Safe/interfaces/ISafe.sol";
import {Singleton} from "./Safe/common/Singleton.sol";

contract ModuleGuard is Singleton, IModuleGuard {
    // solhint-disable-next-line payable-fallback
    fallback() external {
        // We don't revert on fallback to avoid issues in case of a Safe upgrade
        // E.g. The expected check method might change and then the Safe would be locked.
    }

    //////////////////////
    // State Variables  //
    //////////////////////

    ISafe private safe;

    // A whitelist of contract addresses and function signatures
    // with which the SAMM module can interact on behalf of the Safe multisig
    mapping(address module => mapping(address to => mapping(bytes4 selector => bool))) public isTxAllowed;

    // A limit on the amount of ETH that can be transferred
    // to a single address in the whitelist.
    mapping(address module => mapping(address to => uint256)) public allowance;

    //////////////////////////////
    // Functions - Constructor  //
    //////////////////////////////
    constructor() {
        // To lock the singleton contract so no one can call setup.
        safe = ISafe(address(1));
    }

    ///////////////////////////
    // Functions - External  //
    ///////////////////////////

    /**
     * @notice Initializes the contract.
     * @dev This method can only be called once.
     * If a proxy was created without setting up, anyone can call setup and claim the proxy.
     * Revert in case:
     *  - The contract has already been initialized.
     *  - One of the passed parameters is 0.
     * @param _safe The address of the Safe.
     */
    function setup(address _safe) external {
        if (safe != ISafe(address(0))) {
            revert ModuleGuard__alreadyInitialized();
        }

        if (_safe == address(0)) {
            revert ModuleGuard__safeIsZero();
        }

        safe = ISafe(_safe);
        emit Setup(msg.sender, _safe);
    }

    /**
     * @notice Updates list of allowed transactions.
     * @param module The address of module, for which allowed transactions list is changing.
     * @param to The destination address of new transaction.
     * @param selector The selector of new transaction.
     * @param isAllowed Boolean: 1 if the transaction is allowed, 0 if the transaction is not allowed anymore.
     */
    function setTxAllowed(address module, address to, bytes4 selector, bool isAllowed) external {
        address _safe = address(safe);
        if (msg.sender != _safe) {
            revert ModuleGuard__notSafe();
        }
        if (module == _safe || module == address(0)) {
            revert ModuleGuard__moduleIsWrong();
        }
        if (to == _safe || to == address(0)) {
            revert ModuleGuard__toIsWrong();
        }
        if (isAllowed == isTxAllowed[module][to][selector]) {
            revert ModuleGuard__noChanges();
        }
        isTxAllowed[module][to][selector] = isAllowed;
        emit TxAllowanceChanged(module, to, selector, isAllowed);
    }

    /**
     * @notice Updates allowance mapping.
     * @param module The address of module, for which allowance mapping is changing.
     * @param to The destination address for which allowance is changing.
     * @param amount The new allowance value.
     */
    function setAllowance(address module, address to, uint256 amount) external {
        address _safe = address(safe);
        if (msg.sender != _safe) {
            revert ModuleGuard__notSafe();
        }
        if (module == _safe || module == address(0)) {
            revert ModuleGuard__moduleIsWrong();
        }
        if (to == _safe || to == address(0)) {
            revert ModuleGuard__toIsWrong();
        }
        if (amount == allowance[module][to]) {
            revert ModuleGuard__noChanges();
        }
        allowance[module][to] = amount;
        emit AllowanceChanged(module, to, amount);
    }

    /**
     * @notice Called by the Safe contract before a transaction is executed via a module.
     * @param to Destination address of Safe transaction.
     * @param value Ether value of Safe transaction.
     * @param data Data payload of Safe transaction.
     * @param operation Operation type of Safe transaction.
     * @param module Account executing the transaction.
     * @return moduleTxHash Hash of the module transaction.
     */
    function checkModuleTransaction(
        address to,
        uint256 value,
        bytes memory data,
        Enum.Operation operation,
        address module
    ) external view override returns (bytes32 moduleTxHash) {
        bytes4 selector = _getABISig(data);
        if (!isTxAllowed[module][to][selector]) {
            revert ModuleGuard__txIsNotAllowed();
        }
        if (allowance[module][to] < value) {
            revert ModuleGuard__allowanceIsNotEnough();
        }

        moduleTxHash = keccak256(abi.encodePacked(to, value, data, operation, module));
    }

    /**
     * @notice Called by the Safe contract after a module transaction is executed.
     * @dev No-op.
     */
    function checkAfterModuleExecution(bytes32 txHash, bool success) external override {}

    //////////////////////////////
    // Functions  -   View      //
    //////////////////////////////

    /// @notice Retrieves the address of the Safe associated with this module.
    /// @return _safe The address of the associated Safe.
    function getSafe() external view returns (address _safe) {
        return address(safe);
    }

    function supportsInterface(bytes4 interfaceId) external view virtual override returns (bool) {
        return interfaceId == type(IModuleGuard).interfaceId // 0x58401ed8
            || interfaceId == type(IERC165).interfaceId; // 0x01ffc9a7
    }

    //////////////////////////////
    //   Functions - Private    //
    //////////////////////////////
    function _getABISig(bytes memory data) private pure returns (bytes4 sig) {
        assembly {
            sig := mload(add(data, 0x20))
        }
    }
}
