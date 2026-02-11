// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/**
 * @title Liquid Staking Derivative Index Adapter
 * @notice Base adapter contract used to retrieve information on the LSD tokens held in the index pool
 */
abstract contract LSDIndexAdapter is Initializable, UUPSUpgradeable, OwnableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    IERC20Upgradeable public token;
    address public indexPool;

    function __LiquidSDAdapter_init(address _token, address _indexPool) public onlyInitializing {
        token = IERC20Upgradeable(_token);
        token.safeApprove(_indexPool, type(uint256).max);
        indexPool = _indexPool;
        __Ownable_init();
        __UUPSUpgradeable_init();
    }

    /**
     * @notice returns the total underlying value of deposits in this adapter
     * @return total deposits amount
     */
    function getTotalDeposits() public view returns (uint256) {
        return getUnderlyingByLSD(token.balanceOf(address(this)));
    }

    /**
     * @notice returns the total amount of deposits in this adapter
     * @return total underlying amount
     */
    function getTotalDepositsLSD() public view returns (uint256) {
        return token.balanceOf(address(this));
    }

    /**
     * @notice returns the underlying amount that corresponds to an LSD amount
     * @param _lsdAmount amount of LSD tokens
     * @return underlying amount
     */
    function getUnderlyingByLSD(uint256 _lsdAmount) public view returns (uint256) {
        return (_lsdAmount * getExchangeRate()) / 1e18;
    }

    /**
     * @notice returns the LSD amount that corresponds to an underlying amount
     * @param _underlyingAmount underlying amount
     * @return LSD amount
     */
    function getLSDByUnderlying(uint256 _underlyingAmount) public view returns (uint256) {
        return (_underlyingAmount * 1e18) / getExchangeRate();
    }

    /**
     * @notice returns the exchange rate between the underlying asset and this adapter's token
     * @return exchange rate
     */
    function getExchangeRate() public view virtual returns (uint256);

    /**
     * @dev Checks authorization for contract upgrades
     */
    function _authorizeUpgrade(address) internal override onlyOwner {}

    /**
     * @dev Allows future contract versions to add new variables without shifting
     * down storage in the inheritance chain
     */
    uint256[10] private __gap;
}
