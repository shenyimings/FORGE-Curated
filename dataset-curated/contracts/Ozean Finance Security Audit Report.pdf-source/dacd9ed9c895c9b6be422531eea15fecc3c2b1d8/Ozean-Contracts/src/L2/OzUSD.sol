// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {IERC20} from "openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Initializable} from "openzeppelin/contracts/proxy/utils/Initializable.sol";

/// @title  Ozean USD (ozUSD) Token Contract
/// @notice This contract implements a rebasing token (ozUSD), where token balances are dynamic and calculated
///         based on shares controlled by each account. The total pooled USDX (protocol-controlled USDX) determines the
///         total balances; meaning that any USDX sent to this contract automatically rebases all user balances.
///         1 USDX == 1 ozUSD.
/// @dev    This contract does not fully comply with the ERC20 standard as rebasing events do not emit `Transfer`
/// events.
///         This contract is inspired by Lido's stETH contract:
/// https://vscode.blockscan.com/ethereum/0x17144556fd3424edc8fc8a4c940b2d04936d17eb
contract OzUSD is IERC20, ReentrancyGuard, Initializable {
    string public constant name = "Ozean USD";
    string public constant symbol = "ozUSD";
    uint8 public constant decimals = 18;
    uint256 private totalShares;

    /// @notice A mapping from addresses to shares controlled by each account.
    /// @dev    ozUSD balances are dynamic and are calculated based on the accounts' shares and the total amount of
    ///         USDX controlled by the protocol. Account shares aren't normalized, so the contract also stores the
    ///         sum of all shares to calculate each account's token balance which equals to:
    ///         shares[account] * _getTotalPooledUSDX() / totalShares
    mapping(address => uint256) private shares;

    /// @notice A mapping to track token allowances for delegated spending.
    /// @dev    Allowances are denominated in tokens, not token shares.
    mapping(address => mapping(address => uint256)) private allowances;

    /// @notice An executed shares transfer from `sender` to `recipient`.
    /// @param  from The address the shares are leaving from.
    /// @param  to The address receiving the shares.
    /// @param  sharesValue The number of shares being transferred.
    /// @dev    This is emitted in pair with an ERC20-defined `Transfer` event.
    event TransferShares(address indexed from, address indexed to, uint256 sharesValue);

    /// @notice An executed `burnShares` request
    /// @param  account holder of the burnt shares.
    /// @param  preRebaseTokenAmount amount of ozUSD the burnt shares corresponded to before the burn.
    /// @param  postRebaseTokenAmount amount of ozUSD the burnt shares corresponded to after the burn.
    /// @param  sharesAmount amount of burnt shares.
    /// @dev    Reports simultaneously burnt shares amount and corresponding ozUSD amount.
    ///         The ozUSD amount is calculated twice: before and after the burning incurred rebase.
    event SharesBurnt(
        address indexed account, uint256 preRebaseTokenAmount, uint256 postRebaseTokenAmount, uint256 sharesAmount
    );

    /// @notice An event for distribution of yield (in the form of USDX) to all participants.
    /// @param  _previousTotalBalance The total amount of USDX held by the contract before rebasing.
    /// @param  _newTotalBalance The total amount of USDX held by the contract after rebasing.
    event YieldDistributed(uint256 _previousTotalBalance, uint256 _newTotalBalance);

    /// SETUP ///

    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the contract with a specific amount of shares.
    /// @param  _sharesAmount The number of shares to initialize.
    /// @dev    Requires the sender to send USDX equal to the number of shares specified in `_sharesAmount`.
    function initialize(uint256 _sharesAmount) external payable initializer nonReentrant {
        require(msg.value == _sharesAmount, "OzUSD: Incorrect value.");
        _mintShares(address(0xdead), _sharesAmount);
        _emitTransferAfterMintingShares(address(0xdead), _sharesAmount);
    }

    /// EXTERNAL ///

    receive() external payable {}

    /// @notice Distributes the yield to the protocol by updating the total pooled USDX balance.
    function distributeYield() external payable nonReentrant {
        require(msg.value > 1 ether, "OzUSD: Must distribute at least one USDX.");
        emit YieldDistributed(_getTotalPooledUSDX() - msg.value, _getTotalPooledUSDX());
    }

    /// @notice Transfers an amount of ozUSD tokens from the caller to a recipient.
    /// @param  _recipient The recipient of the token transfer.
    /// @param  _amount The number of ozUSD tokens to transfer.
    /// @return bool Returns `true` if the transfer was successful.
    /// @dev    The `_amount` parameter represents the number of tokens, not shares. It calculates the equivalent shares
    ///         and transfers those shares between the accounts.
    function transfer(address _recipient, uint256 _amount) external nonReentrant returns (bool) {
        _transfer(msg.sender, _recipient, _amount);
        return true;
    }

    /// @notice Transfers `ozUSD` tokens on behalf of a sender to a recipient.
    /// @param  _sender The account from which the tokens are transferred.
    /// @param  _recipient The recipient of the token transfer.
    /// @param  _amount The number of ozUSD tokens to transfer.
    /// @return success Returns `true` if the transfer was successful.
    /// @dev    The `_amount` parameter represents the number of tokens, not shares. The caller must have an allowance
    ///         from the sender to spend the specified amount.
    function transferFrom(address _sender, address _recipient, uint256 _amount) external nonReentrant returns (bool) {
        _spendAllowance(_sender, msg.sender, _amount);
        _transfer(_sender, _recipient, _amount);
        return true;
    }

    /// @notice Approves a spender to spend a specific number of `ozUSD` tokens on behalf of the caller.
    /// @param  _spender The address authorized to spend the tokens.
    /// @param  _amount The number of tokens allowed to be spent.
    /// @return success Returns `true` if the approval was successful.
    /// @dev    The `_amount` argument is the amount of tokens, not shares.
    function approve(address _spender, uint256 _amount) external nonReentrant returns (bool) {
        _approve(msg.sender, _spender, _amount);
        return true;
    }

    /// @notice Increases the allowance of a spender by a specified amount.
    /// @param  _spender The address authorized to spend the tokens.
    /// @param  _addedValue The additional amount of tokens the spender is allowed to spend.
    /// @return success Returns `true` if the operation was successful.
    /// @dev    The `_addedValue` argument is the amount of tokens, not shares.
    function increaseAllowance(address _spender, uint256 _addedValue) external nonReentrant returns (bool) {
        _approve(msg.sender, _spender, allowances[msg.sender][_spender] + _addedValue);
        return true;
    }

    /// @notice Decreases the allowance of a spender by a specified amount.
    /// @param  _spender The address authorized to spend the tokens.
    /// @param  _subtractedValue The amount of tokens to subtract from the current allowance.
    /// @return success Returns `true` if the operation was successful.
    /// @dev    The `_subtractedValue` argument is the amount of tokens, not shares.
    ///         Reverts if the current allowance is less than the amount being subtracted.
    function decreaseAllowance(address _spender, uint256 _subtractedValue) external nonReentrant returns (bool) {
        uint256 currentAllowance = allowances[msg.sender][_spender];
        require(currentAllowance >= _subtractedValue, "OzUSD: Allowance below value.");
        _approve(msg.sender, _spender, currentAllowance - _subtractedValue);
        return true;
    }

    /// @notice Transfers `ozUSD` shares from the caller to a recipient and returns the equivalent ozUSD tokens.
    /// @param  _recipient The recipient of the share transfer.
    /// @param  _sharesAmount The number of shares to transfer.
    /// @return uint256 The equivalent ozUSD token amount corresponding to the transferred shares.
    /// @dev    The `_sharesAmount` argument is the amount of shares, not tokens.
    function transferShares(address _recipient, uint256 _sharesAmount) external nonReentrant returns (uint256) {
        _transferShares(msg.sender, _recipient, _sharesAmount);
        uint256 tokensAmount = getPooledUSDXByShares(_sharesAmount);
        _emitTransferEvents(msg.sender, _recipient, tokensAmount, _sharesAmount);
        return tokensAmount;
    }

    /// @notice Transfers `_sharesAmount` shares from `_sender` to `_recipient` and returns the equivalent ozUSD tokens.
    /// @param  _sender The address to transfer shares from.
    /// @param  _recipient The address to transfer shares to.
    /// @param  _sharesAmount The number of shares to transfer.
    /// @return uint256 The amount of ozUSD tokens equivalent to the transferred shares.
    /// @dev    The `_sharesAmount` argument is the amount of shares, not tokens.
    function transferSharesFrom(address _sender, address _recipient, uint256 _sharesAmount)
        external
        nonReentrant
        returns (uint256)
    {
        uint256 tokensAmount = getPooledUSDXByShares(_sharesAmount);
        _spendAllowance(_sender, msg.sender, tokensAmount);
        _transferShares(_sender, _recipient, _sharesAmount);
        _emitTransferEvents(_sender, _recipient, tokensAmount, _sharesAmount);
        return tokensAmount;
    }

    /// @notice Mints `ozUSD` to the specified `_to` address by depositing a `_usdxAmount` of USDX.
    /// @dev    Transfers USDX and mints new shares accordingly.
    /// @param  _to The address to receive the minted ozUSD.
    /// @param  _usdxAmount The amount of USDX to lock in exchange for ozUSD.
    function mintOzUSD(address _to, uint256 _usdxAmount) external payable nonReentrant {
        require(_usdxAmount != 0, "OzUSD: Amount zero.");
        require(msg.value == _usdxAmount, "OzUSD: Insufficient USDX transfer.");

        /// @dev Have to minus `_usdxAmount` from denominator given the transfer of funds has already occured
        uint256 sharesToMint = (_usdxAmount * totalShares) / (_getTotalPooledUSDX() - _usdxAmount);
        _mintShares(_to, sharesToMint);

        _emitTransferAfterMintingShares(_to, sharesToMint);
    }

    /// @notice Redeems ozUSD tokens by burning shares and redeeming the equivalent amount of `_ozUSDAmount` in USDX.
    /// @param  _from The address that owns the ozUSD to redeem.
    /// @param  _ozUSDAmount The amount of ozUSD to redeem.
    /// @dev    Burns shares and transfers back the corresponding USDX.
    function redeemOzUSD(address _from, uint256 _ozUSDAmount) external nonReentrant {
        require(_ozUSDAmount != 0, "OzUSD: Amount zero.");
        if (msg.sender != _from) _spendAllowance(_from, msg.sender, _ozUSDAmount);

        uint256 sharesToBurn = getSharesByPooledUSDX(_ozUSDAmount);
        _burnShares(_from, sharesToBurn);

        (bool s,) = _from.call{value: _ozUSDAmount}("");
        assert(s);

        _emitTransferEvents(msg.sender, address(0), _ozUSDAmount, sharesToBurn);
    }

    /// VIEW ///

    /// @notice Returns the balance of ozUSD tokens owned by `_account`.
    /// @param  _account The address to query the balance for.
    /// @return uint256 The amount of ozUSD tokens owned by `_account`.
    /// @dev    Balances are dynamic and equal to the _account's share of the total USDX controlled by the protocol.
    ///         This is calculated using the `sharesOf` function.
    function balanceOf(address _account) external view returns (uint256) {
        return getPooledUSDXByShares(shares[_account]);
    }

    /// @notice Returns the remaining number of ozUSD tokens that `_spender` is allowed to spend on behalf of `_owner`.
    /// @param  _owner The address of the token owner.
    /// @param  _spender The address of the spender.
    /// @return uint256 The remaining amount of ozUSD tokens that `_spender` can spend on behalf of `_owner`.
    /// @dev    This value is updated when `approve` or `transferFrom` is called. Defaults to zero.
    function allowance(address _owner, address _spender) external view returns (uint256) {
        return allowances[_owner][_spender];
    }

    /// @notice Returns the amount of shares owned by `_account`.
    /// @param  _account The address to query for shares.
    /// @return uint256 The amount of shares owned by `_account`.
    function sharesOf(address _account) external view returns (uint256) {
        return shares[_account];
    }

    /// @notice Returns the amount of shares that corresponds to the `_usdxAmount` of protocol-controlled USDX.
    /// @param  _usdxAmount The amount of USDX to convert to shares.
    /// @return uint256 The equivalent amount of shares for `_usdxAmount`.
    function getSharesByPooledUSDX(uint256 _usdxAmount) public view returns (uint256) {
        return (_usdxAmount * totalShares) / _getTotalPooledUSDX();
    }

    /// @notice Returns the amount of USDX that corresponds to `_sharesAmount` token shares.
    /// @param  _sharesAmount The number of shares to convert to USDX.
    /// @return The equivalent amount of USDX for `_sharesAmount`.
    function getPooledUSDXByShares(uint256 _sharesAmount) public view returns (uint256) {
        return (_sharesAmount * _getTotalPooledUSDX()) / totalShares;
    }

    /// @notice Returns the total supply of ozUSD tokens in existence.
    /// @return The total supply of ozUSD tokens.
    /// @dev    This is always equal to the total amount of USDX controlled by the protocol.
    function totalSupply() external view returns (uint256) {
        return _getTotalPooledUSDX();
    }

    /// INTERNAL ///

    function _getTotalPooledUSDX() internal view returns (uint256) {
        return address(this).balance;
    }

    /// @dev    Moves `_amount` tokens from `_sender` to `_recipient`.
    function _transfer(address _sender, address _recipient, uint256 _amount) internal {
        uint256 _sharesToTransfer = getSharesByPooledUSDX(_amount);
        _transferShares(_sender, _recipient, _sharesToTransfer);
        _emitTransferEvents(_sender, _recipient, _amount, _sharesToTransfer);
    }

    function _approve(address _owner, address _spender, uint256 _amount) internal {
        require(_owner != address(0), "OzUSD: Approve from zero address.");
        require(_spender != address(0), "OzUSD: Approve to zero address.");

        allowances[_owner][_spender] = _amount;
        emit Approval(_owner, _spender, _amount);
    }

    function _spendAllowance(address _owner, address _spender, uint256 _amount) internal {
        uint256 currentAllowance = allowances[_owner][_spender];
        if (currentAllowance != ~uint256(0)) {
            require(currentAllowance >= _amount, "OzUSD: Allowance exceeded.");
            _approve(_owner, _spender, currentAllowance - _amount);
        }
    }

    function _transferShares(address _sender, address _recipient, uint256 _sharesAmount) internal {
        require(_sender != address(0), "OzUSD: Transfer from zero address.");
        require(_recipient != address(0), "OzUSD: Transfer to zero address.");
        require(_recipient != address(this), "OzUSD: Transfer to this contract.");

        uint256 currentSenderShares = shares[_sender];
        require(_sharesAmount <= currentSenderShares, "OzUSD: Balance exceeded.");

        shares[_sender] = currentSenderShares - _sharesAmount;
        shares[_recipient] = shares[_recipient] + _sharesAmount;
    }

    /// @notice Creates `_sharesAmount` shares and assigns them to `_recipient`, increasing the total amount of shares.
    /// @dev    This doesn't increase the token total supply.
    function _mintShares(address _recipient, uint256 _sharesAmount) internal returns (uint256 newTotalShares) {
        require(_recipient != address(0), "OzUSD: Mint to zero address.");

        newTotalShares = totalShares + _sharesAmount;
        totalShares = newTotalShares;
        shares[_recipient] += _sharesAmount;
    }

    /// @notice Destroys `_sharesAmount` shares from `_account`'s holdings, decreasing the total amount of shares.
    /// @dev    This doesn't decrease the token total supply.
    function _burnShares(address _account, uint256 _sharesAmount) internal returns (uint256 newTotalShares) {
        require(_account != address(0), "OzUSD: Burn from zero address.");

        uint256 accountShares = shares[_account];
        require(_sharesAmount <= accountShares, "OzUSD: Balance exceeded.");

        uint256 preRebaseTokenAmount = getPooledUSDXByShares(_sharesAmount);

        newTotalShares = totalShares - _sharesAmount;
        totalShares = newTotalShares;
        shares[_account] = accountShares - _sharesAmount;

        uint256 postRebaseTokenAmount = getPooledUSDXByShares(_sharesAmount);

        emit SharesBurnt(_account, preRebaseTokenAmount, postRebaseTokenAmount, _sharesAmount);
    }

    function _emitTransferEvents(address _from, address _to, uint256 _tokenAmount, uint256 _sharesAmount) internal {
        emit Transfer(_from, _to, _tokenAmount);
        emit TransferShares(_from, _to, _sharesAmount);
    }

    /// @dev Emits {Transfer} and {TransferShares} events where `from` is 0 address. Indicates mint events.
    function _emitTransferAfterMintingShares(address _to, uint256 _sharesAmount) internal {
        _emitTransferEvents(address(0), _to, getPooledUSDXByShares(_sharesAmount), _sharesAmount);
    }
}
