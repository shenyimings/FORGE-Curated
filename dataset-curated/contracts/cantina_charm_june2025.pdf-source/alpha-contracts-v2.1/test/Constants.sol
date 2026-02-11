pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

library Constants {
    address constant ZERO_ADDR = address(0);
    int24 constant MIN_TICK_MOVE = 0;
    int24 constant MAX_TWAP_DEVIATION = 100;
    uint32 constant TWAP_DURATION = 60;
    uint256 constant PROTOCOL_FEE = 30000;
    uint256 constant MAX_TOTAL_SUPPLY = 10 ** 20;

    // Uniswap v3 factory on Rinkeby and other chains according to https://docs.uniswap.org/protocol/reference/deployments
    address constant FACTORY_ADDRESS = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address constant SWAP_ROUTER_ADDRESS = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

    address constant USDC_ADDRESS = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant WETH_ADDRESS = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant DAI_ADDRESS = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    IERC20 constant USDC = IERC20(USDC_ADDRESS);
    IERC20 constant WETH = IERC20(WETH_ADDRESS);
    IERC20 constant DAI = IERC20(DAI_ADDRESS);

    // TODO: use key from env
    // Fork related constants
    string constant MAINNET_RPC_URL = "https://eth-mainnet.g.alchemy.com/v2/161WAOtSAE5jevNI4o4JUYgdtP9lOUoe";
    uint256 constant BLOCK_NUMBER = 17073835;
    uint24 constant POOL_FEE = 3000;
    int24 constant MIN_TICK = -887272;
    int24 constant MAX_TICK = 887272;
}
