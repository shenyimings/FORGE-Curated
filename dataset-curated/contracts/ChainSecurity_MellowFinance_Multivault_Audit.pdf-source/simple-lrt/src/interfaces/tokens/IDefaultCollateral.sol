// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IDefaultCollateral is IERC20 {
    /**
     * @notice Emitted when debt is issued.
     * @param issuer address of the debt's issuer
     * @param recipient address that should receive the underlying asset
     * @param debtIssued amount of the debt issued
     */
    event IssueDebt(address indexed issuer, address indexed recipient, uint256 debtIssued);

    /**
     * @notice Emitted when debt is repaid.
     * @param issuer address of the debt's issuer
     * @param recipient address that received the underlying asset
     * @param debtRepaid amount of the debt repaid
     */
    event RepayDebt(address indexed issuer, address indexed recipient, uint256 debtRepaid);

    /**
     * @notice Get the collateral's underlying asset.
     * @return asset address of the underlying asset
     */
    function asset() external view returns (address);

    /**
     * @notice Get a total amount of repaid debt.
     * @return total repaid debt
     */
    function totalRepaidDebt() external view returns (uint256);

    /**
     * @notice Get an amount of repaid debt created by a particular issuer.
     * @param issuer address of the debt's issuer
     * @return particular issuer's repaid debt
     */
    function issuerRepaidDebt(address issuer) external view returns (uint256);

    /**
     * @notice Get an amount of repaid debt to a particular recipient.
     * @param recipient address that received the underlying asset
     * @return particular recipient's repaid debt
     */
    function recipientRepaidDebt(address recipient) external view returns (uint256);

    /**
     * @notice Get an amount of repaid debt for a particular issuer-recipient pair.
     * @param issuer address of the debt's issuer
     * @param recipient address that received the underlying asset
     * @return particular pair's repaid debt
     */
    function repaidDebt(address issuer, address recipient) external view returns (uint256);

    /**
     * @notice Get a total amount of debt.
     * @return total debt
     */
    function totalDebt() external view returns (uint256);

    /**
     * @notice Get a current debt created by a particular issuer.
     * @param issuer address of the debt's issuer
     * @return particular issuer's debt
     */
    function issuerDebt(address issuer) external view returns (uint256);

    /**
     * @notice Get a current debt to a particular recipient.
     * @param recipient address that should receive the underlying asset
     * @return particular recipient's debt
     */
    function recipientDebt(address recipient) external view returns (uint256);

    /**
     * @notice Get a current debt for a particular issuer-recipient pair.
     * @param issuer address of the debt's issuer
     * @param recipient address that should receive the underlying asset
     * @return particular pair's debt
     */
    function debt(address issuer, address recipient) external view returns (uint256);

    /**
     * @notice Burn a given amount of the collateral, and increase a debt of the underlying asset for the caller.
     * @param recipient address that should receive the underlying asset
     * @param amount amount of the collateral
     */
    function issueDebt(address recipient, uint256 amount) external;

    error NotLimitIncreaser();
    error InsufficientDeposit();
    error ExceedsLimit();
    error InsufficientWithdraw();
    error InsufficientIssueDebt();

    /**
     * @notice Emmited when deposit happens.
     * @param depositor address of the depositor
     * @param recipient address of the collateral's recipient
     * @param amount amount of the collateral minted
     */
    event Deposit(address indexed depositor, address indexed recipient, uint256 amount);

    /**
     * @notice Emmited when withdrawal happens.
     * @param withdrawer address of the withdrawer
     * @param recipient address of the underlying asset's recipient
     * @param amount amount of the collateral burned
     */
    event Withdraw(address indexed withdrawer, address indexed recipient, uint256 amount);

    /**
     * @notice Emmited when limit is increased.
     * @param amount amount to increase the limit by
     */
    event IncreaseLimit(uint256 amount);

    /**
     * @notice Emmited when new limit increaser is set.
     * @param limitIncreaser address of the new limit increaser
     */
    event SetLimitIncreaser(address indexed limitIncreaser);

    /**
     * @notice Get a maximum possible collateral total supply.
     * @return maximum collateral total supply
     */
    function limit() external view returns (uint256);

    /**
     * @notice Get an address of the limit increaser.
     * @return address of the limit increaser
     */
    function limitIncreaser() external view returns (address);

    /**
     * @notice Deposit a given amount of the underlying asset, and mint the collateral to a particular recipient.
     * @param recipient address of the collateral's recipient
     * @param amount amount of the underlying asset
     * @return amount of the collateral minted
     */
    function deposit(address recipient, uint256 amount) external returns (uint256);

    /**
     * @notice Deposit a given amount of the underlying asset using a permit functionality, and mint the collateral to a particular recipient.
     * @param recipient address of the collateral's recipient
     * @param amount amount of the underlying asset
     * @param deadline timestamp of the signature's deadline
     * @param v v component of the signature
     * @param r r component of the signature
     * @param s s component of the signature
     * @return amount of the collateral minted
     */
    function deposit(
        address recipient,
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256);

    /**
     * @notice Withdraw a given amount of the underlying asset, and transfer it to a particular recipient.
     * @param recipient address of the underlying asset's recipient
     * @param amount amount of the underlying asset
     */
    function withdraw(address recipient, uint256 amount) external;

    /**
     * @notice Increase a limit of maximum collateral total supply.
     * @param amount amount to increase the limit by
     * @dev Called only by limitIncreaser.
     */
    function increaseLimit(uint256 amount) external;

    /**
     * @notice Set a new limit increaser.
     * @param limitIncreaser address of the new limit increaser
     * @dev Called only by limitIncreaser.
     */
    function setLimitIncreaser(address limitIncreaser) external;
}
