// SPDX-License-Identifier: MIT
/*
 * This contract uses:
 * - OpenZeppelin Contracts (MIT License)
 * - Trader Joe's LB Router (MIT License)
 *
 * For full license texts, see LICENSE file in the root directory
 */
/// @custom:security-contact security@ercburner.xyz
/// @custom:security-contact contact@ercburner.xyz
pragma solidity 0.8.24;

import { Initializable } from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import { ReentrancyGuardUpgradeable } from '@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol';
import { OwnableUpgradeable } from '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import { AccessControlUpgradeable } from '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import { SafeERC20 } from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import { PausableUpgradeable } from '@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol';
import { Address } from '@openzeppelin/contracts/utils/Address.sol';

import { ILBRouter } from './interfaces/ILBRouter.sol';
import { IWETH } from "./interfaces/IWETH.sol";

import { BurnerEvents } from "./libraries/BurnerEvents.sol";
import { BurnerErrors } from "./libraries/BurnerErrors.sol";

/// @title Trader Joe's LB Router Token Burner
/// @author ERC Burner Team
/// @notice A contract that allows users to swap multiple tokens to AVAX in a single transaction
/// @dev Uses Trader Joe's LB Router for token swaps and implements security measures
/// @dev Uses Relay's RelayReceiver contract for bridge calls
contract Burner is Initializable, ReentrancyGuardUpgradeable, OwnableUpgradeable, PausableUpgradeable, AccessControlUpgradeable {
    using SafeERC20 for IERC20;
    using BurnerErrors for *;
    using BurnerEvents for *;

    /// @notice The parameters for a swap
    /// @param tokenIn The token to swap
    /// @param amountIn The amount of tokens to swap
    /// @param amountOutMinimum The minimum amount of tokens to receive
    /// @param path The path of the swap
    struct SwapParams 
    {
        address tokenIn;
        uint256 amountIn;
        uint256 amountOutMinimum;
        ILBRouter.Path path;
    }

    /// @notice Role identifier for administrators
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    /// @notice The Trader Joe's LB Router contract
    ILBRouter public swapRouter;
    /// @notice The bridge contract address
    address public bridgeAddress;
    /// @notice The wrapped native token address
    address public WNATIVE;
    /// @notice The USDC token address
    address public USDC;
    /// @notice The fee collector address
    address public feeCollector;

    /// @notice The burn fee divisor, as in 100/divisor = y%
    uint256 public burnFeeDivisor;
    /// @notice The bridge fee divisor, as in 100/divisor = y%
    uint256 public bridgeFeeDivisor;
    /// @notice The default referrer fee share, as in share/20 = y%
    uint8 public referrerFeeShare;

    /// @notice The partners addresses mapped to a specific fee share
    mapping(address partner => uint8 feeShare) public partners;

    /// @notice The minimum gas required for a swap
    /// @dev This is to short circuit the burn function and prevent reverts cause by low gas.
    uint32 public minGasForSwap;
    
    /// @notice The maximum number of tokens that can be burned in one transaction
    /// @dev Has been calculated based on the max gas limit of blocks. Should over around 50-70% of the max gas limit.
    uint32 public maxTokensPerBurn;

    /// @notice Whether to pause the bridge
    bool public pauseBridge;
    /// @notice Whether to pause the referral
    bool public pauseReferral;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the contract with required parameters
    /// @dev Sets up the contract with initial configuration values
    /// @param _swapRouter Address of the Swap Router contract
    /// @param _bridgeAddress Address of the bridge contract
    /// @param _WNATIVE Address of the wrapped native token (WETH)
    /// @param _USDC Address of the USDC token
    /// @param _feeCollector Address that will receive the fees
    /// @param _burnFeeDivisor Burn fee divisor (100 = 1%, 200 = 0.5%)
    /// @param _bridgeFeeDivisor Bridge fee divisor (1000 = 0.1%, 2000 = 0.05%)
    /// @param _referrerFeeShare Referrer fee share (5 = 25%, 20 = 100%)
    /// @param _minGasForSwap Minimum gas required for a single swap
    /// @param _maxTokensPerBurn Maximum number of tokens that can be burned in one transaction
    /// @param _pauseBridge Whether to pause bridge
    /// @param _pauseReferral Whether to pause referral
    /// @param _admin Address of the admin
    function initialize(
        ILBRouter _swapRouter,
        address _bridgeAddress,
        address _WNATIVE,
        address _USDC,
        address _feeCollector,
        uint256 _burnFeeDivisor,
        uint256 _bridgeFeeDivisor,
        uint8 _referrerFeeShare,
        uint32 _minGasForSwap,
        uint32 _maxTokensPerBurn,
        bool _pauseBridge,
        bool _pauseReferral,
        address _admin
    ) 
        external 
        initializer 
    {
        __ReentrancyGuard_init_unchained();
        __Ownable_init_unchained(msg.sender);
        __Pausable_init_unchained();
        __AccessControl_init_unchained();

        if(address(_swapRouter) == address(0)) revert BurnerErrors.ZeroAddress();
        if(_bridgeAddress == address(0)) revert BurnerErrors.ZeroAddress();
        if(_WNATIVE == address(0)) revert BurnerErrors.ZeroAddress();
        if(_USDC == address(0)) revert BurnerErrors.ZeroAddress();
        if(_feeCollector == address(0)) revert BurnerErrors.ZeroAddress();
        if(_admin == address(0)) revert BurnerErrors.ZeroAddress();

        swapRouter = _swapRouter;
        bridgeAddress = _bridgeAddress;
        WNATIVE = _WNATIVE;
        USDC = _USDC;
        feeCollector = _feeCollector;
        referrerFeeShare = _referrerFeeShare;
        burnFeeDivisor = _burnFeeDivisor;
        bridgeFeeDivisor = _bridgeFeeDivisor;
        minGasForSwap = _minGasForSwap;
        maxTokensPerBurn = _maxTokensPerBurn;
        pauseBridge = _pauseBridge;
        pauseReferral = _pauseReferral;

        // Setup administration roles
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, _admin);

        emit BurnerEvents.RouterChanged(address(_swapRouter));
        emit BurnerEvents.FeeCollectorChanged(_feeCollector);
        emit BurnerEvents.BridgeAddressChanged(_bridgeAddress);
        emit BurnerEvents.PauseBridgeChanged(_pauseBridge);
        emit BurnerEvents.BurnFeeDivisorChanged(_burnFeeDivisor);
        emit BurnerEvents.BridgeFeeDivisorChanged(_bridgeFeeDivisor);
        emit BurnerEvents.ReferrerFeeShareChanged(_referrerFeeShare);
        emit BurnerEvents.MinGasForSwapChanged(_minGasForSwap);
        emit BurnerEvents.MaxTokensPerBurnChanged(_maxTokensPerBurn);
        emit BurnerEvents.AdminChanged(_admin);
    }

    /// @notice Allows contract upgrade initialization
    /// @dev Used for future upgrades to initialize new state variables
    /// @param version Version number for the upgrade
    function reinitialize(uint8 version) 
        external 
        reinitializer(version)
        nonReentrant
    {
        // Add future upgrade initialization logic
    }

    
    /// @notice Fallback function to allow the contract to receive ETH
    fallback() external payable {}

    /// @notice Receive function to allow the contract to receive ETH
    receive() external payable {}


    /// @notice Modifier to check if the referrer is valid
    /// @param _referrer The referrer address
    modifier referrerCheck(address _referrer) {
        if (_referrer == msg.sender && partners[_referrer] == 0) revert BurnerErrors.ReferrerCannotBeSelf();
        if (_referrer == feeCollector) revert BurnerErrors.ReferrerCannotBeFeeCollector();
        if (_referrer == address(this)) revert BurnerErrors.ReferrerCannotBeContract();
        _;
    }

    /// @notice Modifier to check if the recipient is valid
    /// @param _to The recipient address
    modifier toCheck(address _to) {
        if (_to == address(this)) revert BurnerErrors.ToCannotBeContract();
        if (_to == feeCollector) revert BurnerErrors.ToCannotBeFeeCollector();
        _;
    }
    
    /// @notice Swaps multiple tokens for ETH in a single transaction
    /// @dev Processes multiple swaps and charges a fee on the total output
    /// @param params Array of swap parameters for each token
     /// @param _to The recipient address
    /// @param bridge Whether to bridge the ETH
    /// @param bridgeData The data to be sent to the bridge contract
    /// @param _referrer The referrer address
    /// @return amountAfterFee The amount of ETH received after fees
    function swapExactInputMultiple(
        SwapParams[] calldata params,
        address _to,
        bool bridge,
        bytes calldata bridgeData,
        address _referrer
    ) 
        external 
        payable 
        nonReentrant 
        whenNotPaused 
        referrerCheck(_referrer) 
        toCheck(_to) 
        returns (uint256 amountAfterFee) 
    {
        if (bridge && pauseBridge) revert BurnerErrors.BridgePaused();
        if (params.length == 0 || params.length > maxTokensPerBurn) revert BurnerErrors.MismatchedInputs(params.length);
        if (!bridge && bridgeData.length > 0) revert BurnerErrors.BridgeDataMustBeEmpty(bridgeData);
        if (bridge && _to != address(0)) revert BurnerErrors.BridgeAndRecipientBothSet(_to);
        if (bridge && bridgeData.length == 0) revert BurnerErrors.InvalidBridgeData();
        if (!bridge && msg.value > 0 && _to == address(0)) revert BurnerErrors.RecipientMustBeSet();

        uint256 totalAmountOut = 0;
        uint48 expiration = uint48(block.timestamp + 900);
        uint256 len = params.length;

        for (uint256 i; i < len; ) {
            SwapParams calldata param = params[i];

            // Short circuit if insufficient gas.
            if (gasleft() < minGasForSwap) {
                emit BurnerEvents.SwapFailed(msg.sender, param.tokenIn, param.amountIn, "Insufficient gas");
                break;
            }
            // Skip if amount is 0.
            if (param.amountIn == 0) {
                emit BurnerEvents.SwapFailed(msg.sender, param.tokenIn, param.amountIn, "Zero amount");
                unchecked { ++i; }
                continue;
            }

            // Transfer the tokens from the sender to the contract.
            IERC20 token = IERC20(param.tokenIn);
            token.safeTransferFrom(msg.sender, address(this), param.amountIn);

            // If token is WNATIVE, skip the swap.
            if (param.tokenIn == WNATIVE) {
                totalAmountOut += param.amountIn;
                emit BurnerEvents.SwapSuccess(msg.sender, param.tokenIn, param.amountIn, param.amountIn);
                unchecked { ++i; }
                continue;
            }

            // Increase allowance for the swap router.
            token.safeIncreaseAllowance(address(swapRouter), param.amountIn);

            // Execute the swap.
            try swapRouter.swapExactTokensForTokens(param.amountIn, param.amountOutMinimum, param.path, address(this), expiration) returns (uint256 actualReceived) {
                // If the amount received is 0, revert.
                if (actualReceived <= 0) revert BurnerErrors.AvaxSwapIssue(msg.sender, param.tokenIn, param.amountIn, "Zero amount received");
                // Add the amount received to the total amount out.
                totalAmountOut += actualReceived;

                emit BurnerEvents.SwapSuccess(msg.sender, param.tokenIn, param.amountIn, actualReceived);
            } catch {
                // If the swap fails, decrease the allowance of the router contract.
                token.safeDecreaseAllowance(address(swapRouter), param.amountIn);
                // Return the tokens to the sender.
                token.safeTransfer(msg.sender, param.amountIn);

                emit BurnerEvents.SwapFailed(msg.sender, param.tokenIn, param.amountIn, "Router error");

                unchecked { ++i; }
                continue;
            }
            unchecked { ++i; }
        }
        
        // If the total amount out is 0, return 0.
        if (totalAmountOut == 0) return 0;
        // If the total amount out is less than the burn fee divisor * 20, revert.
        if (totalAmountOut < burnFeeDivisor * 20) revert BurnerErrors.InsufficientTotalOutput(totalAmountOut, burnFeeDivisor * 20);

        // Calculate the fee amount.
        uint256 feeAmount = totalAmountOut / burnFeeDivisor;
        // Calculate the amount after fee.
        amountAfterFee = totalAmountOut - feeAmount;

        // Convert WNATIVE to ETH.
        IWETH(WNATIVE).withdraw(totalAmountOut);

        // If msg.value is sent and less than the bridge fee divisor * 20 (Times 20 to ensure proper fee calculation), revert.
        if (msg.value > 0 && msg.value < bridgeFeeDivisor * 20) revert BurnerErrors.InsufficientValue(msg.value, bridgeFeeDivisor * 20);
        
        // If msg.value is sent, calculate the bridge fee and update amountAfterFee.
        if (msg.value >= bridgeFeeDivisor * 20) {
            uint256 bridgeFee = msg.value / bridgeFeeDivisor;
            uint256 valueAfterFee = msg.value - bridgeFee;
            feeAmount += bridgeFee;
            amountAfterFee += valueAfterFee;
        }

        // If the referrer is not the zero address, calculate the referrer fee and update feeAmount.
        uint256 referrerFee = 0;
        if (_referrer != address(0)) {
            referrerFee = _calculateReferrerFee(feeAmount, _referrer);
            feeAmount -= referrerFee;
            Address.sendValue(payable(_referrer), referrerFee);
            emit BurnerEvents.ReferrerFeePaid(msg.sender, _referrer, referrerFee);
        }

        // Send the fee to the fee collector.
        Address.sendValue(payable(feeCollector), feeAmount);

        // If the bridge is true, send both the swapped ETH (net of fee) and the msg.value (net of fee) to the bridge contract.
        if (bridge) {
            // Send both the swapped ETH and the msg.value (net of fee) to the bridge contract.
            bytes memory returnData = Address.functionCallWithValue(bridgeAddress, bridgeData, amountAfterFee);
            //Redundant event, but kept for clarity and dashboards.
            emit BurnerEvents.BridgeSuccess(msg.sender, returnData, amountAfterFee, feeAmount + referrerFee);
        } else {
            // Determine recipient: use _to if provided, otherwise default to msg.sender.
            address recipient = _to == address(0) ? msg.sender : _to;
            // Send the amount after fee to the recipient.
            Address.sendValue(payable(recipient), amountAfterFee);
        }

        emit BurnerEvents.BurnSuccess(msg.sender, amountAfterFee, feeAmount + referrerFee);
        return amountAfterFee;
    }

    /// @notice Calls the Relay Receiver bridge contract
    /// @param _bridgeData The data to be sent to the bridge contract
    /// @param _referrer The referrer address
    function relayBridge(bytes calldata _bridgeData, address _referrer) 
        external 
        payable 
        nonReentrant 
        referrerCheck(_referrer) 
    {
        if (msg.value == 0) revert BurnerErrors.ZeroValue();
        if (_bridgeData.length == 0) revert BurnerErrors.InvalidBridgeData();
        if (msg.value < bridgeFeeDivisor * 20) revert BurnerErrors.InsufficientValue(msg.value, bridgeFeeDivisor * 20);
        
        // Calculate the bridge fee and amount after fee.
        uint256 bridgeFee = msg.value / bridgeFeeDivisor;
        uint256 amountAfterFee = msg.value - bridgeFee;

        uint256 referrerFee = 0;
        if (_referrer != address(0)) {
            referrerFee = _calculateReferrerFee(bridgeFee, _referrer);
            bridgeFee -= referrerFee;
            Address.sendValue(payable(_referrer), referrerFee);
            emit BurnerEvents.ReferrerFeePaid(msg.sender, _referrer, referrerFee);
        }
        // Send the fee to the fee collector.
        Address.sendValue(payable(feeCollector), bridgeFee);

        // Call the bridge contract.
        bytes memory returnData = Address.functionCallWithValue(bridgeAddress, _bridgeData, amountAfterFee);
        emit BurnerEvents.BridgeSuccess(msg.sender, returnData, amountAfterFee, bridgeFee + referrerFee);
    }

    /// @notice User can pay for a better referrer fee share.
    /// @param _amount The amount of USDC to pay for the referrer fee share.
    function paidReferrer(uint256 _amount) 
        external 
        nonReentrant 
    {
        if (partners[msg.sender] > 0) revert BurnerErrors.ReferrerAlreadyPaid();
        uint256 allowance = IERC20(USDC).allowance(msg.sender, address(this));
        uint8 feeShare = 0;
        
        // 100 USDC = 50% share
        // 50 USDC = 40% share
        // 25 USDC = 30% share
        if (_amount == 100 * 10 ** 6 && allowance >= 100 * 10 ** 6) {
            feeShare = 10; // 50% share
        } else if (_amount == 50 * 10 ** 6 && allowance >= 50 * 10 ** 6) {
            feeShare = 8; // 40% share
        } else if (_amount == 25 * 10 ** 6 && allowance >= 25 * 10 ** 6) {
            feeShare = 6; // 30% share
        } else {
            revert BurnerErrors.InsufficientAllowanceOrAmount(allowance, _amount);
        }
        // Update the partner's fee share.
        partners[msg.sender] = feeShare;
        // Transfer the required amount.
        IERC20(USDC).safeTransferFrom(msg.sender, feeCollector, _amount);

        emit BurnerEvents.PartnerAdded(msg.sender);
        emit BurnerEvents.PartnerFeeShareChanged(msg.sender, feeShare);
    }

    /// @notice User can upgrade their referrer fee share.
    /// @param _amount The amount of USDC to pay for the referrer fee share.
    function upgradeReferrer(uint256 _amount) 
        external 
        nonReentrant 
    {
        uint256 currentShare = partners[msg.sender];
        if (currentShare == 0) revert BurnerErrors.ReferrerNotRegistered();
        
        uint256 allowance = IERC20(USDC).allowance(msg.sender, address(this));
        uint8 newFeeShare = 0;
        uint256 requiredAmount = 0;

        // For 30% tier, 75 USDC = 50% share
        // For 30% tier, 25 USDC = 40% share
        if (currentShare == 6) { // Current tier is 30%
            if (_amount == 75 * 10 ** 6 && allowance >= 75 * 10 ** 6) {
                newFeeShare = 10; // 50% share
                requiredAmount = 75 * 10 ** 6;
            } else if (_amount == 25 * 10 ** 6 && allowance >= 25 * 10 ** 6) {
                newFeeShare = 8; // 40% share
                requiredAmount = 25 * 10 ** 6;
            } else {
                revert BurnerErrors.InsufficientAllowanceOrAmount(allowance, _amount);
            }
        } else if (currentShare == 8) { // Current tier is 40%
            // For 40% tier, 50 USDC = 50% share
            if (_amount == 50 * 10 ** 6 && allowance >= 50 * 10 ** 6) {
                newFeeShare = 10; // 50% share
                requiredAmount = 50 * 10 ** 6;
            } else {
                revert BurnerErrors.InsufficientAllowanceOrAmount(allowance, _amount);
            }
        } else if (currentShare == 10) {
            // If the current tier is 50%, the maximum tier is reached.
            revert BurnerErrors.MaximumTierReached();
        } else {
            // Update the partner's fee share
            revert BurnerErrors.OnPartnerTier();
        }
        // Update the partner's fee share
        partners[msg.sender] = newFeeShare;
        
        // Transfer the required amount
        IERC20(USDC).safeTransferFrom(msg.sender, feeCollector, requiredAmount);

        emit BurnerEvents.PartnerFeeShareChanged(msg.sender, newFeeShare);
    }

    /// @notice Calculates the referrer fee
    /// @param _amount The amount to calculate the referrer fee for
    /// @return referrerFee The referrer fee
    function _calculateReferrerFee(uint256 _amount, address _referrer) 
        private 
        view 
        returns (uint256 referrerFee) 
    {
        // If the referral is paused, return 0.
        if (pauseReferral) return 0;
        // If the referrer is registered, calculate the partner's fee.
        if (partners[_referrer] > 0) {
            return _amount * partners[_referrer] / 20;
        } else {
            // If the referrer is not registered, calculate the referrer fee.
            return _amount * referrerFeeShare / 20;
        }
    }
    
    /// @notice Adds or modifies a partner share
    /// @dev Can be called by the owner or by an account with the ADMIN_ROLE
    /// @param _partner The partner address
    /// @param _feeShare The fee share, from 1 to 20 (1 = 5%, 20 = 100%)
    function putPartner(address _partner, uint8 _feeShare) 
        external 
        nonReentrant 
        whenNotPaused  
    {
        // If the caller is not the owner or the ADMIN_ROLE, revert.
        if(!hasRole(DEFAULT_ADMIN_ROLE, msg.sender) && !hasRole(ADMIN_ROLE, msg.sender)) revert BurnerErrors.CallerNotAdminOrOwner(msg.sender);
        // If the partner is the zero address, revert.
        if (_partner == address(0)) revert BurnerErrors.ZeroAddress();
        if (_feeShare > 20) revert BurnerErrors.FeeShareTooHigh(_feeShare, 20);
        if (_feeShare == 0) revert BurnerErrors.ZeroFeeShare();

        // If the partner is not already registered, emit the event.
        if (partners[_partner] == 0) emit BurnerEvents.PartnerAdded(_partner); 
        // Update the partner's fee share.
        partners[_partner] = _feeShare;

        emit BurnerEvents.PartnerFeeShareChanged(_partner, _feeShare);
    }

    /// @notice Removes a partner
    /// @dev Can only be called by the owner
    /// @param _partner The partner address
    function removePartner(address _partner) 
        external 
        onlyOwner 
        nonReentrant 
    {
        // Delete the partner's fee share.
        delete partners[_partner];
        emit BurnerEvents.PartnerRemoved(_partner);
    }
    
    /// @notice Updates the burn fee divisor, 2.5% being the maximum
    /// @dev Can only be called by the owner
    /// @param _newBurnFeeDivisor New fee divisor
    function setBurnFeeDivisor(uint16 _newBurnFeeDivisor) 
        external 
        onlyOwner 
        nonReentrant 
    {
        if (_newBurnFeeDivisor < 40) revert BurnerErrors.FeeDivisorTooLow(_newBurnFeeDivisor, 40);
        burnFeeDivisor = _newBurnFeeDivisor;
        emit BurnerEvents.BurnFeeDivisorChanged(_newBurnFeeDivisor);
    }

    /// @notice Updates the bridge fee divisor, 0.25% being the maximum
    /// @dev Can only be called by the owner
    /// @param _newBridgeFeeDivisor New fee divisor
    function setBridgeFeeDivisor(uint16 _newBridgeFeeDivisor) 
        external 
        onlyOwner 
        nonReentrant 
    {
        // If the new burn fee divisor is less than 40, revert.
        if (_newBridgeFeeDivisor < 400) revert BurnerErrors.FeeDivisorTooLow(_newBridgeFeeDivisor, 400);
        // Update the burn fee divisor.
        bridgeFeeDivisor = _newBridgeFeeDivisor;
        emit BurnerEvents.BridgeFeeDivisorChanged(_newBridgeFeeDivisor);
    }

    /// @notice Updates the referrer fee share
    /// @dev Can only be called by the owner
    /// @param _newReferrerFeeShare New fee share
    function setReferrerFeeShare(uint8 _newReferrerFeeShare) 
        external 
        onlyOwner 
        nonReentrant 
    {
        // If the new referrer fee share is greater than 20, revert.
        if (_newReferrerFeeShare > 20) revert BurnerErrors.FeeShareTooHigh(_newReferrerFeeShare, 20);
        // If the new referrer fee share is 0, revert.
        if (_newReferrerFeeShare == 0) revert BurnerErrors.ZeroFeeShare();
        // Update the referrer fee share.
        referrerFeeShare = _newReferrerFeeShare;
        emit BurnerEvents.ReferrerFeeShareChanged(_newReferrerFeeShare);
    }

    /// @notice Updates the universal router address
    /// @dev Can only be called by the owner
    /// @param _newUniversalRouter New address to universal router
    function setUniversalRouter(address _newUniversalRouter) 
        external 
        onlyOwner 
        nonReentrant 
    {
        if (_newUniversalRouter == address(0)) revert BurnerErrors.ZeroAddress();
        swapRouter = ILBRouter(_newUniversalRouter);
        emit BurnerEvents.RouterChanged(_newUniversalRouter);
    }

    /// @notice Updates the bridge address
    /// @dev Can only be called by the owner
    /// @param _newBridgeAddress New address to bridge
    function setBridgeAddress(address _newBridgeAddress) 
        external 
        onlyOwner 
        nonReentrant 
    {
        if (_newBridgeAddress == address(0)) revert BurnerErrors.ZeroAddress();
        bridgeAddress = _newBridgeAddress;
        emit BurnerEvents.BridgeAddressChanged(_newBridgeAddress);
    }

    /// @notice Updates the fee collector address
    /// @dev Can only be called by the owner
    /// @param _newFeeCollector New address to collect fees
    function setFeeCollector(address _newFeeCollector) 
        external 
        onlyOwner 
        nonReentrant 
    {
        if (_newFeeCollector == address(0)) revert BurnerErrors.ZeroAddress();
        feeCollector = _newFeeCollector;
        emit BurnerEvents.FeeCollectorChanged(_newFeeCollector);
    }

    /// @notice Updates the admin address
    /// @dev Can only be called by the owner
    /// @param _oldAdmin The old admin address
    /// @param _newAdmin New address to admin
    function setAdmin(address _oldAdmin, address _newAdmin)
        external
        onlyOwner
        nonReentrant
    {
        // If the new admin is the zero address, revert.
        if (_newAdmin == address(0)) revert BurnerErrors.ZeroAddress();
        // If the old admin is the zero address, revert.
        if (_oldAdmin == address(0)) revert BurnerErrors.ZeroAddress();
        // If the old admin is the same as the new admin, revert.
        if (_oldAdmin == _newAdmin) revert BurnerErrors.SameAdmin();
        // If the new admin already has the ADMIN_ROLE, revert.
        if (hasRole(ADMIN_ROLE, _newAdmin)) revert BurnerErrors.AdminAlreadyExists();
        // If the old admin does not have the ADMIN_ROLE, revert.
        if (!hasRole(ADMIN_ROLE, _oldAdmin)) revert BurnerErrors.AdminDoesNotExist();

        // Revoke the old admin's ADMIN_ROLE.
        _revokeRole(ADMIN_ROLE, _oldAdmin);
        // Grant the new admin the ADMIN_ROLE.
        _grantRole(ADMIN_ROLE, _newAdmin);
        emit BurnerEvents.AdminChanged(_newAdmin);
    }

    /// @notice Updates the minimum gas required for a swap
    /// @dev Can only be called by the owner
    /// @param _newMinGasForSwap New minimum gas value
    function setMinGasForSwap(uint32 _newMinGasForSwap)
        external
        onlyOwner
        nonReentrant
    {
        if (_newMinGasForSwap == 0) revert BurnerErrors.ZeroMinGasForSwap();
        minGasForSwap = _newMinGasForSwap;
        emit BurnerEvents.MinGasForSwapChanged(_newMinGasForSwap);
    }

    /// @notice Updates the maximum number of tokens that can be burned in one transaction
    /// @dev Can only be called by the owner
    /// @param _newMaxTokensPerBurn New maximum number of tokens
    function setMaxTokensPerBurn(uint32 _newMaxTokensPerBurn)
        external
        onlyOwner
        nonReentrant
    {
        if (_newMaxTokensPerBurn == 0) revert BurnerErrors.ZeroMaxTokensPerBurn();
        maxTokensPerBurn = _newMaxTokensPerBurn;
        emit BurnerEvents.MaxTokensPerBurnChanged(_newMaxTokensPerBurn);
    }

    /// @notice Allows the owner to rescue stuck tokens
    /// @dev Transfers any ERC20 tokens stuck in the contract
    /// @dev Can only be called by the owner
    /// @param _token Address of the token to rescue
    /// @param _to Address to send the tokens to
    /// @param _amount Amount of tokens to rescue
    function rescueTokens(
        address _token, 
        address _to, 
        uint256 _amount
    )
        external
        onlyOwner
        nonReentrant
    {
        if (_token == address(0)) revert BurnerErrors.ZeroAddress();
        if (_to == address(0)) revert BurnerErrors.ZeroAddress();
        IERC20(_token).safeTransfer(_to, _amount);
    }

    /// @notice Allows the owner to rescue stuck ETH
    /// @dev Transfers any ETH stuck in the contract
    /// @dev Can only be called by the owner
    /// @param _to Address to send the ETH to
    /// @param _amount Amount of ETH to rescue
    function rescueETH(address _to, uint256 _amount)
        external
        onlyOwner
        nonReentrant
    {
        if (_to == address(0)) revert BurnerErrors.ZeroAddress();
        Address.sendValue(payable(_to), _amount);
    }

    /// @notice Pauses the bridge
    /// @dev Can only be called by the owner
    function changePauseBridge()
        external
        onlyOwner
        nonReentrant
    {
        pauseBridge = !pauseBridge;
        emit BurnerEvents.PauseBridgeChanged(pauseBridge);
    }

    /// @notice Pauses the referral
    /// @dev Can only be called by the owner
    function changePauseReferral()
        external
        onlyOwner
        nonReentrant
    {
        pauseReferral = !pauseReferral;
        emit BurnerEvents.PauseReferralChanged(pauseReferral);
    }


    /// @notice Pauses the contract
    /// @dev Can only be called by the owner
    function pause()
        external
        onlyOwner
        nonReentrant
    {
        _pause();
    }

    /// @notice Unpauses the contract
    /// @dev Can only be called by the owner
    function unpause()
        external
        onlyOwner
        nonReentrant
    {
        _unpause();
    }

    /// @dev To prevent upgradeability issues.
    uint256[50] private __gap;
}