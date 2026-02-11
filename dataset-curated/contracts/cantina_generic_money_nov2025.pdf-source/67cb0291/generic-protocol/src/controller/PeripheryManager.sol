// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import { BaseController, ISwapper, IYieldDistributor } from "./BaseController.sol";

/**
 * @title PeripheryManager
 * @notice Abstract contract for managing periphery services like swappers and yield distributors
 * @dev Inherits from BaseController and provides role-based management of external service contracts
 */
abstract contract PeripheryManager is BaseController {
    /**
     * @notice Role identifier for addresses authorized to manage periphery services
     */
    bytes32 public constant PERIPHERY_MANAGER_ROLE = keccak256("PERIPHERY_MANAGER_ROLE");

    /**
     * @notice Emitted when the swapper contract address is updated
     */
    event SwapperUpdated(address indexed oldSwapper, address indexed newSwapper);
    /**
     * @notice Emitted when the yield distributor contract address is updated
     */
    event YieldDistributorUpdated(address indexed oldDistributor, address indexed newDistributor);

    /**
     * @notice Thrown when attempting to set the swapper to the zero address
     */
    error Periphery_ZeroSwapper();
    /**
     * @notice Thrown when attempting to set the yield distributor to the zero address
     */
    error Periphery_ZeroYieldDistributor();

    /**
     * @notice Initializes the PeripheryManager with swapper and yield distributor contracts
     * @dev Internal function called during contract initialization
     * @param swapper_ The swapper contract interface for token swapping operations
     * @param yieldDistributor_ The yield distributor contract interface for yield distribution
     */
    // forge-lint: disable-next-line(mixed-case-function)
    function __PeripheryManager_init(
        ISwapper swapper_,
        IYieldDistributor yieldDistributor_
    )
        internal
        onlyInitializing
    {
        require(address(swapper_) != address(0), Periphery_ZeroSwapper());
        require(address(yieldDistributor_) != address(0), Periphery_ZeroYieldDistributor());
        _swapper = swapper_;
        _yieldDistributor = yieldDistributor_;
    }

    /**
     * @notice Updates the swapper contract used for token swapping operations
     * @dev Only callable by addresses with PERIPHERY_MANAGER_ROLE
     * @param newSwapper The new swapper to use
     */
    function setSwapper(ISwapper newSwapper) external onlyRole(PERIPHERY_MANAGER_ROLE) {
        require(address(newSwapper) != address(0), Periphery_ZeroSwapper());
        emit SwapperUpdated(address(_swapper), address(newSwapper));
        _swapper = newSwapper;
    }

    /**
     * @notice Updates the yield distributor contract used for yield distribution
     * @dev Only callable by addresses with PERIPHERY_MANAGER_ROLE
     * @param newDistributor The new yield distributor to use
     */
    function setYieldDistributor(IYieldDistributor newDistributor) external onlyRole(PERIPHERY_MANAGER_ROLE) {
        require(address(newDistributor) != address(0), Periphery_ZeroYieldDistributor());
        emit YieldDistributorUpdated(address(_yieldDistributor), address(newDistributor));
        _yieldDistributor = newDistributor;
    }

    /**
     * @notice Returns the address of the current swapper contract
     * @return The address of the swapper contract
     */
    function swapper() public view returns (address) {
        return address(_swapper);
    }

    /**
     * @notice Returns the address of the current yield distributor contract
     * @return The address of the yield distributor contract
     */
    function yieldDistributor() public view returns (address) {
        return address(_yieldDistributor);
    }
}
