// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0 <0.9.0;

import {IOptionMarketOTMFE} from "../interfaces/apps/options/IOptionMarketOTMFE.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {ISwapper} from "../interfaces/ISwapper.sol";

/// @title OpenSettlement
/// @notice Contract that handles the settlement of expired options with a two-tier fee structure
/// @dev Inherits from Ownable and uses SafeERC20 for token transfers
contract OpenSettlement is Ownable {
    using SafeERC20 for ERC20;

    // events

    event LogSettleOptionsOpen(
        address indexed market,
        uint256 indexed optionId,
        uint256 totalProfitForUser,
        uint256 settledFeeProtocol,
        uint256 settledFeePublic
    );

    // errors
    /// @notice Thrown when attempting to settle an option that hasn't been settled by the market
    error OptionNotSettled();

    /// @notice Fee percentage for whitelisted settlers (in SETTLE_FEE_PRECISION basis points)
    uint256 public settleFeeProtocol;

    /// @notice Fee percentage for public settlers (in SETTLE_FEE_PRECISION basis points)
    uint256 public settleFeePublic;

    /// @notice Precision for fee calculations (10,000 = 100%)
    uint256 public constant SETTLE_FEE_PRECISION = 10_000;

    /// @notice Address that receives settlement fees
    address public publicFeeRecipient;

    /// @notice Mapping of addresses to their whitelisted settler status
    mapping(address => bool) public isWhitelistedSettler;

    /// @notice Constructs the OpenSettlement contract
    /// @param _isWhitelistedSettler Initial whitelisted settler address
    /// @param _publicFeeRecipient Address to receive settlement fees
    /// @param _settleFeeProtocol Fee percentage for whitelisted settlers
    /// @param _settleFeePublic Fee percentage for public settlers
    constructor(
        address _isWhitelistedSettler,
        address _publicFeeRecipient,
        uint256 _settleFeeProtocol,
        uint256 _settleFeePublic
    ) Ownable(msg.sender) {
        settleFeeProtocol = _settleFeeProtocol;
        settleFeePublic = _settleFeePublic;
        isWhitelistedSettler[_isWhitelistedSettler] = true;
        publicFeeRecipient = _publicFeeRecipient;
    }

    /// @notice Settles an option and distributes profits according to the fee structure
    /// @dev Whitelisted settlers pay a lower fee than public settlers
    /// @param market The option market contract
    /// @param optionId The ID of the option to settle
    /// @param settleParams Parameters required for settlement
    /// @return AssetsCache struct containing settlement results
    function openSettle(
        IOptionMarketOTMFE market,
        uint256 optionId,
        IOptionMarketOTMFE.SettleOptionParams memory settleParams
    ) external returns (IOptionMarketOTMFE.AssetsCache memory) {
        (IOptionMarketOTMFE.AssetsCache memory ac) = market.settleOption(settleParams);

        if (!ac.isSettle) revert OptionNotSettled();

        if (ac.totalProfit > 0) {
            if (settleFeeProtocol > 0) {
                uint256 feeProtocol;
                uint256 feePublic;

                if (isWhitelistedSettler[msg.sender]) {
                    feeProtocol = (ac.totalProfit * settleFeeProtocol) / SETTLE_FEE_PRECISION;
                    ac.assetToGet.safeTransfer(publicFeeRecipient, feeProtocol);
                    ac.assetToGet.safeTransfer(market.ownerOf(optionId), ac.totalProfit - feeProtocol);
                } else {
                    feeProtocol = (ac.totalProfit * (settleFeeProtocol - settleFeePublic)) / SETTLE_FEE_PRECISION;
                    feePublic = (ac.totalProfit * settleFeePublic) / SETTLE_FEE_PRECISION;
                    ac.assetToGet.safeTransfer(publicFeeRecipient, feeProtocol);
                    ac.assetToGet.safeTransfer(msg.sender, feePublic);
                    ac.assetToGet.safeTransfer(market.ownerOf(optionId), ac.totalProfit - feeProtocol - feePublic);
                }

                emit LogSettleOptionsOpen(
                    address(market), optionId, ac.totalProfit - feeProtocol - feePublic, feeProtocol, feePublic
                );
            } else {
                ac.assetToGet.safeTransfer(market.ownerOf(optionId), ac.totalProfit);
                emit LogSettleOptionsOpen(address(market), optionId, ac.totalProfit, 0, 0);
            }
        }

        return ac;
    }

    /// @notice Updates the protocol fee percentage for whitelisted settlers
    /// @param _settleFeeProtocol New fee percentage in SETTLE_FEE_PRECISION basis points
    function setSettleFeeProtocol(uint256 _settleFeeProtocol) external onlyOwner {
        settleFeeProtocol = _settleFeeProtocol;
    }

    /// @notice Updates the public fee percentage for non-whitelisted settlers
    /// @param _settleFeePublic New fee percentage in SETTLE_FEE_PRECISION basis points
    function setSettleFeePublic(uint256 _settleFeePublic) external onlyOwner {
        settleFeePublic = _settleFeePublic;
    }

    /// @notice Updates the whitelisted status of a settler address
    /// @param _isWhitelistedSettler Address to update
    /// @param _isWhitelistedSettlerStatus New whitelisted status
    function setIsWhitelistedSettler(address _isWhitelistedSettler, bool _isWhitelistedSettlerStatus)
        external
        onlyOwner
    {
        isWhitelistedSettler[_isWhitelistedSettler] = _isWhitelistedSettlerStatus;
    }

    /// @notice Updates the address that receives settlement fees
    /// @param _publicFeeRecipient New fee recipient address
    function setPublicFeeRecipient(address _publicFeeRecipient) external onlyOwner {
        publicFeeRecipient = _publicFeeRecipient;
    }
}
