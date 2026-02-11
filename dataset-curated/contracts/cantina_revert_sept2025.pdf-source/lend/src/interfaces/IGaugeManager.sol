// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

interface IGaugeManager {
    // Events
    event PositionStaked(uint256 indexed tokenId, address indexed owner);
    event PositionUnstaked(uint256 indexed tokenId, address indexed owner);
    event RewardsCompounded(uint256 indexed tokenId, uint256 aeroAmount, uint256 amount0, uint256 amount1);

    // Core functions
    function stakePosition(uint256 tokenId) external;
    function unstakePosition(uint256 tokenId) external;
    
    // Compounding
    function compoundRewards(
        uint256 tokenId,
        bytes calldata swapData0,
        bytes calldata swapData1,
        uint256 minAmount0,
        uint256 minAmount1,
        uint256 deadline
    ) external;
    
    // Simple claim without compounding
    function claimRewards(uint256 tokenId) external;
    
    // Operator management
    function setOperator(address operator, bool approved) external;
    
    // Transform function for AutoRange integration
    function transform(uint256 tokenId, address transformer, bytes calldata data) external returns (uint256 newTokenId);
    
    // View functions
    function positionOwners(uint256 tokenId) external view returns (address);
    function isVaultPosition(uint256 tokenId) external view returns (bool);
    function tokenIdToGauge(uint256 tokenId) external view returns (address);
    function poolToGauge(address pool) external view returns (address);
    function operators(address user, address operator) external view returns (bool);
    
    // Admin functions
    function setGauge(address pool, address gauge) external;
    function setTransformer(address transformer, bool active) external;
}