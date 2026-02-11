// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

import "../tokens/base/ERC677Upgradeable.sol";

/**
 * @title Staking Rewards Pool Base
 * @dev Staking Rewards Pool without UUPSUpgradeable and OwnableUpgradeable
 */
abstract contract StakingRewardsPoolBase is ERC677Upgradeable {
    uint256 private constant DEAD_SHARES = 10 ** 3;

    IERC20Upgradeable public token;

    mapping(address => uint256) private shares;
    uint256 public totalShares;

    function __StakingRewardsPoolBase_init(
        address _token,
        string memory _derivativeTokenName,
        string memory _derivativeTokenSymbol
    ) public onlyInitializing {
        __ERC677_init(_derivativeTokenName, _derivativeTokenSymbol, 0);
        token = IERC20Upgradeable(_token);
    }

    /**
     * @notice returns the total supply of staking derivative tokens
     * @return total supply
     */
    function totalSupply() public view override returns (uint256) {
        return _totalStaked();
    }

    /**
     * @notice returns an account's stake balance
     * @param _account account address
     * @return account's stake balance
     */
    function balanceOf(address _account) public view override returns (uint256) {
        uint256 balance = getStakeByShares(shares[_account]);
        if (balance < 100) {
            return 0;
        } else {
            return balance;
        }
    }

    /**
     * @notice returns an account's share balance
     * @param _account account address
     * @return account's share balance
     */
    function sharesOf(address _account) public view returns (uint256) {
        return shares[_account];
    }

    /**
     * @notice returns the amount of shares that corresponds to a staked amount
     * @param _amount staked amount
     * @return amount of shares
     */
    function getSharesByStake(uint256 _amount) public view returns (uint256) {
        uint256 totalStaked = _totalStaked();
        if (totalStaked == 0) {
            return _amount;
        } else {
            return (_amount * totalShares) / totalStaked;
        }
    }

    /**
     * @notice returns the amount of stake that corresponds to an amount of shares
     * @param _amount shares amount
     * @return amount of stake
     */
    function getStakeByShares(uint256 _amount) public view returns (uint256) {
        if (totalShares == 0) {
            return _amount;
        } else {
            return (_amount * _totalStaked()) / totalShares;
        }
    }

    /**
     * @notice transfers shares from one account to another
     * @param _recipient account to transfer to
     * @param _sharesAmount amount of shares to transfer
     */
    function transferShares(address _recipient, uint256 _sharesAmount) external returns (bool) {
        _transferShares(msg.sender, _recipient, _sharesAmount);
        return true;
    }

    /**
     * @notice transfers shares from one account to another
     * @param _sender account to transfer from
     * @param _recipient account to transfer to
     * @param _sharesAmount amount of shares to transfer
     */
    function transferSharesFrom(
        address _sender,
        address _recipient,
        uint256 _sharesAmount
    ) external returns (bool) {
        uint256 tokensAmount = getStakeByShares(_sharesAmount);
        _spendAllowance(_sender, msg.sender, tokensAmount);
        _transferShares(_sender, _recipient, _sharesAmount);
        return true;
    }

    /**
     * @notice returns the total amount of assets staked in the pool
     * @return total staked amount
     */
    function _totalStaked() internal view virtual returns (uint256);

    /**
     * @notice transfers a stake balance from one account to another
     * @param _sender account to transfer from
     * @param _recipient account to transfer to
     * @param _amount amount to transfer
     */
    function _transfer(
        address _sender,
        address _recipient,
        uint256 _amount
    ) internal virtual override {
        uint256 sharesToTransfer = getSharesByStake(_amount);

        require(_sender != address(0), "Transfer from the zero address");
        require(_recipient != address(0), "Transfer to the zero address");
        require(shares[_sender] >= sharesToTransfer, "Transfer amount exceeds balance");

        shares[_sender] -= sharesToTransfer;
        shares[_recipient] += sharesToTransfer;

        emit Transfer(_sender, _recipient, _amount);
    }

    /**
     * @notice transfers shares from one account to another
     * @param _sender account to transfer from
     * @param _recipient account to transfer to
     * @param _sharesAmount amount of shares to transfer
     */
    function _transferShares(
        address _sender,
        address _recipient,
        uint256 _sharesAmount
    ) internal virtual {
        require(_sender != address(0), "Transfer from the zero address");
        require(_recipient != address(0), "Transfer to the zero address");
        require(shares[_sender] >= _sharesAmount, "Transfer amount exceeds balance");

        shares[_sender] -= _sharesAmount;
        shares[_recipient] += _sharesAmount;

        emit Transfer(_sender, _recipient, getStakeByShares(_sharesAmount));
    }

    /**
     * @notice mints new shares to an account
     * @dev takes a stake amount and calculates the amount of shares it corresponds to
     * @param _recipient account to mint shares for
     * @param _amount stake amount
     */
    function _mint(address _recipient, uint256 _amount) internal override {
        uint256 sharesToMint = getSharesByStake(_amount);
        _mintShares(_recipient, sharesToMint);

        emit Transfer(address(0), _recipient, _amount);
    }

    /**
     * @notice mints new shares to an account
     * @param _recipient account to mint shares for
     * @param _amount shares amount
     */
    function _mintShares(address _recipient, uint256 _amount) internal {
        require(_recipient != address(0), "Mint to the zero address");

        if (totalShares == 0) {
            shares[address(0)] = DEAD_SHARES;
            totalShares = DEAD_SHARES;
            _amount -= DEAD_SHARES;
        }

        totalShares += _amount;
        shares[_recipient] += _amount;
    }

    /**
     * @notice burns shares belonging to an account
     * @dev takes a stake amount and calculates the amount of shares it corresponds to
     * @param _account account to burn shares for
     * @param _amount stake amount
     */
    function _burn(address _account, uint256 _amount) internal override {
        uint256 sharesToBurn = getSharesByStake(_amount);

        require(_account != address(0), "Burn from the zero address");
        require(shares[_account] >= sharesToBurn, "Burn amount exceeds balance");

        totalShares -= sharesToBurn;
        shares[_account] -= sharesToBurn;

        emit Transfer(_account, address(0), _amount);
    }
}
