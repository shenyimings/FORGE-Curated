// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19;
import "../../../src/LevelMinting.sol";

// This contract inherits from LevelMinting and wraps the internal functions _mint and
// _redeem in an external function so that they can be tested.
contract LevelMintingChild is LevelMinting {
    constructor(
        IlvlUSD _lvlusd,
        address[] memory _assets,
        address[] memory _oracles,
        address[] memory _reserves,
        uint256[] memory _ratios,
        address _admin,
        uint256 _maxMintPerBlock,
        uint256 _maxRedeemPerBlock
    )
        LevelMinting(
            _lvlusd,
            _assets,
            _oracles,
            _reserves,
            _ratios,
            _admin,
            _maxMintPerBlock,
            _maxRedeemPerBlock
        )
    {}

    function __mint(Order calldata order, Route calldata route) external {
        super._mint(order, route);
    }

    function __redeem(Order calldata order) external {
        super._redeem(order);
        lvlusd.burnFrom(order.benefactor, order.lvlusd_amount);
    }
}
