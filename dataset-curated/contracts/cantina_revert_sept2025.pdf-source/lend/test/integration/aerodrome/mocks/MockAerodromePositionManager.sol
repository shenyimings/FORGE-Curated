// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "../../../../src/interfaces/aerodrome/IAerodromeNonfungiblePositionManager.sol";

contract MockAerodromePositionManager is ERC721Enumerable, IAerodromeNonfungiblePositionManager {
    struct Position {
        uint96 nonce;
        address operator;
        address token0;
        address token1;
        uint24 tickSpacing; // stored as fee but represents tickSpacing
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;
        uint256 feeGrowthInside0LastX128;
        uint256 feeGrowthInside1LastX128;
        uint128 tokensOwed0;
        uint128 tokensOwed1;
    }

    mapping(uint256 => Position) internal _positions;
    address public immutable override factory;
    address public immutable override WETH9;

    constructor(address _factory, address _weth) ERC721("Aerodrome Positions NFT", "AERO-POS") {
        factory = _factory;
        WETH9 = _weth;
    }

    function positions(uint256 tokenId) external view override returns (
        uint96 nonce,
        address operator,
        address token0,
        address token1,
        uint24 fee, // actually tickSpacing in Aerodrome
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity,
        uint256 feeGrowthInside0LastX128,
        uint256 feeGrowthInside1LastX128,
        uint128 tokensOwed0,
        uint128 tokensOwed1
    ) {
        Position memory position = _positions[tokenId];
        return (
            position.nonce,
            position.operator,
            position.token0,
            position.token1,
            position.tickSpacing,
            position.tickLower,
            position.tickUpper,
            position.liquidity,
            position.feeGrowthInside0LastX128,
            position.feeGrowthInside1LastX128,
            position.tokensOwed0,
            position.tokensOwed1
        );
    }

    function mint(address to, uint256 tokenId) external {
        _mint(to, tokenId);
    }

    function setPosition(
        uint256 tokenId,
        address token0,
        address token1,
        int24 tickSpacing,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity
    ) external {
        _positions[tokenId] = Position({
            nonce: 0,
            operator: address(0),
            token0: token0,
            token1: token1,
            tickSpacing: uint24(tickSpacing),
            tickLower: tickLower,
            tickUpper: tickUpper,
            liquidity: liquidity,
            feeGrowthInside0LastX128: 0,
            feeGrowthInside1LastX128: 0,
            tokensOwed0: 0,
            tokensOwed1: 0
        });
    }
    
    function setTokensOwed(uint256 tokenId, uint128 tokensOwed0, uint128 tokensOwed1) external {
        _positions[tokenId].tokensOwed0 = tokensOwed0;
        _positions[tokenId].tokensOwed1 = tokensOwed1;
    }

    // Implement required but unused interface functions
    function createAndInitializePoolIfNecessary(address, address, uint24, uint160) external payable override returns (address) {
        revert("Not implemented");
    }

    function mint(MintParams calldata) external payable override returns (uint256, uint128, uint256, uint256) {
        revert("Not implemented");
    }

    function increaseLiquidity(IncreaseLiquidityParams calldata) external payable override returns (uint128, uint256, uint256) {
        revert("Not implemented");
    }

    function decreaseLiquidity(DecreaseLiquidityParams calldata) external payable override returns (uint256, uint256) {
        revert("Not implemented");
    }

    function collect(CollectParams calldata) external payable override returns (uint256, uint256) {
        revert("Not implemented");
    }

    function burn(uint256) external payable override {
        revert("Not implemented");
    }

    function multicall(bytes[] calldata) external payable returns (bytes[] memory) {
        revert("Not implemented");
    }

    function permit(address, uint256, uint256, uint8, bytes32, bytes32) external payable override {
        revert("Not implemented");
    }

    function uniswapV3MintCallback(uint256, uint256, bytes calldata) external {
        revert("Not implemented");
    }

    function selfPermit(address, uint256, uint256, uint8, bytes32, bytes32) external payable {
        revert("Not implemented");
    }

    function selfPermitIfNecessary(address, uint256, uint256, uint8, bytes32, bytes32) external payable {
        revert("Not implemented");
    }

    function selfPermitAllowed(address, uint256, uint256, uint8, bytes32, bytes32) external payable {
        revert("Not implemented");
    }

    function selfPermitAllowedIfNecessary(address, uint256, uint256, uint8, bytes32, bytes32) external payable {
        revert("Not implemented");
    }

    function multicall(uint256, bytes[] calldata) external payable returns (bytes[] memory) {
        revert("Not implemented");
    }

    function DOMAIN_SEPARATOR() external view override returns (bytes32) {
        return bytes32(0);
    }

    function PERMIT_TYPEHASH() external pure override returns (bytes32) {
        return bytes32(0);
    }

    function sweepToken(address, uint256, address) external payable override {
        revert("Not implemented");
    }

    function refundETH() external payable override {
        revert("Not implemented");
    }

    function unwrapWETH9(uint256, address) external payable override {
        revert("Not implemented");
    }
}