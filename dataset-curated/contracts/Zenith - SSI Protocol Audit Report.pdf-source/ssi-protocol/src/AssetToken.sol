// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;
import "./Interface.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Utils} from './Utils.sol';

import "forge-std/console.sol";

contract AssetToken is Initializable, ERC20Upgradeable, AccessControlUpgradeable, UUPSUpgradeable, IAssetToken {
    // tokenset
    Token[] tokenset_;
    Token[] basket_;
    Token[] feeTokenset_;
    // issue
    uint issueCnt;
    // rebalance
    bool public rebalancing;
    // fee
    uint public constant feeDecimals = 8;
    uint public id;
    uint public maxFee;
    uint public fee;
    uint public lastCollectTimestamp;
    bool public burningFee;
    // roles
    bytes32 public constant ISSUER_ROLE = keccak256("ISSUER_ROLE");
    bytes32 public constant REBALANCER_ROLE = keccak256("REBALANCER_ROLE");
    bytes32 public constant FEEMANAGER_ROLE = keccak256("FEEMANAGER_ROLE");
    // event
    event SetFee(uint fee);
    event SetTokenset(Token[] tokenset);
    event SetBasket(Token[] basket);
    event SetFeeTokenset(Token[] feeTokenset);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize (
        uint256 id_,
        string memory name_,
        string memory symbol_,
        uint maxFee_,
        address owner
    ) public initializer {
        __ERC20_init(name_, symbol_);
        __AccessControl_init();
        __UUPSUpgradeable_init();
        require(maxFee_ < 10**feeDecimals, "maxFee should less than 1");
        id = id_;
        maxFee = maxFee_;
        fee = maxFee;
        lastCollectTimestamp = block.timestamp;
        _grantRole(DEFAULT_ADMIN_ROLE, owner);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    function decimals() public pure override(ERC20Upgradeable, IAssetToken) returns (uint8) {
        return 8;
    }

    // tokenset

    function getTokenset() public view returns (Token[] memory) {
        return tokenset_;
    }

    function initTokenset(Token[] memory tokenset) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(tokenset_.length == 0, "already inited");
        setTokenset(tokenset);
    }

    function setTokenset(Token[] memory tokenset) internal {
        delete tokenset_;
        for (uint i = 0; i < tokenset.length; i++) {
            require(tokenset[i].amount > 0, "token amount == 0");
            tokenset_.push(tokenset[i]);
        }
        emit SetTokenset(tokenset_);
    }

    function getBasket() public view returns (Token[] memory) {
        return basket_;
    }

    function setBasket(Token[] memory basket) internal {
        delete basket_;
        for (uint i = 0; i < basket.length; i++) {
            require(basket[i].amount > 0, "token amount == 0");
            basket_.push(basket[i]);
        }
        emit SetBasket(basket_);
    }

    // issue

    function lockIssue() external onlyRole(ISSUER_ROLE) {
        require(rebalancing == false, "is rebalancing");
        issueCnt += 1;
    }

    function issuing() external view returns (bool) {
        return issueCnt > 0;
    }

    function unlockIssue() external onlyRole(ISSUER_ROLE) {
        if (issueCnt > 0) {
            issueCnt -= 1;
        }
    }

    function mint(address account, uint amount) external onlyRole(ISSUER_ROLE) {
        _mint(account, amount);
        Token[] memory newBasket = Utils.addTokenset(basket_, Utils.muldivTokenset(tokenset_, amount, 10 ** decimals()));
        setBasket(newBasket);
    }

    function burn(uint amount) external onlyRole(ISSUER_ROLE) {
        _update(msg.sender, address(0), amount);
        Token[] memory newBasket = Utils.subTokenset(basket_, Utils.muldivTokenset(tokenset_, amount, 10 ** decimals()));
        setBasket(newBasket);
    }

    // rebalance

    function lockRebalance() external onlyRole(REBALANCER_ROLE) {
        require(issueCnt == 0, "is issuing");
        require(rebalancing == false, "is rebalancing");
        rebalancing = true;
    }

    function unlockRebalance() external onlyRole(REBALANCER_ROLE) {
        rebalancing = false;
    }

    function rebalance(Token[] memory inBasket, Token[] memory outBasket) external onlyRole(REBALANCER_ROLE) {
        require(rebalancing, "lock rebalance first");
        require(totalSupply() > 0, "zero supply");
        Token[] memory newBasket = Utils.addTokenset(Utils.subTokenset(basket_, outBasket), inBasket);
        Token[] memory newTokenset = Utils.muldivTokenset(newBasket, 10**decimals(), totalSupply());
        setBasket(newBasket);
        setTokenset(newTokenset);
    }

    // fee

    function setFee(uint fee_) external onlyRole(FEEMANAGER_ROLE) {
        require(fee_ <= maxFee, "new fee exceeds maxFee");
        fee = fee_;
        emit SetFee(fee_);
    }

    function getFeeTokenset() external view returns (Token[] memory) {
        return feeTokenset_;
    }

    function feeCollected() external view returns (bool) {
        return block.timestamp - lastCollectTimestamp < 1 days;
    }

    // warning: fee manager should collect fee daily
    function collectFeeTokenset() external onlyRole(FEEMANAGER_ROLE) {
        if (block.timestamp - lastCollectTimestamp >= 1 days) {
            if (totalSupply() > 0) {
                require(rebalancing == false, "is rebalancing");
                require(issueCnt == 0, "is issuing");
                Token[] memory newBasket = basket_;
                uint256 feeDays = (block.timestamp - lastCollectTimestamp) / 1 days;
                for (uint i = 0; i < newBasket.length; i++) {
                    for (uint j = 0; j < feeDays; j++) {
                        newBasket[i].amount -= newBasket[i].amount * fee / (10 ** feeDecimals);
                    }
                }
                Token[] memory newFeeTokenset = Utils.addTokenset(feeTokenset_, Utils.subTokenset(basket_, newBasket));
                Token[] memory newTokenset = Utils.muldivTokenset(newBasket, 10**decimals(), totalSupply());
                setBasket(newBasket);
                setFeeTokenset(newFeeTokenset);
                setTokenset(newTokenset);
            }
            lastCollectTimestamp += (block.timestamp - lastCollectTimestamp) / 1 days * 1 days;
        }
    }

    function lockBurnFee() external onlyRole(FEEMANAGER_ROLE) {
        require(burningFee == false, "is burning fee");
        burningFee = true;
    }

    function unlockBurnFee() external onlyRole(FEEMANAGER_ROLE) {
        burningFee = false;
    }

    function burnFeeTokenset(Token[] memory feeTokenset) external onlyRole(FEEMANAGER_ROLE) {
        require(Utils.containTokenset(feeTokenset_, feeTokenset), "burn amount too large");
        setFeeTokenset(Utils.subTokenset(feeTokenset_, feeTokenset));
    }

    function setFeeTokenset(Token[] memory feeTokenset) internal {
        delete feeTokenset_;
        for (uint i = 0; i < feeTokenset.length; i++) {
            feeTokenset_.push(feeTokenset[i]);
        }
        emit SetFeeTokenset(feeTokenset_);
    }
}
