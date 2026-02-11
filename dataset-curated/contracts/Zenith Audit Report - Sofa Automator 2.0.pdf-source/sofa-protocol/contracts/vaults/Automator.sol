// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/utils/ERC1155HolderUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "../interfaces/IFeeCollector.sol";

struct Product {
    uint256 expiry;
    uint256[2] anchorPrices;
    uint256 collateralAtRiskPercentage;
}

struct MintParams {
    uint256 expiry;
    uint256[2] anchorPrices;
    uint256 collateralAtRisk;
    uint256 makerCollateral;
    uint256 deadline;
    address maker;
    bytes makerSignature;
}

interface IVault {
    function mint(
        uint256 totalCollateral,
        MintParams calldata params,
        address referral
    ) external;

    function burn(uint256 expiry, uint256[2] calldata anchorPrices, uint256 collateralAtRiskPercentage, uint256 isMaker) external;
}

contract Automator is Initializable, ContextUpgradeable, OwnableUpgradeable, ERC1155HolderUpgradeable, ERC20Upgradeable, ReentrancyGuardUpgradeable {
    using ECDSA for bytes32;
    using SafeERC20 for IERC20;

    address public referral;
    IERC20 public collateral;
    uint256 public constant MINIMUM_SHARES = 10**3;

    uint256 public totalFee;
    address public feeCollector;
    uint256 public totalPendingRedemptions;
    uint256 public totalCollateral;

    mapping(address => bool) public vaults;
    mapping(address => bool) public makers;
    mapping(bytes32 => uint256) private _positions;
    mapping(address => Redemption) private _redemptions;

    struct Redemption {
        uint256 pendingRedemption;
        uint256 redemptionRequestTimestamp;
    }

    struct ProductMint {
        address vault;
        uint256 totalCollateral;
        MintParams mintParams;
    }

    struct ProductBurn {
        address vault;
        Product[] products;
    }

    event Deposited(address indexed account, uint256 amount, uint256 shares);
    event Withdrawn(address indexed account, uint256 shares);
    event RedemptionsClaimed(address indexed account, uint256 amount, uint256 shares);
    event ProductsMinted(ProductMint[] products);
    event ProductsBurned(ProductBurn[] products, uint256 totalCollateral, uint256 fee);
    event ReferralUpdated(address referral);
    event VaultsEnabled(address[] vaults);
    event VaultsDisabled(address[] vaults);
    event MakersEnabled(address[] makers);
    event MakersDisabled(address[] makers);
    event FeeCollected(address account, uint256 amount);

    function initialize(
        address collateral_,
        address referral_,
        address feeCollector_
    ) external initializer {
        collateral = IERC20(collateral_);
        referral = referral_;
        feeCollector = feeCollector_;
        __Ownable_init();
        __ERC1155Holder_init();
        __ERC20_init(
            string(abi.encodePacked("Automator ", IERC20Metadata(collateral_).name())),
            string(abi.encodePacked("at", IERC20Metadata(collateral_).symbol()))
        );
        __ReentrancyGuard_init();
    }

    function deposit(uint256 amount) external nonReentrant {
        collateral.safeTransferFrom(_msgSender(), address(this), amount);
        uint256 shares;
        if (totalSupply() == 0) {
            shares = amount - MINIMUM_SHARES;
            _mint(address(0x000000000000000000000000000000000000dEaD), MINIMUM_SHARES);
        } else {
            shares = amount * totalSupply() / totalCollateral;
        }
        totalCollateral += amount;
        _mint(_msgSender(), shares);
        emit Deposited(_msgSender(), amount, shares);
    }

    function withdraw(uint256 shares) external nonReentrant {
        require(balanceOf(_msgSender()) >= shares, "Automator: insufficient shares");
        if (_redemptions[_msgSender()].pendingRedemption > 0) {
            totalPendingRedemptions = totalPendingRedemptions + shares - _redemptions[_msgSender()].pendingRedemption;
        } else {
            totalPendingRedemptions = totalPendingRedemptions + shares;
        }
        _redemptions[_msgSender()].pendingRedemption = shares;
        _redemptions[_msgSender()].redemptionRequestTimestamp = block.timestamp;

        emit Withdrawn(_msgSender(), shares);
    }

    function claimRedemptions() external nonReentrant {
        require(_redemptions[_msgSender()].pendingRedemption > 0, "Automator: no pending redemption");
        require(block.timestamp >= _redemptions[_msgSender()].redemptionRequestTimestamp + 7 days && block.timestamp < _redemptions[_msgSender()].redemptionRequestTimestamp + 7 days + 3 days, "Automator: invalid redemption");

        uint256 pendingRedemption = _redemptions[_msgSender()].pendingRedemption;
        uint256 amount = pendingRedemption * getPricePerShare() / 1e18;
        require(collateral.balanceOf(address(this)) >= amount, "Automator: insufficient collateral to redeem");

        totalPendingRedemptions -= pendingRedemption;
        _redemptions[_msgSender()].pendingRedemption = 0;
        totalCollateral -= amount;

        _burn(_msgSender(), pendingRedemption);
        collateral.safeTransfer(_msgSender(), amount);

        emit RedemptionsClaimed(_msgSender(), amount, pendingRedemption);
    }

    function mintProducts(
        ProductMint[] calldata products,
        bytes calldata signature
    ) external nonReentrant {
        bytes32 signatures;
        for (uint256 i = 0; i < products.length; i++) {
            require(vaults[products[i].vault], "Automator: invalid vault");
            IVault(products[i].vault).mint(
                products[i].totalCollateral,
                products[i].mintParams,
                referral
            );
            uint256 collateralAtRiskPercentage = products[i].mintParams.collateralAtRisk * 1e18 / products[i].totalCollateral;
            bytes32 id = keccak256(abi.encodePacked(products[i].vault, products[i].mintParams.expiry, products[i].mintParams.anchorPrices, collateralAtRiskPercentage));
            _positions[id] = _positions[id] + products[i].totalCollateral - products[i].mintParams.makerCollateral;
            signatures = signatures ^ keccak256(abi.encodePacked(products[i].mintParams.maker, products[i].mintParams.makerSignature));
        }

        (address signer, ) = signatures.toEthSignedMessageHash().tryRecover(signature);
        require(makers[signer], "Automator: invalid maker");
        require(collateral.balanceOf(address(this)) >= totalFee + totalPendingRedemptions * getPricePerShare() / 1e18, "Automator: no enough collateral to redeem");

        emit ProductsMinted(products);
    }

    function burnProducts(
        ProductBurn[] calldata products
    ) external nonReentrant {
        uint256 totalEarned;
        uint256 totalPositions;
        uint256 fee;
        for (uint256 i = 0; i < products.length; i++) {
            for (uint256 j = 0; j < products[i].products.length; j++) {
                uint256 balanceBefore = collateral.balanceOf(address(this));
                IVault(products[i].vault).burn(
                    products[i].products[j].expiry,
                    products[i].products[j].anchorPrices,
                    products[i].products[j].collateralAtRiskPercentage,
                    0
                );
                uint256 balanceAfter = collateral.balanceOf(address(this));
                uint256 earned = balanceAfter - balanceBefore;
                totalEarned += earned;
                bytes32 id = keccak256(abi.encodePacked(products[i].vault, products[i].products[j].expiry, products[i].products[j].anchorPrices, products[i].products[j].collateralAtRiskPercentage));
                totalPositions += _positions[id];
                if (earned > _positions[id]) {
                    fee += (earned - _positions[id]) * IFeeCollector(feeCollector).tradingFeeRate() / 1e18;
                }
                delete _positions[id];
            }
        }
        if (fee > 0) {
            totalFee += fee;
            totalEarned -= fee;
        }
        if (totalEarned > totalPositions) {
            totalCollateral += totalEarned - totalPositions;
        } else if (totalEarned < totalPositions) {
            totalCollateral -= totalPositions - totalEarned;
        }

        emit ProductsBurned(products, totalCollateral, fee);
    }

    function harvest() external {
        uint256 fee = totalFee;
        require(fee > 0, "Automator: zero fee");
        totalFee = 0;
        collateral.safeTransfer(feeCollector, fee);

        emit FeeCollected(_msgSender(), fee);
    }

    function updateReferral(address referral_) external onlyOwner {
        referral = referral_;
        emit ReferralUpdated(referral_);
    }

    function enableVaults(address[] calldata vaults_) external onlyOwner {
        for (uint256 i = 0; i < vaults_.length; i++) {
            vaults[vaults_[i]] = true;
            collateral.approve(vaults_[i], type(uint256).max);
        }
        emit VaultsEnabled(vaults_);
    }

    function disableVaults(address[] calldata vaults_) external onlyOwner {
        for (uint256 i = 0; i < vaults_.length; i++) {
            vaults[vaults_[i]] = false;
            collateral.approve(vaults_[i], 0);
        }
        emit VaultsDisabled(vaults_);
    }

    function enableMakers(address[] calldata makers_) external onlyOwner {
        for (uint256 i = 0; i < makers_.length; i++) {
            makers[makers_[i]] = true;
        }
        emit MakersEnabled(makers_);
    }

    function disableMakers(address[] calldata makers_) external onlyOwner {
        for (uint256 i = 0; i < makers_.length; i++) {
            makers[makers_[i]] = false;
        }
        emit MakersDisabled(makers_);
    }

    function decimals() public view virtual override returns (uint8) {
        return IERC20Metadata(address(collateral)).decimals();
    }

    function getRedemption() external view returns (uint256, uint256) {
        return (_redemptions[_msgSender()].pendingRedemption, _redemptions[_msgSender()].redemptionRequestTimestamp);
    }

    function getPricePerShare() public view returns (uint256) {
        if (totalSupply() == 0) {
            return 1e18;
        } else {
            return totalCollateral * 1e18 / totalSupply();
        }
    }

    function getUnredeemedCollateral() external view returns (uint256) {
        if (collateral.balanceOf(address(this)) > totalPendingRedemptions * getPricePerShare() / 1e18) {
            return collateral.balanceOf(address(this)) - totalPendingRedemptions * getPricePerShare() / 1e18;
        } else {
            return 0;
        }
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual override {
        if (from != address(0)) {
            require(balanceOf(from) >= amount + _redemptions[from].pendingRedemption, "Automator: invalid transfer amount");
        }
        super._beforeTokenTransfer(from, to, amount);
    }
}
