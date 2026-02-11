// SPDX-License-Identifier: MIT
pragma solidity =0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

contract WithdrawVault is Pausable, AccessControl {
    using SafeERC20 for IERC20;

    mapping(address => bool) public supportedTokens;
    address[] private supportedTokensArray;
    address public vault;
    address ceffu;

    // Role
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant VAULT_ROLE = keccak256("VAULT_ROLE");
    bytes32 private constant BOT_ROLE = keccak256("BOT_ROLE");

    event CeffuReceive(address indexed token, address indexed to, uint256 indexed amount);

    constructor(address[] memory tokens, address admin, address bot, address _ceffu) {
        require(admin != address(0), "Admin address cannot be zero");
        require(_ceffu != address(0), "Ceffu address cannot be zero");

        ceffu = _ceffu;

        uint length = tokens.length;
        for (uint i = 0; i < length; i++) {
            require(tokens[i] != address(0));
            supportedTokens[tokens[i]] = true;
            supportedTokensArray.push(tokens[i]);
        }

        // Grant admin roles
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);
        _grantRole(BOT_ROLE, bot);
    }

    function transfer(address token, address recipient, uint256 amount) external whenNotPaused onlyRole(VAULT_ROLE) {
        require(supportedTokens[token], "Token not supported");
        require(recipient != address(0), "Recipient cannot be zero address");
        require(amount > 0, "Amount must be greater than zero");
        require(IERC20(token).balanceOf(address(this)) >= amount, "Insufficient balance");

        IERC20(token).safeTransfer(recipient, amount);
    }

    /**
     * @dev Pauses the contract, disabling `transfer` functionality.
     * Can only be called by an account with the PAUSER_ROLE.
     */
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /**
     * @dev Unpauses the contract, enabling `transfer` functionality.
     * Can only be called by an account with the PAUSER_ROLE.
     */
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function addSupportedToken(address token) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(token != address(0), "Token address cannot be zero");
        require(!supportedTokens[token], "Token already supported");
        supportedTokens[token] = true;
        supportedTokensArray.push(token);
    }

    function setVault(address _vault) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_vault != address(0), "Vault address cannot be zero");
        address oldVault = vault;
        _revokeRole(VAULT_ROLE, oldVault);
        _grantRole(VAULT_ROLE, _vault);
        vault = _vault;
    }

    function changeAdmin(address _admin) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_admin != address(0), "Admin address cannot be zero");
        _revokeRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    }


    function getSupportedTokens() external view returns (address[] memory) {
        return supportedTokensArray;
    }

    function getBalance(address token) external view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }

    function emergencyWithdraw(address token, address recipient, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        // sweep the tokens which are sent to this contract accidentally
        require(token != address(0) && recipient != address(0), "Invalid address");
        IERC20(token).safeTransfer(recipient, amount);
    }

    function transferToCeffu(
        address _token,
        uint256 _amount
    ) external onlyRole(BOT_ROLE) {
        require(_amount > 0, "must > 0");
        require(_amount <= IERC20(_token).balanceOf(address(this)), "Not enough balance");

        require(supportedTokens[_token], "Token not supported");

        IERC20(_token).safeTransfer(ceffu, _amount);

        emit CeffuReceive(_token, ceffu, _amount);
    }


    receive() external payable {
        revert("This contract does not accept native currency");
    }
}