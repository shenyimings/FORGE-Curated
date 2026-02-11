// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/SignatureCheckerUpgradeable.sol";
// import "../interfaces/IWETH.sol";
import "../interfaces/ISmartTrendStrategy.sol";
import "../interfaces/ISpotOracle.sol";
import "../interfaces/IFeeCollector.sol";
import "../utils/SignatureBitMap.sol";

contract SmartTrendVault is Initializable, ContextUpgradeable, ERC1155Upgradeable, ReentrancyGuardUpgradeable, SignatureBitMap {
    using SafeERC20 for IERC20Metadata;
    using SignatureCheckerUpgradeable for address;

    struct Product {
        uint256 expiry;
        uint256[2] anchorPrices;
        uint256 isMaker;
    }
    struct MintParams {
        uint256 expiry;
        uint256[2] anchorPrices;
        uint256 makerCollateral;
        uint256 deadline;
        address maker;
        bytes makerSignature;
    }

    bytes32 public DOMAIN_SEPARATOR;
    // bytes32 public constant EIP712DOMAIN_TYPEHASH = keccak256(
    //     "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    // );
    bytes32 public constant EIP712DOMAIN_TYPEHASH = 0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f;
    // bytes32 public constant MINT_TYPEHASH = keccak256(
    //     "Mint(address minter,uint256 totalCollateral,uint256 expiry,uint256[2] anchorPrices,uint256 makerCollateral,uint256 deadline,address vault)"
    // );
    bytes32 public constant MINT_TYPEHASH = 0xe8015bbde99f68dcef36fec6eec1f414ef04b9f79422109663be9c2c47e3dc30;

    string public name;
    string public symbol;

    // IWETH public weth;
    ISmartTrendStrategy public strategy;
    IERC20Metadata public collateral;
    ISpotOracle public oracle;

    uint256 public totalFee;
    address public feeCollector;

    // Events
    event Minted(address minter, address maker, address referral, uint256 totalCollateral, uint256 expiry, uint256[2] anchorPrices, uint256 makerCollateral);
    event Burned(address operator, uint256 productId, uint256 amount, uint256 payoff);
    event BatchBurned(address operator, uint256[] productIds, uint256[] amounts, uint256[] payoffs);
    event FeeCollected(address collector, uint256 amount);

    // modifier onlyETHVault() {
    //     require(address(collateral) == address(weth), "Vault: only ETH vault");
    //     _;
    // }

    receive() external payable {}

    function initialize(
        string memory name_,
        string memory symbol_,
        ISmartTrendStrategy strategy_,
        // address weth_,
        address collateral_,
        address feeCollector_,
        ISpotOracle oracle_
    ) initializer external {
        name = name_;
        symbol = symbol_;

        // weth = IWETH(weth_);
        strategy = strategy_;

        collateral = IERC20Metadata(collateral_);
        oracle = oracle_;

        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                EIP712DOMAIN_TYPEHASH,
                keccak256("Vault"),
                keccak256("1.0"),
                block.chainid,
                address(this)
            )
        );
        feeCollector = feeCollector_;

        __Context_init();
        __ERC1155_init("");
        __ReentrancyGuard_init();
    }

    function mint(
        uint256 totalCollateral,
        MintParams calldata params,
        address referral
    ) external {
        // transfer collateral
        uint256 depositAmount = totalCollateral - params.makerCollateral;
        collateral.safeTransferFrom(_msgSender(), address(this), depositAmount);
        _mint(totalCollateral, params, referral);
    }

    // function mint(
    //     MintParams calldata params,
    //     address referral
    // ) external payable onlyETHVault {
    //     weth.deposit{value: msg.value}();
    //     _mint(
    //         params.makerCollateral + msg.value,
    //         params,
    //         referral
    //     );
    // }

    function _mint(uint256 totalCollateral, MintParams memory params, address referral) internal {
        require(block.timestamp < params.deadline, "Vault: deadline");
        require(block.timestamp < params.expiry, "Vault: expired");
        // require expiry must be 8:00 UTC
        require(params.expiry % 86400 == 28800, "Vault: invalid expiry");
        require(params.anchorPrices[0] < params.anchorPrices[1], "Vault: invalid strike prices");
        require(!isSignatureConsumed(params.makerSignature), "Vault: signature consumed");
        require(referral != _msgSender(), "Vault: invalid referral");

        {
        // verify maker's signature
        bytes32 digest =
            keccak256(abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR,
                keccak256(abi.encode(MINT_TYPEHASH,
                                     _msgSender(),
                                     totalCollateral,
                                     params.expiry,
                                     keccak256(abi.encodePacked(params.anchorPrices)),
                                     params.makerCollateral,
                                     params.deadline,
                                     address(this)))
        ));
        require(params.maker.isValidSignatureNow(digest, params.makerSignature), "Vault: invalid maker signature");
        consumeSignature(params.makerSignature);

        // transfer makerCollateral
        collateral.safeTransferFrom(params.maker, address(this), params.makerCollateral);
        }

        // trading fee
        uint256 tradingFee = IFeeCollector(feeCollector).tradingFeeRate() * (totalCollateral - params.makerCollateral) / 1e18;
        totalFee += tradingFee;

        // mint product
        uint256 productId = getProductId(params.expiry, params.anchorPrices, uint256(0));
        uint256 makerProductId = getProductId(params.expiry, params.anchorPrices, uint256(1));
        _mint(_msgSender(), productId, totalCollateral - tradingFee, "");
        _mint(params.maker, makerProductId, totalCollateral - tradingFee, "");

        emit Minted(_msgSender(), params.maker, referral, totalCollateral, params.expiry, params.anchorPrices, params.makerCollateral);
    }

    function mintBatch(
        uint256[] calldata totalCollaterals,
        MintParams[] calldata paramsArray,
        address referral
    ) external {
        require(totalCollaterals.length == paramsArray.length, "Vault: invalid params length");
        // transfer collateral
        uint256 depositAmount;
        for (uint256 i = 0; i < paramsArray.length; i++) {
            depositAmount += totalCollaterals[i] - paramsArray[i].makerCollateral;
        }
        collateral.safeTransferFrom(_msgSender(), address(this), depositAmount);
        _mintBatch(totalCollaterals, paramsArray, referral);
    }

    // function mintBatch(
    //     uint256[] calldata totalCollaterals,
    //     MintParams[] calldata paramsArray,
    //     address referral
    // ) external payable onlyETHVault {
    //     require(totalCollaterals.length == paramsArray.length, "Vault: invalid params length");
    //     // transfer collateral
    //     uint256 depositAmount;
    //     for (uint256 i = 0; i < paramsArray.length; i++) {
    //         depositAmount += totalCollaterals[i] - paramsArray[i].makerCollateral;
    //     }
    //     require(msg.value == depositAmount, "Vault: invalid msg.value");
    //     weth.deposit{value: msg.value}();

    //     _mintBatch(totalCollaterals, paramsArray, referral);
    // }

    function _mintBatch(uint256[] memory totalCollaterals, MintParams[] memory paramsArray, address referral) internal {
        require(referral != _msgSender(), "Vault: invalid referral");
        uint256[] memory productIds = new uint256[](paramsArray.length);
        uint256 tradingFee;
        for (uint256 i = 0; i < paramsArray.length; i++) {
            uint256 totalCollateral = totalCollaterals[i];
            MintParams memory params = paramsArray[i];
            require(block.timestamp < params.deadline, "Vault: deadline");
            require(block.timestamp < params.expiry, "Vault: expired");
            // require expiry must be 8:00 UTC
            require(params.expiry % 86400 == 28800, "Vault: invalid expiry");
            require(params.anchorPrices[0] < params.anchorPrices[1], "Vault: invalid strike prices");
            require(!isSignatureConsumed(params.makerSignature), "Vault: signature consumed");

            {
            // verify maker's signature
            bytes32 digest =
                keccak256(abi.encodePacked(
                                           "\x19\x01",
                                           DOMAIN_SEPARATOR,
                                           keccak256(abi.encode(MINT_TYPEHASH,
                                                                _msgSender(),
                                                                totalCollateral,
                                                                params.expiry,
                                                                keccak256(abi.encodePacked(params.anchorPrices)),
                                                                params.makerCollateral,
                                                                params.deadline,
                                                                address(this)))
                          ));
            require(params.maker.isValidSignatureNow(digest, params.makerSignature), "Vault: invalid maker signature");
            consumeSignature(params.makerSignature);

            // transfer makercollateral
            collateral.safeTransferFrom(params.maker, address(this), params.makerCollateral);
            }

            // trading fee
            uint256 fee = IFeeCollector(feeCollector).tradingFeeRate() * (totalCollateral - params.makerCollateral) / 1e18;
            tradingFee += fee;
            totalCollaterals[i] = totalCollateral - fee;

            // mint product
            productIds[i] = getProductId(params.expiry, params.anchorPrices, uint256(0));
            uint256 makerProductId = getProductId(params.expiry, params.anchorPrices, uint256(1));
            _mint(params.maker, makerProductId, totalCollateral - fee, "");

            emit Minted(_msgSender(), params.maker, referral, totalCollateral, params.expiry, params.anchorPrices, params.makerCollateral);
        }
        totalFee += tradingFee;
        _mintBatch(_msgSender(), productIds, totalCollaterals, "");
    }

    function burn(uint256 expiry, uint256[2] calldata anchorPrices, uint256 isMaker) external {
        uint256 payoff = _burn(expiry, anchorPrices, isMaker);
        if (payoff > 0) {
            collateral.safeTransfer(_msgSender(), payoff);
        }
    }

    // function ethBurn(uint256 expiry, uint256[2] calldata anchorPrices, uint256 isMaker) external onlyETHVault {
    //     uint256 payoff = _burn(expiry, anchorPrices, isMaker);
    //     if (payoff > 0) {
    //         weth.withdraw(payoff);
    //         (bool success, ) = _msgSender().call{value: payoff, gas: 100_000}("");
    //         require(success, "Failed to send ETH");
    //     }
    // }

    function _burn(uint256 expiry, uint256[2] memory anchorPrices, uint256 isMaker) internal nonReentrant returns (uint256 payoff) {
        require(block.timestamp >= expiry, "Vault: not expired");
        uint256 productId = getProductId(expiry, anchorPrices, isMaker);
        uint256 amount = balanceOf(_msgSender(), productId);
        require(amount > 0, "Vault: zero amount");

        // check if settled
        require(oracle.settlePrices(expiry) > 0, "Vault: not settled");

        // calculate payoff by strategy
        if (isMaker == 1) {
            payoff = getMakerPayoff(expiry, anchorPrices, amount);
        } else {
            uint256 settlementFee;
            (payoff, settlementFee) = getMinterPayoff(expiry, anchorPrices, amount);
            if (settlementFee > 0) {
                totalFee += settlementFee;
            }
        }

        // burn product
        _burn(_msgSender(), productId, amount);
        emit Burned(_msgSender(), productId, amount, payoff);
    }

    function burnBatch(Product[] calldata products) external {
        uint256 totalPayoff = _burnBatch(products);

        // check self balance of collateral and transfer payoff
        if (totalPayoff > 0) {
            collateral.safeTransfer(_msgSender(), totalPayoff);
        }
    }

    // function ethBurnBatch(Product[] calldata products) external onlyETHVault {
    //     uint256 totalPayoff = _burnBatch(products);

    //     // check self balance of collateral and transfer payoff
    //     if (totalPayoff > 0) {
    //         weth.withdraw(totalPayoff);
    //         (bool success, ) = _msgSender().call{value: totalPayoff, gas: 100_000}("");
    //         require(success, "Failed to send ETH");
    //     }
    // }

    function _burnBatch(Product[] calldata products) internal nonReentrant returns (uint256 totalPayoff) {
        uint256[] memory productIds = new uint256[](products.length);
        uint256[] memory amounts = new uint256[](products.length);
        uint256[] memory payoffs = new uint256[](products.length);
        uint256 settlementFee;
        for (uint256 i = 0; i < products.length; i++) {
            Product memory product = products[i];
            uint256 productId = getProductId(product.expiry, product.anchorPrices, product.isMaker);
            uint256 amount = balanceOf(_msgSender(), productId);
            require(amount > 0, "Vault: zero amount");
            require(block.timestamp >= product.expiry, "Vault: not expired");
            // check if settled
            require(oracle.settlePrices(product.expiry) > 0, "Vault: not settled");
            // calculate payoff by strategy
            if (product.isMaker == 1) {
                payoffs[i] = getMakerPayoff(product.expiry, product.anchorPrices, amount);
            } else {
                uint256 fee;
                (payoffs[i], fee) = getMinterPayoff(product.expiry, product.anchorPrices, amount);
                if (fee > 0) {
                    settlementFee += fee;
                }
            }
            if (payoffs[i] > 0) {
                totalPayoff += payoffs[i];
            }

            productIds[i] = productId;
            amounts[i] = amount;
        }
        if (settlementFee > 0) {
            totalFee += settlementFee;
        }
        // burn product
        _burnBatch(_msgSender(), productIds, amounts);
        emit BatchBurned(_msgSender(), productIds, amounts, payoffs);
    }

    // withdraw fee
    function harvest() external {
        uint256 fee = totalFee;
        require(fee > 0, "Vault: zero fee");
        totalFee = 0;
        collateral.safeTransfer(feeCollector, fee);

        emit FeeCollected(_msgSender(), fee);
    }

    function getMakerPayoff(uint256 expiry, uint256[2] memory anchorPrices, uint256 amount) public view returns (uint256 payoff) {
        payoff = strategy.getMakerPayoff(anchorPrices, oracle.settlePrices(expiry), amount);
    }

    function getMinterPayoff(uint256 expiry, uint256[2] memory anchorPrices, uint256 amount) public view returns (uint256 payoff, uint256 fee) {
        uint256 payoffWithFee = strategy.getMinterPayoff(anchorPrices, oracle.settlePrices(expiry), amount);
        fee = payoffWithFee * IFeeCollector(feeCollector).settlementFeeRate() / 1e18;
        payoff = payoffWithFee - fee;
    }

    // get product id by parameters
    function getProductId(uint256 expiry, uint256[2] memory anchorPrices, uint256 isMaker) public pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(expiry, anchorPrices, isMaker)));
    }

    // get decimals
    function decimals() external view returns (uint8) {
        return collateral.decimals();
    }

    uint256[50] private __gap;
}
