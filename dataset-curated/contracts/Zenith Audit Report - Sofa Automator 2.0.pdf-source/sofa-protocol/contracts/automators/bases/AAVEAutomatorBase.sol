// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "../../interfaces/IFeeCollector.sol";
import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";
import {DataTypes} from "@aave/core-v3/contracts/protocol/libraries/types/DataTypes.sol";
import {ReserveLogic} from "@aave/core-v3/contracts/protocol/libraries/logic/ReserveLogic.sol";
import {IAToken} from "@aave/core-v3/contracts/interfaces/IAToken.sol";

struct Product {
    uint256 expiry;
    uint256[2] anchorPrices;
}

struct MintParams {
    uint256 expiry;
    uint256[2] anchorPrices;
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

    function burn(uint256 expiry, uint256[2] calldata anchorPrices, uint256 isMaker) external;
}

interface IAutomatorFactory {
    function vaults(address) external view returns (bool);
    function makers(address) external view returns (bool);
    function referral() external view returns (address);
    function feeCollector() external view returns (address);
}

contract AAVEAutomatorBase is ERC1155Holder, ERC20, ReentrancyGuard {
    using ECDSA for bytes32;
    using SafeERC20 for IERC20;
    using Strings for uint256;

    address private _owner;
    IERC20 public collateral;
    uint256 public feeRate;
    uint256 public maxPeriod;
    address public immutable factory;
    uint256 public constant MINIMUM_SHARES = 10**3;
    string private symbol_;

    int256 public totalFee;
    uint256 public totalProtocolFee;
    uint256 public totalPendingRedemptions;
    uint256 public totalPositions;

    // Aave Referral Code
    IAToken public aToken;
    IPool public immutable pool;
    uint16 private constant REFERRAL_CODE = 0;

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

    event Deposited(address indexed account, uint256 amount, uint256 yieldShares, uint256 shares);
    event Withdrawn(address indexed account, uint256 shares);
    event RedemptionsClaimed(address indexed account, uint256 amount, uint256 yieldShares, uint256 shares);
    event ProductsMinted(ProductMint[] products);
    event ProductsBurned(ProductBurn[] products, uint256 accCollateralPerShare, int256 fee, uint256 protocolFee);
    event FeeCollected(address account, uint256 feeAmount, int256 fee, uint256 protocolFeeAmount, uint256 protocolFee);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor(address pool_) ERC20("", "") {
        pool = IPool(pool_);
        factory = _msgSender();
    }

    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _transferOwnership(newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Internal function without access restriction.
     */
    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }

    /**
     * @dev Throws if the sender is not the owner.
     */
    function _checkOwner() internal view virtual {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
    }

    function initialize(
        address owner_,
        address collateral_,
        uint256 feeRate_,
        uint256 maxPeriod_
    ) external {
        require(_msgSender() == factory, "Automator: forbidden");
        _owner = owner_;
        collateral = IERC20(collateral_);
        feeRate = feeRate_;
        maxPeriod = maxPeriod_;
        aToken = IAToken(pool.getReserveData(collateral_).aTokenAddress);
        collateral.safeApprove(address(pool), type(uint256).max);
        uint256 salt = uint256(uint160(address(this))) % 65536;
        symbol_ = string(abi.encodePacked("at", IERC20Metadata(address(collateral)).symbol(), "_", salt.toString()));
    }

    function deposit(uint256 amount) external nonReentrant {
        collateral.safeTransferFrom(_msgSender(), address(this), amount);
        pool.supply(address(collateral), amount, address(this), REFERRAL_CODE);
        uint256 shares;
        if (totalSupply() == 0) {
            shares = amount - MINIMUM_SHARES;
            _mint(address(0x000000000000000000000000000000000000dEaD), MINIMUM_SHARES);
        } else {
            shares = amount * totalSupply() / (totalCollateral() - amount);
        }
        _mint(_msgSender(), shares);
        emit Deposited(_msgSender(), amount, amount, shares);
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
        require(block.timestamp >= _redemptions[_msgSender()].redemptionRequestTimestamp + maxPeriod && block.timestamp < _redemptions[_msgSender()].redemptionRequestTimestamp + maxPeriod + 3 days, "Automator: invalid redemption");

        uint256 pendingRedemption = _redemptions[_msgSender()].pendingRedemption;
        uint256 aTokenAmount = pendingRedemption * totalCollateral() / totalSupply();
        require(aToken.balanceOf(address(this)) >= aTokenAmount, "Automator: insufficient collateral to redeem");

        totalPendingRedemptions -= pendingRedemption;
        _redemptions[_msgSender()].pendingRedemption = 0;

        _burn(_msgSender(), pendingRedemption);
        uint256 amount = pool.withdraw(address(collateral), aTokenAmount, _msgSender());
        require(amount > 0, "Automator: withdraw failed");

        emit RedemptionsClaimed(_msgSender(), amount, aTokenAmount, pendingRedemption);
    }

    function mintProducts(
        ProductMint[] calldata products,
        bytes calldata signature
    ) external nonReentrant onlyOwner {
        bytes32 signatures;
        uint256 _totalPositions;
        for (uint256 i = 0; i < products.length; i++) {
            require(IAutomatorFactory(factory).vaults(products[i].vault), "Automator: invalid vault");
            uint256 period = products[i].mintParams.expiry - block.timestamp;
            require(period <= maxPeriod, "Automator: exceed maxPeriod");
            // approve vaults
            if (aToken.allowance(address(this), products[i].vault) == 0) {
                aToken.approve(products[i].vault, type(uint256).max);
            }
            IVault(products[i].vault).mint(
                products[i].totalCollateral,
                products[i].mintParams,
                IAutomatorFactory(factory).referral()
            );
            bytes32 id = keccak256(abi.encodePacked(products[i].vault, products[i].mintParams.expiry, products[i].mintParams.anchorPrices));
            _positions[id] = _positions[id] + products[i].totalCollateral - products[i].mintParams.makerCollateral;
            _totalPositions += products[i].totalCollateral - products[i].mintParams.makerCollateral;
            signatures = signatures ^ keccak256(abi.encodePacked(products[i].mintParams.maker, products[i].mintParams.makerSignature));
        }
        totalPositions += _totalPositions;

        (address signer, ) = signatures.toEthSignedMessageHash().tryRecover(signature);
        require(IAutomatorFactory(factory).makers(signer), "Automator: invalid maker");
        if (totalFee > 0) {
            require(aToken.balanceOf(address(this)) >= uint256(totalFee) + totalProtocolFee + totalPendingRedemptions * totalCollateral() / totalSupply(), "Automator: no enough collateral to redeem");
        } else {
            require(aToken.balanceOf(address(this)) >= totalProtocolFee + totalPendingRedemptions * totalCollateral() / totalSupply(), "Automator: no enough collateral to redeem");
        }

        emit ProductsMinted(products);
    }

    function burnProducts(
        ProductBurn[] calldata products
    ) external nonReentrant {
        uint256 _totalPositions;
        int256 fee;
        uint256 protocolFee;
        for (uint256 i = 0; i < products.length; i++) {
            for (uint256 j = 0; j < products[i].products.length; j++) {
                uint256 balanceBefore = aToken.balanceOf(address(this));
                IVault(products[i].vault).burn(
                    products[i].products[j].expiry,
                    products[i].products[j].anchorPrices,
                    0
                );
                uint256 balanceAfter = aToken.balanceOf(address(this));
                uint256 earned = balanceAfter - balanceBefore;
                bytes32 id = keccak256(abi.encodePacked(products[i].vault, products[i].products[j].expiry, products[i].products[j].anchorPrices));
                _totalPositions += _positions[id];
                if (earned > _positions[id]) {
                    fee += int256((earned - _positions[id]) * feeRate / 1e18);
                    protocolFee += (earned - _positions[id]) * IFeeCollector(IAutomatorFactory(factory).feeCollector()).tradingFeeRate() / 1e18;
                }
                if (earned < _positions[id]) {
                    fee -= int256((_positions[id] - earned) * feeRate / 1e18);
                }
                delete _positions[id];
            }
        }
        if (fee != 0) {
            totalFee += fee;
        }
        if (protocolFee > 0) {
            totalProtocolFee += protocolFee;
        }
        totalPositions -= _totalPositions;

        emit ProductsBurned(products, totalCollateral(), fee, protocolFee);
    }

    function harvest() external nonReentrant {
        require(totalFee > 0 || totalProtocolFee > 0, "Automator: zero fee");
        uint256 feeAmount = 0;
        uint256 protocolFeeAmount = 0;
        if (totalFee > 0) {
            feeAmount = pool.withdraw(address(collateral), uint256(totalFee), owner());
            totalFee = 0;
        }
        if (totalProtocolFee > 0) {
            protocolFeeAmount = pool.withdraw(address(collateral), totalProtocolFee, IAutomatorFactory(factory).feeCollector());
            totalProtocolFee = 0;
        }
        emit FeeCollected(_msgSender(), feeAmount, totalFee, protocolFeeAmount, totalProtocolFee);
    }

    function name() public view virtual override returns (string memory) {
        return string(abi.encodePacked("Automator ", IERC20Metadata(address(collateral)).name()));
    }

    function symbol() public view virtual override returns (string memory) {
        return symbol_;
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
            return totalCollateral() * 1e18 / totalSupply();
        }
    }

    function getUnredeemedCollateral() external view returns (uint256) {
        if (aToken.balanceOf(address(this)) > totalPendingRedemptions * getPricePerShare() / 1e18) {
            return aToken.balanceOf(address(this)) - totalPendingRedemptions * getPricePerShare() / 1e18;
        } else {
            return 0;
        }
    }

    function totalCollateral() public view returns (uint256) {
        if (totalFee > 0) {
            return aToken.balanceOf(address(this)) + totalPositions - uint256(totalFee) - totalProtocolFee;
        } else {
            return aToken.balanceOf(address(this)) + totalPositions - totalProtocolFee;
        }
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual override {
        if (from != address(0)) {
            require(balanceOf(from) >= amount + _redemptions[from].pendingRedemption, "Automator: invalid transfer amount");
        }
        super._beforeTokenTransfer(from, to, amount);
    }
}
