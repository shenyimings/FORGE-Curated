// SPDX-License-Identifier: BUSL-1.1
// OpenZeppelin Contracts (last updated v5.0.0) (token/ERC20/extensions/ERC20Wrapper.sol)

pragma solidity ^0.8.20;

import {IERC20, IERC20Metadata, ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./auth/v5/SingleAdminAccessControl.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import "./interfaces/aave/IRewardsController.sol";

/**
 * @dev Extension of the ERC-20 token contract to support token wrapping.
 *
 * Users can deposit and withdraw "underlying tokens" and receive a matching number of "wrapped tokens". This is useful
 * in conjunction with other modules. For example, combining this wrapping mechanism with {ERC20Votes} will allow the
 * wrapping of an existing "basic" ERC-20 into a governance token.
 *
 * WARNING: Any mechanism in which the underlying token changes the {balanceOf} of an account without an explicit transfer
 * may desynchronize this contract's supply and its underlying balance. Please exercise caution when wrapping tokens that
 * may undercollateralize the wrapper (i.e. wrapper's total supply is higher than its underlying balance). See {claimAllRewards}
 * for recovering value accrued to the wrapper.
 */
contract WrappedRebasingERC20 is ERC20, SingleAdminAccessControl {
    using SafeERC20 for IERC20;
    IERC20 private immutable _underlying;

    bytes32 public RECOVERER_ROLE = keccak256("RECOVERER_ROLE");

    /**
     * @dev The underlying token couldn't be wrapped.
     */
    error ERC20InvalidUnderlying(address token);

    constructor(
        IERC20 underlyingToken,
        string memory name,
        string memory symbol
    ) ERC20(name, symbol) {
        if (underlyingToken == this) {
            revert ERC20InvalidUnderlying(address(this));
        }
        _underlying = underlyingToken;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /**
     * @dev See {ERC20-decimals}.
     */
    function decimals() public view virtual override returns (uint8) {
        try IERC20Metadata(address(_underlying)).decimals() returns (
            uint8 value
        ) {
            return value;
        } catch {
            return super.decimals();
        }
    }

    /**
     * @dev Returns the address of the underlying ERC-20 token that is being wrapped.
     */
    function underlying() public view returns (IERC20) {
        return _underlying;
    }

    /**
     * @dev Allow a user to deposit underlying tokens and mint the corresponding number of wrapped tokens.
     */
    function depositFor(
        address account,
        uint256 value
    ) public virtual returns (bool) {
        address sender = _msgSender();
        if (sender == address(this)) {
            revert IERC20Errors.ERC20InvalidSender(address(this));
        }
        if (account == address(this)) {
            revert IERC20Errors.ERC20InvalidReceiver(account);
        }
        SafeERC20.safeTransferFrom(_underlying, sender, address(this), value);
        _mint(account, value);
        return true;
    }

    /**
     * @dev Allow a user to burn a number of wrapped tokens and withdraw the corresponding number of underlying tokens.
     */
    function withdrawTo(
        address account,
        uint256 value
    ) public virtual returns (bool) {
        if (account == address(this)) {
            revert IERC20Errors.ERC20InvalidReceiver(account);
        }
        _burn(_msgSender(), value);
        SafeERC20.safeTransfer(_underlying, account, value);
        return true;
    }

    /**
     * @dev Mint wrapped token to cover any underlyingTokens that would have been transferred by mistake or acquired from
     * rebasing mechanisms. Internal function that can be exposed with access control if desired.
     */
    function recoverUnderlying()
        external
        onlyRole(RECOVERER_ROLE)
        returns (uint256)
    {
        address sender = _msgSender();
        uint256 value = _underlying.balanceOf(address(this)) - totalSupply();
        if (value > 0) {
            SafeERC20.safeTransfer(_underlying, sender, value);
        }
        return value;
    }

    /**
     * @dev Recover any ERC20 tokens that were accidentally sent to this contract.
     * Can only be called by admin. Cannot recover the underlying token - use claimAllRewards() for that.
     * @param tokenAddress The token contract address to recover
     * @param tokenReceiver The address to send the tokens to
     * @param tokenAmount The amount of tokens to recover
     */
    function transferERC20(
        address tokenAddress,
        address tokenReceiver,
        uint256 tokenAmount
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(
            tokenAddress != address(_underlying),
            "Use recover instead of transferERC20 to recover underlying."
        );
        require(tokenReceiver != address(0), "Invalid recipient");
        IERC20(tokenAddress).safeTransfer(tokenReceiver, tokenAmount);
    }

    /**
     * @dev Recover ETH that was accidentally sent to this contract.
     * Can only be called by admin.
     * @param _to The address to send the ETH to
     */
    function transferEth(
        address payable _to,
        uint256 _amount
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        (bool success, ) = _to.call{value: _amount}("");
        require(success, "Failed to send Ether");
    }

    /**
     * @dev Claim Aave rewards
     * @param rewardsController Aave rewards controller contract
     * @param assets tokens to claim
     * @param to The address to send the rewards to
     */
    function claimAllRewards(
        address rewardsController,
        address[] calldata assets,
        address to
    )
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        returns (address[] memory rewardsList, uint256[] memory claimedAmounts)
    {
        return
            IRewardsController(rewardsController).claimAllRewards(assets, to);
    }
}
