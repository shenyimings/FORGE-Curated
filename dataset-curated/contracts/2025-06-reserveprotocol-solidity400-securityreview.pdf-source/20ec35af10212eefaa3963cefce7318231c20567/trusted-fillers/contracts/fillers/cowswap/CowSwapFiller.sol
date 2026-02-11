// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { IBaseTrustedFiller } from "../../interfaces/IBaseTrustedFiller.sol";

import { GPv2OrderLib } from "./GPv2OrderLib.sol";
import { GPV2_SETTLEMENT, GPV2_VAULT_RELAYER, D27 } from "./Constants.sol";

/// Swap MUST occur in the same block as initialization
/// Expected to be newly deployed in the pre-hook of a CowSwap order
/// Ideally `closeFiller()` is called in the end as a post-hook, but this is not relied upon
contract CowSwapFiller is Initializable, IBaseTrustedFiller {
    using GPv2OrderLib for GPv2OrderLib.Data;
    using SafeERC20 for IERC20;

    error CowSwapFiller__Unauthorized();
    error CowSwapFiller__OrderCheckFailed(uint256 errorCode);

    address public fillCreator;

    IERC20 public sellToken;
    IERC20 public buyToken;

    uint256 public sellAmount; // {sellTok}
    uint256 public blockInitialized; // {block}

    uint256 public price; // D27{buyTok/sellTok}

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// Initialize the swap, transferring in `_sellAmount` of the `_sell` token
    /// @dev Built for the pre-hook of a CowSwap order, must be called via using entity
    function initialize(
        address _creator,
        IERC20 _sellToken,
        IERC20 _buyToken,
        uint256 _sellAmount,
        uint256 _minBuyAmount
    ) external initializer {
        fillCreator = _creator;
        sellToken = _sellToken;
        buyToken = _buyToken;
        sellAmount = _sellAmount;

        blockInitialized = block.number;

        // D27{buyTok/sellTok} = {buyTok} * D27 / {sellTok}
        price = Math.mulDiv(_minBuyAmount, D27, _sellAmount, Math.Rounding.Ceil);

        sellToken.forceApprove(GPV2_VAULT_RELAYER, _sellAmount);
        sellToken.safeTransferFrom(_creator, address(this), _sellAmount);
    }

    /// @dev Validates CowSwap order for a fill via EIP-1271
    function isValidSignature(bytes32 orderHash, bytes calldata signature) external view returns (bytes4) {
        require(block.number == blockInitialized, CowSwapFiller__Unauthorized());

        // Decode signature to get the CowSwap order
        GPv2OrderLib.Data memory order = abi.decode(signature, (GPv2OrderLib.Data));

        // Verify Order Hash
        require(orderHash == order.hash(GPV2_SETTLEMENT.domainSeparator()), CowSwapFiller__OrderCheckFailed(0)); // Invalid Order Hash

        require(order.sellToken == sellToken, CowSwapFiller__OrderCheckFailed(1)); // Invalid Sell Token
        require(order.buyToken == buyToken, CowSwapFiller__OrderCheckFailed(2)); // Invalid Buy Token
        require(order.feeAmount == 0, CowSwapFiller__OrderCheckFailed(3)); // Must be a Limit Order
        require(order.receiver == address(this), CowSwapFiller__OrderCheckFailed(4)); // Receiver must be self
        require(order.sellTokenBalance == GPv2OrderLib.BALANCE_ERC20, CowSwapFiller__OrderCheckFailed(5)); // Must use ERC20 Balance
        require(order.buyTokenBalance == GPv2OrderLib.BALANCE_ERC20, CowSwapFiller__OrderCheckFailed(6)); // Must use ERC20 Balance
        require(order.sellAmount != 0, CowSwapFiller__OrderCheckFailed(7)); // catch div-by-zero below

        // Price check, just in case
        // D27{buyTok/sellTok} = {buyTok} * D27 / {sellTok}
        uint256 orderPrice = Math.mulDiv(order.buyAmount, D27, order.sellAmount, Math.Rounding.Floor);
        require(order.sellAmount <= sellAmount && orderPrice >= price, CowSwapFiller__OrderCheckFailed(100));

        // If all checks pass, return the magic value
        return this.isValidSignature.selector;
    }

    /// @return true if the contract is mid-swap and funds have not yet settled
    function swapActive() public view returns (bool) {
        if (block.number != blockInitialized) {
            return false;
        }

        uint256 sellTokenBalance = sellToken.balanceOf(address(this));

        if (sellTokenBalance >= sellAmount) {
            return false;
        }

        // {buyTok} = {sellTok} * D27{buyTok/sellTok} / D27
        uint256 minimumExpectedIn = Math.mulDiv(sellAmount - sellTokenBalance, price, D27, Math.Rounding.Ceil);
        
        return minimumExpectedIn > buyToken.balanceOf(address(this));
    }

    /// Collect all balances back to the beneficiary
    function closeFiller() external {
        require(!swapActive(), IBaseTrustedFiller__SwapActive());

        rescueToken(sellToken);
        rescueToken(buyToken);
    }

    /// Rescue tokens in case any are left in the contract
    function rescueToken(IERC20 token) public {
        uint256 tokenBalance = token.balanceOf(address(this));

        if (tokenBalance != 0) {
            token.safeTransfer(fillCreator, tokenBalance);
        }
    }
}
