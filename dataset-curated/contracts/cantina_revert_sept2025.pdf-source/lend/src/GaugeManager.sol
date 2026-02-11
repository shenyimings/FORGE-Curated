// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "./interfaces/aerodrome/IAerodromeNonfungiblePositionManager.sol";
import "./interfaces/aerodrome/IAerodromeSlipstreamFactory.sol";
import "./interfaces/aerodrome/IGauge.sol";
import "./interfaces/IVault.sol";
import "./transformers/V3Utils.sol";
import "./utils/Constants.sol";
import "./utils/Swapper.sol";

/// @title GaugeManager with Built-in Compounding
/// @notice Single contract that handles both staking AND compounding
/// @dev Simplest solution - one contract does everything
contract GaugeManager is Ownable2Step, IERC721Receiver, ReentrancyGuard, Swapper {
    using SafeERC20 for IERC20;

    event PositionStaked(uint256 indexed tokenId, address indexed owner);
    event PositionUnstaked(uint256 indexed tokenId, address indexed owner);
    event RewardsCompounded(uint256 indexed tokenId, uint256 aeroAmount, uint256 amount0, uint256 amount1);
    event SwapAndIncreaseLiquidity(uint256 indexed tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);
    event V3UtilsSet(address indexed v3Utils);
    event PositionMigratedToVault(uint256 indexed tokenId, address indexed owner);
    event PositionTransformed(uint256 indexed oldTokenId, uint256 indexed newTokenId, address indexed owner);
    event TransformerSet(address indexed transformer, bool active);
    event ApprovedTransform(uint256 indexed tokenId, address indexed owner, address indexed transformer, bool isActive);

    IERC20 public immutable aeroToken;
    IVault public immutable vault;
    
    // V3Utils for position management operations
    address payable public v3Utils;
    
    // Compound fee configuration
    uint64 public constant MAX_REWARD_X64 = uint64(Q64 * 5 / 100); // 5% max fee
    uint64 public totalRewardX64 = 0; // Start at 0%, owner can set up to 5%
    address public feeWithdrawer; // Can withdraw accumulated fees

    // Core mappings
    mapping(address => address) public poolToGauge;
    mapping(uint256 => address) public tokenIdToGauge;
    mapping(uint256 => address) public positionOwners;
    mapping(uint256 => bool) public isVaultPosition;
    
    // Transform system for AutoRange/AutoCompound integration
    mapping(address => bool) public transformerAllowList;
    uint256 public transformedTokenId;
    
    // Transform approvals: owner => tokenId => transformer => approved
    mapping(address => mapping(uint256 => mapping(address => bool))) public transformApprovals;

    constructor(
        IAerodromeNonfungiblePositionManager _npm,
        IERC20 _aeroToken,
        IVault _vault,
        address _universalRouter,
        address _zeroxAllowanceHolder,
        address _feeWithdrawer
    ) Swapper(
        INonfungiblePositionManager(address(_npm)),
        _universalRouter,
        _zeroxAllowanceHolder
    ) Ownable2Step() {
        aeroToken = _aeroToken;
        vault = _vault;
        feeWithdrawer = _feeWithdrawer;
    }

    /// @notice Set gauge for a pool
    function setGauge(address pool, address gauge) external onlyOwner {
        poolToGauge[pool] = gauge;
    }

    /// @notice Approve/revoke transformer for a specific position
    function approveTransform(uint256 tokenId, address transformer, bool isActive) external {
        require(positionOwners[tokenId] == msg.sender, "Not position owner");
        transformApprovals[msg.sender][tokenId][transformer] = isActive;
        emit ApprovedTransform(tokenId, msg.sender, transformer, isActive);
    }

    /// @notice Set transformer contract (e.g., AutoRange) allowlist
    function setTransformer(address transformer, bool active) external onlyOwner {
        transformerAllowList[transformer] = active;
        emit TransformerSet(transformer, active);
    }

    /// @notice Set V3Utils contract address
    function setV3Utils(address payable _v3Utils) external onlyOwner {
        v3Utils = _v3Utils;
        emit V3UtilsSet(_v3Utils);
    }

    /// @notice Stake a position (works for both vault and direct)
    function stakePosition(uint256 tokenId) external nonReentrant {
        address nftOwner = nonfungiblePositionManager.ownerOf(tokenId);
        
        // Determine if vault or direct position
        bool fromVault = msg.sender == address(vault);
        address owner = fromVault ? IVault(vault).ownerOf(tokenId) : msg.sender;
        
        require(owner != address(0), "Invalid owner");
        require(fromVault || nftOwner == msg.sender, "Not authorized");

        // Get gauge for position
        (,, address token0, address token1, uint24 tickSpacing,,,,,,,) = 
            nonfungiblePositionManager.positions(tokenId);
        address pool = IAerodromeSlipstreamFactory(factory).getPool(token0, token1, int24(tickSpacing));
        address gauge = poolToGauge[pool];
        require(gauge != address(0), "No gauge");

        // Transfer and stake
        nonfungiblePositionManager.safeTransferFrom(nftOwner, address(this), tokenId);
        nonfungiblePositionManager.approve(gauge, tokenId);
        IGauge(gauge).deposit(tokenId);

        // Record ownership
        tokenIdToGauge[tokenId] = gauge;
        positionOwners[tokenId] = owner;
        isVaultPosition[tokenId] = fromVault;

        emit PositionStaked(tokenId, owner);
    }

    /// @notice Unstake a position
    function unstakePosition(uint256 tokenId) external nonReentrant {
        address owner = positionOwners[tokenId];
        bool fromVault = isVaultPosition[tokenId];
        
        // Check authorization
        require(
            (fromVault && msg.sender == address(vault)) ||
            (!fromVault && msg.sender == owner),
            "Not authorized"
        );

        address gauge = tokenIdToGauge[tokenId];
        require(gauge != address(0), "Not staked");

        // Claim final rewards and send to owner
        uint256 aeroBefore = aeroToken.balanceOf(address(this));
        IGauge(gauge).getReward(tokenId);
        uint256 aeroAmount = aeroToken.balanceOf(address(this)) - aeroBefore;
        
        if (aeroAmount > 0) {
            aeroToken.safeTransfer(owner, aeroAmount);
        }
        
        // Unstake
        IGauge(gauge).withdraw(tokenId);
        
        // Return NFT
        address returnTo = fromVault ? address(vault) : owner;
        nonfungiblePositionManager.safeTransferFrom(address(this), returnTo, tokenId);

        // Clean up
        delete tokenIdToGauge[tokenId];
        delete positionOwners[tokenId];
        delete isVaultPosition[tokenId];

        emit PositionUnstaked(tokenId, owner);
    }

    /// @notice Compound rewards for a position (THE KEY SIMPLIFICATION)
    /// @dev All-in-one: claim, swap, add liquidity
    function compoundRewards(
        uint256 tokenId,
        bytes calldata swapData0,
        bytes calldata swapData1,
        uint256 minAmount0,
        uint256 minAmount1,
        uint256 aeroSplitBps,
        uint256 deadline
    ) external nonReentrant {
        // Check authorization - only owner or vault can manually compound
        address owner = positionOwners[tokenId];
        bool fromVault = isVaultPosition[tokenId];
        require(
            msg.sender == owner || 
            (fromVault && msg.sender == address(vault)),
            "Not authorized"
        );

        address gauge = tokenIdToGauge[tokenId];
        require(gauge != address(0), "Not staked");

        // 1. Claim AERO rewards for this specific NFT
        uint256 aeroBefore = aeroToken.balanceOf(address(this));
        IGauge(gauge).getReward(tokenId);
        uint256 aeroAmount = aeroToken.balanceOf(address(this)) - aeroBefore;
        
        if (aeroAmount == 0) return;

        // 2. Get position details
        (,, address token0, address token1,,,,,,,,) = 
            nonfungiblePositionManager.positions(tokenId);

        // 3. Swap AERO to position tokens
        uint256 amount0;
        uint256 amount1;
        
        if (swapData0.length > 0) {
            (, amount0) = _routerSwap(
                RouterSwapParams(
                    aeroToken,
                    IERC20(token0),
                    (aeroAmount * aeroSplitBps) / 10000,
                    minAmount0,
                    swapData0
                )
            );
        }
        
        if (swapData1.length > 0) {
            (, amount1) = _routerSwap(
                RouterSwapParams(
                    aeroToken,
                    IERC20(token1),
                    aeroToken.balanceOf(address(this)),
                    minAmount1,
                    swapData1
                )
            );
        }

        // 4. Apply compound fees (same logic as AutoCompound)
        uint256 rewardX64 = totalRewardX64;
        uint256 maxAddAmount0 = amount0 * Q64 / (rewardX64 + Q64);
        uint256 maxAddAmount1 = amount1 * Q64 / (rewardX64 + Q64);

        // 5. Temporarily unstake to add liquidity
        IGauge(gauge).withdraw(tokenId);

        // 6. Add liquidity (fees implicitly stay in contract)
        IERC20(token0).safeApprove(address(nonfungiblePositionManager), 0);
        IERC20(token0).safeIncreaseAllowance(address(nonfungiblePositionManager), maxAddAmount0);
        IERC20(token1).safeApprove(address(nonfungiblePositionManager), 0);
        IERC20(token1).safeIncreaseAllowance(address(nonfungiblePositionManager), maxAddAmount1);
        
        (uint128 liquidity, uint256 amount0Added, uint256 amount1Added) = 
            nonfungiblePositionManager.increaseLiquidity(
                INonfungiblePositionManager.IncreaseLiquidityParams(
                    tokenId,
                    maxAddAmount0,
                    maxAddAmount1,
                    0,
                    0,
                    deadline
                )
            );

        // 6. Re-stake
        nonfungiblePositionManager.approve(gauge, tokenId);
        IGauge(gauge).deposit(tokenId);

        // 7. Return only slippage to position owner (fees stay in contract)
        uint256 leftover0 = maxAddAmount0 - amount0Added;
        uint256 leftover1 = maxAddAmount1 - amount1Added;
        
        if (leftover0 > 0) {
            IERC20(token0).safeTransfer(owner, leftover0);
        }
        if (leftover1 > 0) {
            IERC20(token1).safeTransfer(owner, leftover1);
        }

        emit RewardsCompounded(tokenId, aeroAmount, amount0Added, amount1Added);
    }

    /// @notice Simple reward claiming without compounding
    function claimRewards(uint256 tokenId) external nonReentrant {
        address owner = positionOwners[tokenId];
        bool fromVault = isVaultPosition[tokenId];
        
        // Check authorization: only owner or vault can claim
        require(
            msg.sender == owner || 
            (fromVault && msg.sender == address(vault)),
            "Not authorized"
        );
        
        address gauge = tokenIdToGauge[tokenId];
        require(gauge != address(0), "Not staked");
        
        // Claim and send to owner
        uint256 aeroBefore = aeroToken.balanceOf(address(this));
        IGauge(gauge).getReward(tokenId);
        uint256 aeroAmount = aeroToken.balanceOf(address(this)) - aeroBefore;
        
        if (aeroAmount > 0) {
            aeroToken.safeTransfer(owner, aeroAmount);
        }
    }

    /// @notice Execute V3Utils operation on staked position with optional AERO compounding
    /// @param tokenId The staked position to operate on
    /// @param instructions V3Utils instructions
    /// @param shouldCompound Whether to compound AERO rewards before restaking
    /// @param aeroSwapData0 Swap data for AERO->token0 if compounding
    /// @param aeroSwapData1 Swap data for AERO->token1 if compounding
    /// @param minAeroAmount0 Min amount of token0 from AERO swap if compounding
    /// @param minAeroAmount1 Min amount of token1 from AERO swap if compounding
    /// @param aeroSplitBps Basis points of AERO to swap to token0 (rest goes to token1)
    function executeV3UtilsWithOptionalCompound(
        uint256 tokenId,
        V3Utils.Instructions memory instructions,
        bool shouldCompound,
        bytes memory aeroSwapData0,
        bytes memory aeroSwapData1,
        uint256 minAeroAmount0,
        uint256 minAeroAmount1,
        uint256 aeroSplitBps
    ) public nonReentrant returns (uint256 newTokenId) {
        require(v3Utils != address(0), "V3Utils not configured");
        
        // Check authorization
        address owner = positionOwners[tokenId];
        bool fromVault = isVaultPosition[tokenId];
        require(
            msg.sender == owner || 
            (fromVault && msg.sender == address(vault)),
            "Not authorized"
        );

        address gauge = tokenIdToGauge[tokenId];
        require(gauge != address(0), "Not staked");

        // 1. Claim any pending AERO rewards
        uint256 aeroBefore = aeroToken.balanceOf(address(this));
        IGauge(gauge).getReward(tokenId);
        uint256 aeroAmount = aeroToken.balanceOf(address(this)) - aeroBefore;

        // 2. Unstake position from gauge
        IGauge(gauge).withdraw(tokenId);

        // 3. Execute V3Utils operation
        nonfungiblePositionManager.approve(v3Utils, tokenId);
        newTokenId = V3Utils(v3Utils).execute(tokenId, instructions);

        // Determine which tokenId to work with going forward
        uint256 tokenToStake = newTokenId != 0 ? newTokenId : tokenId;

        // 4. If requested and AERO available, compound it
        if (shouldCompound && aeroAmount > 0) {
            _compoundIntoPosition(
                tokenToStake,
                owner,
                aeroAmount,
                aeroSwapData0,
                aeroSwapData1,
                minAeroAmount0,
                minAeroAmount1,
                aeroSplitBps,
                instructions.deadline
            );
        } else if (aeroAmount > 0) {
            // Send unclaimed AERO to owner
            aeroToken.safeTransfer(owner, aeroAmount);
        }

        // 5. Restake the position (same gauge - pool doesn't change)
        nonfungiblePositionManager.approve(gauge, tokenToStake);
        IGauge(gauge).deposit(tokenToStake);

        // 6. Update ownership tracking
        if (newTokenId != 0) {
            // Clean up old tokenId
            delete tokenIdToGauge[tokenId];
            delete positionOwners[tokenId];
            delete isVaultPosition[tokenId];
            
            // Set mappings for new tokenId
            tokenIdToGauge[tokenToStake] = gauge;
            positionOwners[tokenToStake] = owner;
            isVaultPosition[tokenToStake] = fromVault;
        }

        emit PositionStaked(tokenToStake, owner);

        return newTokenId;
    }

    /// @notice Internal function to compound AERO into a position
    function _compoundIntoPosition(
        uint256 tokenId,
        address owner,
        uint256 aeroAmount,
        bytes memory swapData0,
        bytes memory swapData1,
        uint256 minAmount0,
        uint256 minAmount1,
        uint256 aeroSplitBps,
        uint256 deadline
    ) internal {
        // Get position details
        (,, address token0, address token1,,,,,,,,) = 
            nonfungiblePositionManager.positions(tokenId);

        // Swap AERO to position tokens
        uint256 amount0;
        uint256 amount1;
        
        if (swapData0.length > 0) {
            (, amount0) = _routerSwap(
                RouterSwapParams(
                    aeroToken,
                    IERC20(token0),
                    (aeroAmount * aeroSplitBps) / 10000,
                    minAmount0,
                    swapData0
                )
            );
        }
        
        if (swapData1.length > 0) {
            (, amount1) = _routerSwap(
                RouterSwapParams(
                    aeroToken,
                    IERC20(token1),
                    aeroToken.balanceOf(address(this)),
                    minAmount1,
                    swapData1
                )
            );
        }

        // Apply fees
        uint256 rewardX64 = totalRewardX64;
        uint256 maxAddAmount0 = amount0 * Q64 / (rewardX64 + Q64);
        uint256 maxAddAmount1 = amount1 * Q64 / (rewardX64 + Q64);

        // Add liquidity with fee-adjusted amounts
        IERC20(token0).safeApprove(address(nonfungiblePositionManager), 0);
        IERC20(token0).safeIncreaseAllowance(address(nonfungiblePositionManager), maxAddAmount0);
        IERC20(token1).safeApprove(address(nonfungiblePositionManager), 0);
        IERC20(token1).safeIncreaseAllowance(address(nonfungiblePositionManager), maxAddAmount1);
        
        (uint128 liquidity, uint256 amount0Added, uint256 amount1Added) = 
            nonfungiblePositionManager.increaseLiquidity(
                INonfungiblePositionManager.IncreaseLiquidityParams(
                    tokenId,
                    maxAddAmount0,
                    maxAddAmount1,
                    0,
                    0,
                    deadline
                )
            );

        // Return only slippage to position owner (fees stay in contract)
        uint256 leftover0 = maxAddAmount0 - amount0Added;
        uint256 leftover1 = maxAddAmount1 - amount1Added;
        
        if (leftover0 > 0) {
            IERC20(token0).safeTransfer(owner, leftover0);
        }
        if (leftover1 > 0) {
            IERC20(token1).safeTransfer(owner, leftover1);
        }

        emit RewardsCompounded(tokenId, aeroAmount, amount0Added, amount1Added);
    }


    /// @notice Add liquidity to a staked position with optional token swaps
    /// @param tokenId The staked position to add liquidity to
    /// @param params Parameters for V3Utils.swapAndIncreaseLiquidity
    function swapAndIncreaseStakedPosition(
        uint256 tokenId,
        V3Utils.SwapAndIncreaseLiquidityParams calldata params
    ) external payable nonReentrant returns (uint128 liquidity, uint256 amount0, uint256 amount1) {
        require(v3Utils != address(0), "V3Utils not configured");
        
        // Check authorization
        address owner = positionOwners[tokenId];
        bool fromVault = isVaultPosition[tokenId];
        require(
            msg.sender == owner || 
            (fromVault && msg.sender == address(vault)),
            "Not authorized"
        );
        
        address gauge = tokenIdToGauge[tokenId];
        require(gauge != address(0), "Not staked");
        
        // Get position tokens
        (,, address token0, address token1,,,,,,,,) = nonfungiblePositionManager.positions(tokenId);
        
        // Claim and send AERO rewards to owner before unstaking
        uint256 aeroBefore = aeroToken.balanceOf(address(this));
        IGauge(gauge).getReward(tokenId);
        uint256 aeroAmount = aeroToken.balanceOf(address(this)) - aeroBefore;
        if (aeroAmount > 0) {
            aeroToken.safeTransfer(owner, aeroAmount);
        }
        
        // Transfer tokens from sender to this contract
        if (params.amount0 > 0) {
            IERC20(token0).safeTransferFrom(msg.sender, address(this), params.amount0);
        }
        if (params.amount1 > 0) {
            IERC20(token1).safeTransferFrom(msg.sender, address(this), params.amount1);
        }
        
        // Approve V3Utils
        if (params.amount0 > 0) {
            IERC20(token0).safeApprove(v3Utils, 0);
            IERC20(token0).safeIncreaseAllowance(v3Utils, params.amount0);
        }
        if (params.amount1 > 0) {
            IERC20(token1).safeApprove(v3Utils, 0);
            IERC20(token1).safeIncreaseAllowance(v3Utils, params.amount1);
        }
        
        // Unstake position
        IGauge(gauge).withdraw(tokenId);
        
        // Call V3Utils.swapAndIncreaseLiquidity (forward ETH if sent)
        (liquidity, amount0, amount1) = V3Utils(v3Utils).swapAndIncreaseLiquidity{value: msg.value}(params);
        
        // Restake position
        nonfungiblePositionManager.approve(gauge, tokenId);
        IGauge(gauge).deposit(tokenId);
        
        // Note: V3Utils already handles returning leftover tokens to params.recipient
        // No need to handle leftovers here as they've already been sent
        
        emit SwapAndIncreaseLiquidity(tokenId, liquidity, amount0, amount1);
        
        return (liquidity, amount0, amount1);
    }

    /// @notice Migrate a staked position to the vault for collateralized borrowing
    /// @param tokenId The staked position to migrate
    /// @param recipient The recipient address in the vault (usually msg.sender)
    /// @dev This unstakes the position and deposits it into the vault in one transaction
    function migrateToVault(uint256 tokenId, address recipient) external nonReentrant {
        address owner = positionOwners[tokenId];
        require(owner == msg.sender, "Not position owner");
        require(!isVaultPosition[tokenId], "Already a vault position");
        
        address gauge = tokenIdToGauge[tokenId];
        require(gauge != address(0), "Not staked");
        
        // Claim final rewards and send to owner
        uint256 aeroBefore = aeroToken.balanceOf(address(this));
        IGauge(gauge).getReward(tokenId);
        uint256 aeroAmount = aeroToken.balanceOf(address(this)) - aeroBefore;
        
        if (aeroAmount > 0) {
            aeroToken.safeTransfer(owner, aeroAmount);
        }
        
        // Unstake from gauge
        IGauge(gauge).withdraw(tokenId);
        
        // Approve vault to take the NFT
        nonfungiblePositionManager.approve(address(vault), tokenId);
        
        // Transfer to vault using safeTransferFrom with recipient encoded
        nonfungiblePositionManager.safeTransferFrom(
            address(this), 
            address(vault), 
            tokenId, 
            abi.encode(recipient)
        );
        
        // Clean up mappings
        delete tokenIdToGauge[tokenId];
        delete positionOwners[tokenId];
        delete isVaultPosition[tokenId];
        
        emit PositionUnstaked(tokenId, owner);
        emit PositionMigratedToVault(tokenId, owner);
    }

    /// @notice Transform a staked position using an approved transformer (e.g., AutoRange, AutoCompound)
    /// @param tokenId The staked position to transform
    /// @param transformer The transformer contract to use
    /// @param data The encoded function call for the transformer
    /// @return newTokenId The tokenId after transformation (may be same or different)
    function transform(
        uint256 tokenId, 
        address transformer, 
        bytes calldata data
    ) external nonReentrant returns (uint256 newTokenId) {
        // Check authorization
        address owner = positionOwners[tokenId];
        bool fromVault = isVaultPosition[tokenId];
        require(
            msg.sender == owner || 
            (fromVault && msg.sender == address(vault)) ||
            msg.sender == transformer || // Allow transformer to call (for AutoCompound.executeWithGauge)
            transformApprovals[owner][tokenId][msg.sender], // Check if approved transformer
            "Not authorized"
        );
        
        // Validate transformer
        require(transformerAllowList[transformer], "Transformer not allowed");
        require(transformedTokenId == 0, "Reentrancy");
        
        // Set reentrancy guard
        transformedTokenId = tokenId;
        
        // Save state before transform
        address gauge = tokenIdToGauge[tokenId];
        require(gauge != address(0), "Not staked");
        
        // 1. Always claim pending AERO rewards
        uint256 aeroBefore = aeroToken.balanceOf(address(this));
        IGauge(gauge).getReward(tokenId);
        uint256 aeroAmount = aeroToken.balanceOf(address(this)) - aeroBefore;
        
        // Check if this is AutoCompound
        bytes4 selector = bytes4(data[:4]);
        bool isAutoCompound = selector == bytes4(keccak256("executeForGauge((uint256,uint256,bytes,bytes,uint256,uint256,uint256,uint256))"));
        
        bytes memory callData = data;
        
        if (isAutoCompound) {
            // For AutoCompound: transfer AERO and re-encode with actual amount
            if (aeroAmount > 0) {
                aeroToken.safeTransfer(transformer, aeroAmount);
            }
            
            // Re-encode the call data with the actual aeroAmount
            // Decode the original params (skip the selector and tokenId, insert aeroAmount)
            (uint256 originalTokenId, , bytes memory swapData0, bytes memory swapData1, 
             uint256 minAmount0, uint256 minAmount1, uint256 aeroSplitBps, uint256 deadline) = 
                abi.decode(data[4:], (uint256, uint256, bytes, bytes, uint256, uint256, uint256, uint256));
            
            // Re-encode with the actual aeroAmount
            callData = abi.encodeWithSelector(
                selector,
                originalTokenId,
                aeroAmount,
                swapData0,
                swapData1,
                minAmount0,
                minAmount1,
                aeroSplitBps,
                deadline
            );
        } else if (aeroAmount > 0) {
            // For other transformers: send AERO to position owner
            aeroToken.safeTransfer(owner, aeroAmount);
        }
        
        // 2. Unstake from gauge
        IGauge(gauge).withdraw(tokenId);
        
        // 3. Execute transform
        nonfungiblePositionManager.approve(transformer, tokenId);
        (bool success,) = transformer.call(callData);
        require(success, "Transform failed");
        
        // 4. Get new tokenId (may have changed)
        newTokenId = transformedTokenId;
        
        // Verify ownership
        require(nonfungiblePositionManager.ownerOf(newTokenId) == address(this), 
                "Position not returned");
        
        // Clear approval
        nonfungiblePositionManager.approve(address(0), newTokenId);
        
        // 5. Re-stake to same gauge
        nonfungiblePositionManager.approve(gauge, newTokenId);
        IGauge(gauge).deposit(newTokenId);
        
        // 6. Update mappings if tokenId changed
        if (newTokenId != tokenId) {
            // Transfer approvals to new tokenId
            // Note: This is a design choice - we transfer approvals to maintain continuity
            // Alternatively, we could require re-approval for the new tokenId
            
            // Clean up old tokenId
            delete tokenIdToGauge[tokenId];
            delete positionOwners[tokenId];
            delete isVaultPosition[tokenId];
            
            // Set up new tokenId
            tokenIdToGauge[newTokenId] = gauge;
            positionOwners[newTokenId] = owner;
            isVaultPosition[newTokenId] = fromVault;
        }
        
        // Clear reentrancy guard
        transformedTokenId = 0;
        
        emit PositionTransformed(tokenId, newTokenId, owner);
    }

    function onERC721Received(address, address from, uint256 tokenId, bytes calldata) 
        external override returns (bytes4) {
        require(msg.sender == address(nonfungiblePositionManager), "Only NPM");
        
        // Handle transform case - AutoRange sends new NFT back
        if (transformedTokenId != 0 && from == address(this)) {
            transformedTokenId = tokenId;
        }
        
        return IERC721Receiver.onERC721Received.selector;
    }
    
    /**
     * @notice Set compound reward fee (onlyOwner)
     * @param _totalRewardX64 Fee percentage in X64 format (max 5%)
     */
    function setReward(uint64 _totalRewardX64) external onlyOwner {
        require(_totalRewardX64 <= MAX_REWARD_X64, "Fee too high");
        totalRewardX64 = _totalRewardX64;
        emit RewardUpdated(msg.sender, _totalRewardX64);
    }
    
    /**
     * @notice Set fee withdrawer address (onlyOwner)
     * @param _feeWithdrawer Address that can withdraw fees
     */
    function setFeeWithdrawer(address _feeWithdrawer) external onlyOwner {
        feeWithdrawer = _feeWithdrawer;
        emit FeeWithdrawerUpdated(_feeWithdrawer);
    }
    
    /**
     * @notice Withdraw accumulated compound fees
     * @param tokens Array of token addresses to withdraw
     * @param to Recipient address
     */
    function withdrawFees(address[] calldata tokens, address to) external nonReentrant {
        require(msg.sender == feeWithdrawer, "Not fee withdrawer");
        for (uint i = 0; i < tokens.length; i++) {
            uint256 balance = IERC20(tokens[i]).balanceOf(address(this));
            if (balance > 0) {
                IERC20(tokens[i]).safeTransfer(to, balance);
                emit FeesWithdrawn(tokens[i], to, balance);
            }
        }
    }
    
    // Events for compound fee management
    event RewardUpdated(address account, uint64 totalRewardX64);
    event FeeWithdrawerUpdated(address withdrawer);
    event FeesWithdrawn(address token, address to, uint256 amount);
}
