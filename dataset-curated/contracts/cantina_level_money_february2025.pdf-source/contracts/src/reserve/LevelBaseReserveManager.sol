// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19;

import "../interfaces/ILevelBaseReserveManager.sol";
import "../interfaces/IlvlUSD.sol";
import "../interfaces/ILevelMinting.sol";
import "../interfaces/IStakedlvlUSD.sol";
import "../interfaces/ILevelBaseYieldManager.sol";

import {SingleAdminAccessControl} from "../auth/v5/SingleAdminAccessControl.sol";
import {WrappedRebasingERC20} from "../WrappedRebasingERC20.sol";

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

/**
 * @title Level Base Reserve Manager
 * @notice This is the superclass for all reserve managers
 * to inherit common functionality. It is _not_ intended
 * to be deployed on its own.
 */
abstract contract LevelBaseReserveManager is
    ILevelBaseReserveManager,
    SingleAdminAccessControl,
    Pausable
{
    using FixedPointMathLib for uint256;
    using SafeCast for uint256;
    using SafeERC20 for IERC20;

    event EtherReceived(address indexed sender, uint256 amount);
    event FallbackCalled(address indexed sender, uint256 amount, bytes data);

    /// @notice role that sets the addresses where funds can be sent from this contract
    bytes32 private constant ALLOWLIST_ROLE = keccak256("ALLOWLIST_ROLE");

    /// @notice role that deposits to/withdraws from a yield strategy or a restaking protocol
    bytes32 internal constant MANAGER_AGENT_ROLE =
        keccak256("MANAGER_AGENT_ROLE");

    /// @notice role that pauses the contract
    bytes32 private constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /* --------------- STATE VARIABLES --------------- */

    /// @notice address that receives the yield
    address public treasury;

    /// @notice basis points of the max slippage threshold
    uint16 constant MAX_BASIS_POINTS = 1e4;

    /// @notice basis points of the rake
    uint16 public rakeBasisPoints;

    uint16 public constant MAX_RAKE_BASIS_POINTS = 5000; // 50%

    /// @notice basis points of max slippage threshold
    uint16 public maxSlippageThresholdBasisPoints;

    IlvlUSD public immutable lvlUSD;
    uint256 public immutable lvlUsdDecimals;
    ILevelMinting public immutable levelMinting;

    mapping(address => bool) public allowlist;
    IStakedlvlUSD stakedlvlUSD;

    // mapping of native token address to yield manager responsible for handling that token
    mapping(address => ILevelBaseYieldManager) yieldManager;

    /* --------------- CONSTRUCTOR --------------- */

    constructor(
        IlvlUSD _lvlUSD,
        IStakedlvlUSD _stakedlvlUSD,
        address _admin,
        address _allowlister
    ) {
        if (address(_lvlUSD) == address(0)) revert InvalidlvlUSDAddress();
        if (_admin == address(0)) revert InvalidZeroAddress();
        lvlUSD = _lvlUSD;
        lvlUsdDecimals = _lvlUSD.decimals();
        levelMinting = ILevelMinting(_lvlUSD.minter());

        stakedlvlUSD = _stakedlvlUSD;

        maxSlippageThresholdBasisPoints = 5; // 0.05%
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ALLOWLIST_ROLE, _allowlister);
        _grantRole(PAUSER_ROLE, _admin);
    }

    /* --------------- EXTERNAL --------------- */

    /**
     * @notice Convert `amount` of `token` to a yield bearing version
     * (ie wrapped Aave USDT if token is USDT)
     * @param token address of the token
     * @param amount amount to deposit
     * @dev only callable by manager agent
     */
    function depositForYield(
        address token,
        uint256 amount
    ) external onlyRole(MANAGER_AGENT_ROLE) whenNotPaused {
        IERC20(token).forceApprove(address(yieldManager[token]), amount);
        yieldManager[token].depositForYield(token, amount);
        emit DepositedToYieldManager(
            token,
            address(yieldManager[token]),
            amount
        );
    }

    /**
     * @notice Convert `amount` of `token` from a yield bearing version
     * (ie wrapped Aave USDT if token is USDT) to the native version (ie USDT)
     * @param token address of the token
     * @param amount amount to withdraw
     * @dev only callable by manager agent
     */
    function withdrawFromYieldManager(
        address token,
        uint256 amount
    ) external onlyRole(MANAGER_AGENT_ROLE) whenNotPaused {
        yieldManager[token].withdraw(token, amount);
        emit WithdrawnFromYieldManager(
            token,
            address(yieldManager[token]),
            amount
        );
    }

    /**
     * @notice Deposit collateral to level minting contract, to be made available
     * for redemptions
     * @param token address of the collateral token
     * @param amount amount of collateral to deposit
     * @dev only callable by manager agent
     */
    function depositToLevelMinting(
        address token,
        uint256 amount
    ) external onlyRole(MANAGER_AGENT_ROLE) whenNotPaused {
        IERC20(token).safeTransfer(address(levelMinting), amount);
        emit DepositedToLevelMinting(amount);
    }

    /**
     * @notice Take a rake from the amount and transfer it to the treasury
     * @param token address of the token to take rake from
     * @param amount amount of token to take rake from
     * @return rake amount taken
     * @return remainder amount after rake
     */
    function _takeRake(
        address token,
        uint256 amount
    ) internal returns (uint256, uint256) {
        if (treasury == address(0)) {
            revert TreasuryNotSet();
        }

        if (rakeBasisPoints == 0 || amount == 0) {
            return (0, amount);
        }

        uint256 rake = amount.mulDivUp(rakeBasisPoints, MAX_BASIS_POINTS);
        uint256 remainder = amount - rake;
        IERC20(token).safeTransfer(treasury, rake);

        return (rake, remainder);
    }

    /**
     * @notice Rewards staked lvlUSD with lvlUSD. The admin should call
     * mint lvlUSD before calling this function
     * @param amount amount of lvlUSD to reward
     * @dev only callable by admin
     */
    function _rewardStakedlvlUSD(uint256 amount) internal whenNotPaused {
        IERC20(lvlUSD).forceApprove(address(stakedlvlUSD), amount);
        stakedlvlUSD.transferInRewards(amount);
    }

    /**
     * @notice Mint lvlUSD using collateral
     * @param collateral address of the collateral token
     * @param collateralAmount amount of collateral to mint lvlUSD with
     * @dev only callable by admin
     */
    function _mintlvlUSD(
        address collateral,
        uint256 collateralAmount
    ) internal whenNotPaused {
        IERC20(collateral).forceApprove(
            address(levelMinting),
            collateralAmount
        );
        uint256 collateralDecimals = ERC20(collateral).decimals();
        uint256 lvlUSDAmount;

        if (collateralDecimals < lvlUsdDecimals) {
            lvlUSDAmount =
                collateralAmount *
                (10 ** (lvlUsdDecimals - collateralDecimals));
        } else {
            lvlUSDAmount =
                collateralAmount /
                (10 ** (collateralDecimals - lvlUsdDecimals));
        }

        // Apply max slippage threshold
        lvlUSDAmount -= lvlUSDAmount.mulDivDown(
            maxSlippageThresholdBasisPoints,
            MAX_BASIS_POINTS
        );

        ILevelMinting.Order memory order = ILevelMinting.Order(
            ILevelMinting.OrderType.MINT,
            address(this), // benefactor
            address(this), // beneficiary
            collateral, // collateral
            collateralAmount, // collateral amount
            lvlUSDAmount // expected minimum level USD amount to receive to this contract
        );
        levelMinting.mintDefault(order);
    }

    function rewardStakedlvlUSD(
        address token
    ) external onlyRole(MANAGER_AGENT_ROLE) whenNotPaused {
        uint amount = yieldManager[token].collectYield(token);
        (, uint256 collateralAmount) = _takeRake(token, amount);
        if (collateralAmount == 0) {
            revert InvalidAmount();
        }
        uint lvlUSDBalBefore = lvlUSD.balanceOf(address(this));
        _mintlvlUSD(token, collateralAmount);
        uint lvlUSDBalAfter = lvlUSD.balanceOf(address(this));
        _rewardStakedlvlUSD(lvlUSDBalAfter - lvlUSDBalBefore);
    }

    /** Rescue functions- only callable by admin for emergencies */

    /**
     * @notice Approve spender to spend a certain amount of token
     * @param token address of the token
     * @param spender address of the spender
     * @param amount amount to approve
     * @dev only callable by admin
     */
    function approveSpender(
        address token,
        address spender,
        uint256 amount
    ) external onlyRole(DEFAULT_ADMIN_ROLE) whenNotPaused {
        IERC20(token).forceApprove(spender, amount);
    }

    /**
     * @notice Transfer ERC20 token to a recipient
     * @param tokenAddress address of the token
     * @param tokenReceiver address of the recipient
     * @param tokenAmount amount of token to transfer
     * @dev only callable by admin
     */
    function transferERC20(
        address tokenAddress,
        address tokenReceiver,
        uint256 tokenAmount
    ) external onlyRole(DEFAULT_ADMIN_ROLE) whenNotPaused {
        if (allowlist[tokenReceiver]) {
            IERC20(tokenAddress).safeTransfer(tokenReceiver, tokenAmount);
        } else {
            revert InvalidRecipient();
        }
    }

    /**
     * @notice Transfer ETH to a recipient
     * @param _to address of the recipient
     * @param _amount amount of ETH to transfer
     * @dev only callable by admin
     */
    function transferEth(
        address payable _to,
        uint256 _amount
    ) external onlyRole(DEFAULT_ADMIN_ROLE) whenNotPaused {
        if (allowlist[_to]) {
            (bool success, ) = _to.call{value: _amount}("");
            require(success, "Failed to send Ether");
        } else {
            revert InvalidRecipient();
        }
    }

    // Receive function - Called when ETH is sent with empty calldata
    receive() external payable {
        emit EtherReceived(msg.sender, msg.value);
    }

    // Fallback function - Called when ETH is sent with non-empty calldata
    fallback() external payable {
        emit FallbackCalled(msg.sender, msg.value, msg.data);
    }

    /* --------------- SETTERS --------------- */

    function setPaused(bool paused) external onlyRole(PAUSER_ROLE) {
        if (paused) {
            _pause();
        } else {
            _unpause();
        }
    }

    function setAllowlist(
        address recipient,
        bool isAllowlisted
    ) external onlyRole(ALLOWLIST_ROLE) whenNotPaused {
        allowlist[recipient] = isAllowlisted;
    }

    function setStakedlvlUSDAddress(
        address newAddress
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        stakedlvlUSD = IStakedlvlUSD(newAddress);
    }

    function setYieldManager(
        address token,
        address baseYieldManager
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        yieldManager[token] = ILevelBaseYieldManager(baseYieldManager);
        emit YieldManagerSetForToken(token, address(yieldManager[token]));
    }

    function setTreasury(
        address _treasury
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        treasury = _treasury;
    }

    function setRakeBasisPoints(
        uint16 _rakeBasisPoints
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_rakeBasisPoints > MAX_RAKE_BASIS_POINTS) {
            revert InvalidAmount();
        }
        rakeBasisPoints = _rakeBasisPoints;
    }

    function setMaxSlippageThresholdBasisPoints(
        uint16 _maxSlippageThresholdBasisPoints
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(
            _maxSlippageThresholdBasisPoints <= MAX_BASIS_POINTS,
            "Slippage threshold cannot exceed max basis points"
        );
        maxSlippageThresholdBasisPoints = _maxSlippageThresholdBasisPoints;
    }
}
