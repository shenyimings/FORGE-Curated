// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

interface ISBold {
    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/

    struct SPConfig {
        address addr;
        uint96 weight;
    }

    struct SP {
        address sp;
        uint96 weight;
        address coll;
    }

    struct CollBalance {
        address addr;
        uint256 balance;
    }

    struct SwapDataWithColl {
        address addr;
        uint256 balance;
        uint256 collInBold;
        bytes data;
    }

    struct SwapData {
        address sp;
        uint256 balance;
        bytes data;
    }

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidConfiguration();

    error ExecutionFailed(bytes data);

    error CollOverLimit();

    error InsufficientAmount(uint256 amountOut);

    error InvalidDataArray();

    error InvalidSPLength();

    error ZeroWeight();

    error InvalidTotalWeight();

    error DuplicateAddress();

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event PriceOracleSet(address addr);

    event VaultSet(address account);

    event FeesSet(uint256 feeBps, uint256 swapFeeBps);

    event MaxCollValueSet(uint256 value);

    event SwapAdapterSet(address addr);

    event RewardSet(uint256 value);

    event MaxSlippageSet(uint256 value);

    event Swap(
        address indexed adapter,
        address indexed src,
        address indexed dst,
        uint256 amountIn,
        uint256 amountOut,
        uint256 minOut
    );

    event Rebalance(SPConfig[] _sps);

    /*//////////////////////////////////////////////////////////////
                                 FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function setPriceOracle(address _priceOracle) external;

    function setVault(address _vault) external;
}
