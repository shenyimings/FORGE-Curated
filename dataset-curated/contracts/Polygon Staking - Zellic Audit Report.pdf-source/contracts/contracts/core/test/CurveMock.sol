// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title Curve Mock
 * @notice Basic mock contract for UI to locally test token swaps
 */
contract CurveMock {
    IERC20[2] public tokens;

    constructor(address _tokenA, address _tokenB) {
        tokens[0] = IERC20(_tokenA);
        tokens[1] = IERC20(_tokenB);
    }

    function get_dy(int128, int128, uint256 _amount) external pure returns (uint256) {
        return _amount;
    }

    function exchange(
        int128 _i,
        int128 _j,
        uint256 _dx,
        uint256,
        address _receiver
    ) external returns (uint256) {
        require(_i < 2 && _j < 2, "Invalid token indexes");
        require(_i != _j, "Cannot send same token");

        address receiver = msg.sender;
        if (_receiver != address(0)) {
            receiver = _receiver;
        }

        uint i = 0;
        uint j = 0;

        if (_i == 0) {
            j = 1;
        }

        if (_j == 0) {
            i = 1;
        }

        tokens[i].transferFrom(msg.sender, address(this), _dx);
        tokens[j].transfer(_receiver, _dx);

        return _dx;
    }
}
