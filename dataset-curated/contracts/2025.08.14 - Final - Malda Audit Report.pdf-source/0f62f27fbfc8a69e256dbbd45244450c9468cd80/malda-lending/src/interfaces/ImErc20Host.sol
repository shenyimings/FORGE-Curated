// Copyright (c) 2025 Merge Layers Inc.
//
// This source code is licensed under the Business Source License 1.1
// (the "License"); you may not use this file except in compliance with the
// License. You may obtain a copy of the License at
//
//     https://github.com/malda-protocol/malda-lending/blob/main/LICENSE-BSL
//
// See the License for the specific language governing permissions and
// limitations under the License.
//
// This file contains code derived from or inspired by Compound V2,
// originally licensed under the BSD 3-Clause License. See LICENSE-COMPOUND-V2
// for original license terms and attributions.

// SPDX-License-Identifier: BSL-1.1
pragma solidity =0.8.28;

/*
 _____ _____ __    ____  _____ 
|     |  _  |  |  |    \|  _  |
| | | |     |  |__|  |  |     |
|_|_|_|__|__|_____|____/|__|__|   
*/

interface ImErc20Host {
    // ----------- EVENTS -----------
    /**
     * @notice Emitted when a user updates allowed callers
     */
    event AllowedCallerUpdated(address indexed sender, address indexed caller, bool status);

    /**
     * @notice Emitted when a chain id whitelist status is updated
     */
    event mErc20Host_ChainStatusUpdated(uint32 indexed chainId, bool status);

    /**
     * @notice Emitted when a liquidate operation is executed
     */
    event mErc20Host_LiquidateExternal(
        address indexed msgSender,
        address indexed srcSender,
        address userToLiquidate,
        address receiver,
        address indexed collateral,
        uint32 srcChainId,
        uint256 amount
    );

    /**
     * @notice Emitted when a mint operation is executed
     */
    event mErc20Host_MintExternal(
        address indexed msgSender, address indexed srcSender, address indexed receiver, uint32 chainId, uint256 amount
    );

    /**
     * @notice Emitted when a borrow operation is executed
     */
    event mErc20Host_BorrowExternal(
        address indexed msgSender, address indexed srcSender, uint32 indexed chainId, uint256 amount
    );

    /**
     * @notice Emitted when a repay operation is executed
     */
    event mErc20Host_RepayExternal(
        address indexed msgSender, address indexed srcSender, address indexed position, uint32 chainId, uint256 amount
    );

    /**
     * @notice Emitted when a withdrawal is executed
     */
    event mErc20Host_WithdrawExternal(
        address indexed msgSender, address indexed srcSender, uint32 indexed chainId, uint256 amount
    );

    /**
     * @notice Emitted when a borrow operation is triggered for an extension chain
     */
    event mErc20Host_BorrowOnExtensionChain(address indexed sender, uint32 dstChainId, uint256 amount);

    /**
     * @notice Emitted when a withdraw operation is triggered for an extension chain
     */
    event mErc20Host_WithdrawOnExtensionChain(address indexed sender, uint32 dstChainId, uint256 amount);

    /**
     * @notice Emitted when gas fees are updated for a dst chain
     */
    event mErc20Host_GasFeeUpdated(uint32 indexed dstChainId, uint256 amount);

    event mErc20Host_MintMigration(address indexed receiver, uint256 amount);
    event mErc20Host_BorrowMigration(address indexed borrower, uint256 amount);

    // ----------- ERRORS -----------
    /**
     * @notice Thrown when the chain id is not LINEA
     */
    error mErc20Host_ProofGenerationInputNotValid();

    /**
     * @notice Thrown when the dst chain id is not current chain
     */
    error mErc20Host_DstChainNotValid();

    /**
     * @notice Thrown when the chain id is not LINEA
     */
    error mErc20Host_ChainNotValid();

    /**
     * @notice Thrown when the address is not valid
     */
    error mErc20Host_AddressNotValid();

    /**
     * @notice Thrown when the amount provided is bigger than the available amount`
     */
    error mErc20Host_AmountTooBig();

    /**
     * @notice Thrown when the amount specified is invalid (e.g., zero)
     */
    error mErc20Host_AmountNotValid();

    /**
     * @notice Thrown when the journal data provided is invalid or corrupted
     */
    error mErc20Host_JournalNotValid();

    /**
     * @notice Thrown when caller is not allowed
     */
    error mErc20Host_CallerNotAllowed();

    /**
     * @notice Thrown when caller is not rebalancer
     */
    error mErc20Host_NotRebalancer();

    /**
     * @notice Thrown when length of array is not valid
     */
    error mErc20Host_LengthMismatch();

    /**
     * @notice Thrown when not enough gas fee was received
     */
    error mErc20Host_NotEnoughGasFee();

    /**
     * @notice Thrown when L1 inclusion is required
     */
    error mErc20Host_L1InclusionRequired();

    // ----------- VIEW -----------
    /**
     * @notice Returns if a caller is allowed for sender
     */
    function isCallerAllowed(address sender, address caller) external view returns (bool);

    /**
     * @notice Returns the proof data journal
     */
    function getProofData(address user, uint32 dstId) external view returns (uint256, uint256);

    // ----------- PUBLIC -----------
    /**
     * @notice Mints mTokens during migration without requiring underlying transfer
     * @param amount The amount of underlying to be accounted for
     * @param minAmount The min amount of underlying to be accounted for
     * @param receiver The address that will receive the mTokens
     */
    function mintMigration(uint256 amount, uint256 minAmount, address receiver) external;

    /**
     * @notice Borrows from market for a specific borrower and not `msg.sender`
     * @param amount The amount of underlying to be accounted for
     * @param borrower The address that borrow is executed for
     */
    function borrowMigration(uint256 amount, address borrower, address receiver) external;

    /**
     * @notice Extract amount to be used for rebalancing operation
     * @param amount The amount to rebalance
     */
    function extractForRebalancing(uint256 amount) external;

    /**
     * @notice Set caller status for `msg.sender`
     * @param caller The caller address
     * @param status The status to set for `caller`
     */
    function updateAllowedCallerStatus(address caller, bool status) external;

    /**
     * @notice Mints tokens after external verification
     * @param journalData The journal data for minting (array of encoded journals)
     * @param seal The Zk proof seal
     * @param userToLiquidate Array of positions to liquidate
     * @param liquidateAmount Array of amounts to liquidate
     * @param collateral Array of collaterals to seize
     * @param receiver The collateral receiver
     */
    function liquidateExternal(
        bytes calldata journalData,
        bytes calldata seal,
        address[] calldata userToLiquidate,
        uint256[] calldata liquidateAmount,
        address[] calldata collateral,
        address receiver
    ) external;

    /**
     * @notice Mints tokens after external verification
     * @param journalData The journal data for minting (array of encoded journals)
     * @param seal The Zk proof seal
     * @param mintAmount Array of amounts to mint
     * @param minAmountsOut Array of min amounts accepted
     * @param receiver The tokens receiver
     */
    function mintExternal(
        bytes calldata journalData,
        bytes calldata seal,
        uint256[] calldata mintAmount,
        uint256[] calldata minAmountsOut,
        address receiver
    ) external;

    /**
     * @notice Repays tokens after external verification
     * @param journalData The journal data for repayment (array of encoded journals)
     * @param seal The Zk proof seal
     * @param repayAmount Array of amounts to repay
     * @param receiver The position to repay for
     */
    function repayExternal(
        bytes calldata journalData,
        bytes calldata seal,
        uint256[] calldata repayAmount,
        address receiver
    ) external;

    /**
     * @notice Initiates a withdraw operation
     * @param amount The amount to withdraw
     * @param dstChainId The destination chain to recieve funds
     */
    function withdrawOnExtension(uint256 amount, uint32 dstChainId) external payable;

    /**
     * @notice Initiates a withdraw operation
     * @param amount The amount to withdraw
     * @param dstChainId The destination chain to recieve funds
     */
    function borrowOnExtension(uint256 amount, uint32 dstChainId) external payable;
}
