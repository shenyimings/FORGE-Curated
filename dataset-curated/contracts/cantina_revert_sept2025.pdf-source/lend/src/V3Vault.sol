
pragma solidity ^0.8.0;

import "v3-core/interfaces/IUniswapV3Factory.sol";
import "v3-core/interfaces/IUniswapV3Pool.sol";

import "v3-periphery/interfaces/INonfungiblePositionManager.sol";

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/utils/Multicall.sol";

import "permit2/interfaces/IPermit2.sol";

import "./interfaces/IVault.sol";
import "./interfaces/IV3Oracle.sol";
import "./interfaces/IInterestRateModel.sol";
import "./interfaces/IGaugeManager.sol";

import "./utils/Constants.sol";


contract V3Vault is ERC20, Multicall, Ownable2Step, IVault, IERC721Receiver, Constants {
    using Math for uint256;

    uint32 public constant MAX_COLLATERAL_FACTOR_X32 = uint32(Q32 * 90 / 100);

    uint32 public constant MIN_LIQUIDATION_PENALTY_X32 = uint32(Q32 * 2 / 100);
    uint32 public constant MAX_LIQUIDATION_PENALTY_X32 = uint32(Q32 * 10 / 100);

    uint32 public constant MIN_RESERVE_PROTECTION_FACTOR_X32 = uint32(Q32 / 100);

    uint32 public constant MAX_DAILY_LEND_INCREASE_X32 = uint32(Q32 / 10);
    uint32 public constant MAX_DAILY_DEBT_INCREASE_X32 = uint32(Q32 / 10);

    uint32 public constant BORROW_SAFETY_BUFFER_X32 = uint32(Q32 * 95 / 100);

    INonfungiblePositionManager public immutable nonfungiblePositionManager;

    IUniswapV3Factory public immutable factory;

    IInterestRateModel public immutable interestRateModel;

    IV3Oracle public immutable oracle;

    IPermit2 public immutable permit2;

    address public immutable override asset;

    uint8 private immutable assetDecimals;

    event ApprovedTransform(uint256 indexed tokenId, address owner, address target, bool isActive);

    event Add(uint256 indexed tokenId, address owner, uint256 oldTokenId);
    event Remove(uint256 indexed tokenId, address owner, address recipient);

    event ExchangeRateUpdate(uint256 debtExchangeRateX96, uint256 lendExchangeRateX96);
    
    event WithdrawCollateral(
        uint256 indexed tokenId, address owner, address recipient, uint128 liquidity, uint256 amount0, uint256 amount1
    );
    event Borrow(uint256 indexed tokenId, address owner, uint256 assets, uint256 shares);
    event Repay(uint256 indexed tokenId, address repayer, address owner, uint256 assets, uint256 shares);
    event Liquidate(
        uint256 indexed tokenId,
        address liquidator,
        address owner,
        uint256 value,
        uint256 cost,
        uint256 amount0,
        uint256 amount1,
        uint256 reserve,
        uint256 missing
    ); 

    event WithdrawReserves(uint256 amount, address receiver);
    event SetTransformer(address transformer, bool active);
    event SetLimits(
        uint256 minLoanSize,
        uint256 globalLendLimit,
        uint256 globalDebtLimit,
        uint256 dailyLendIncreaseLimitMin,
        uint256 dailyDebtIncreaseLimitMin
    );
    event SetReserveFactor(uint32 reserveFactorX32);
    
    event SetReserveProtectionFactor(uint32 reserveProtectionFactorX32);
    event SetTokenConfig(address token, uint32 collateralFactorX32, uint32 collateralValueLimitFactorX32);

    event SetEmergencyAdmin(address emergencyAdmin);

    struct TokenConfig {
        uint32 collateralFactorX32; 
        uint32 collateralValueLimitFactorX32; 
        uint192 totalDebtShares; 
    }

    mapping(address => TokenConfig) public tokenConfigs;

    uint256 public debtSharesTotal;

    uint256 public lastDebtExchangeRateX96 = Q96;
    uint256 public lastLendExchangeRateX96 = Q96;

    uint256 public globalDebtLimit;
    uint256 public globalLendLimit;

    uint256 public minLoanSize;

    uint256 public dailyLendIncreaseLimitMin;
    uint256 public dailyLendIncreaseLimitLeft;

    uint256 public dailyDebtIncreaseLimitMin;
    uint256 public dailyDebtIncreaseLimitLeft;

    struct Loan {
        uint256 debtShares;
    }

    mapping(uint256 => Loan) public override loans; 

    mapping(address => uint256[]) private ownedTokens; 
    mapping(uint256 => uint256) private ownedTokensIndex; 
    mapping(uint256 => address) private tokenOwner; 

    uint256 public override transformedTokenId; 

    mapping(address => bool) public transformerAllowList; 
    mapping(address => mapping(uint256 => mapping(address => bool))) public transformApprovals; 

    uint64 public lastExchangeRateUpdate;

    uint32 public reserveFactorX32;

    uint32 public reserveProtectionFactorX32 = MIN_RESERVE_PROTECTION_FACTOR_X32;

    uint32 public dailyLendIncreaseLimitLastReset;
    uint32 public dailyDebtIncreaseLimitLastReset;

    address public emergencyAdmin;
    
    // Gauge integration
    address public gaugeManager;

    constructor(
        string memory name,
        string memory symbol,
        address _asset,
        INonfungiblePositionManager _nonfungiblePositionManager,
        IInterestRateModel _interestRateModel,
        IV3Oracle _oracle,
        IPermit2 _permit2
    ) ERC20(name, symbol) {
        asset = _asset;
        assetDecimals = IERC20Metadata(_asset).decimals();
        nonfungiblePositionManager = _nonfungiblePositionManager;
        factory = IUniswapV3Factory(_nonfungiblePositionManager.factory());
        interestRateModel = _interestRateModel;
        oracle = _oracle;
        permit2 = _permit2;
    }

    function vaultInfo()
        external
        view
        override
        returns (
            uint256 debt,
            uint256 lent,
            uint256 balance,
            uint256 reserves,
            uint256 debtExchangeRateX96,
            uint256 lendExchangeRateX96
        )
    {
        (debtExchangeRateX96, lendExchangeRateX96) = _calculateGlobalInterest();
        (balance, reserves) = _getBalanceAndReserves(debtExchangeRateX96, lendExchangeRateX96);

        debt = _convertToAssets(debtSharesTotal, debtExchangeRateX96, Math.Rounding.Up);
        lent = _convertToAssets(totalSupply(), lendExchangeRateX96, Math.Rounding.Down);
    }

    function lendInfo(address account) external view override returns (uint256 amount) {
        (, uint256 newLendExchangeRateX96) = _calculateGlobalInterest();
        amount = _convertToAssets(balanceOf(account), newLendExchangeRateX96, Math.Rounding.Down);
    }

    function loanInfo(uint256 tokenId)
        external
        view
        override
        returns (
            uint256 debt,
            uint256 fullValue,
            uint256 collateralValue,
            uint256 liquidationCost,
            uint256 liquidationValue
        )
    {
        (uint256 newDebtExchangeRateX96,) = _calculateGlobalInterest();

        debt = _convertToAssets(loans[tokenId].debtShares, newDebtExchangeRateX96, Math.Rounding.Up);

        bool isHealthy;
        (isHealthy, fullValue, collateralValue,) = _checkLoanIsHealthy(tokenId, debt, false);

        if (!isHealthy) {
            (liquidationValue, liquidationCost,) = _calculateLiquidation(debt, fullValue, collateralValue);
        }
    }

    function ownerOf(uint256 tokenId) public view override returns (address owner) {
        return tokenOwner[tokenId];
    }

    function loanCount(address owner) external view override returns (uint256) {
        return ownedTokens[owner].length;
    }

    function loanAtIndex(address owner, uint256 index) external view override returns (uint256) {
        return ownedTokens[owner][index];
    }

    function decimals() public view override(IERC20Metadata, ERC20) returns (uint8) {
        return assetDecimals;
    }

    function totalAssets() public view override returns (uint256) {
        return IERC20(asset).balanceOf(address(this));
    }

    function convertToShares(uint256 assets) external view override returns (uint256 shares) {
        (, uint256 lendExchangeRateX96) = _calculateGlobalInterest();
        return _convertToShares(assets, lendExchangeRateX96, Math.Rounding.Down);
    }

    function convertToAssets(uint256 shares) external view override returns (uint256 assets) {
        (, uint256 lendExchangeRateX96) = _calculateGlobalInterest();
        return _convertToAssets(shares, lendExchangeRateX96, Math.Rounding.Down);
    }

    function maxDeposit(address) external view override returns (uint256) {
        (, uint256 lendExchangeRateX96) = _calculateGlobalInterest();
        uint256 value = _convertToAssets(totalSupply(), lendExchangeRateX96, Math.Rounding.Up);
        if (value >= globalLendLimit) {
            return 0;
        } else {
            uint256 maxGlobalDeposit = globalLendLimit - value;
            if (maxGlobalDeposit > dailyLendIncreaseLimitLeft) {
                return dailyLendIncreaseLimitLeft;
            } else {
                return maxGlobalDeposit;
            }
        }
    }

    function maxMint(address) external view override returns (uint256) {
        (, uint256 lendExchangeRateX96) = _calculateGlobalInterest();
        uint256 value = _convertToAssets(totalSupply(), lendExchangeRateX96, Math.Rounding.Up);
        if (value >= globalLendLimit) {
            return 0;
        } else {
            uint256 maxGlobalDeposit = globalLendLimit - value;
            if (maxGlobalDeposit > dailyLendIncreaseLimitLeft) {
                return _convertToShares(dailyLendIncreaseLimitLeft, lendExchangeRateX96, Math.Rounding.Down);
            } else {
                return _convertToShares(maxGlobalDeposit, lendExchangeRateX96, Math.Rounding.Down);
            }
        }
    }

    function maxWithdraw(address owner) external view override returns (uint256) {
        (uint256 debtExchangeRateX96, uint256 lendExchangeRateX96) = _calculateGlobalInterest();

        uint256 ownerShareBalance = balanceOf(owner);
        uint256 ownerAssetBalance = _convertToAssets(ownerShareBalance, lendExchangeRateX96, Math.Rounding.Down);

        (uint256 balance,) = _getBalanceAndReserves(debtExchangeRateX96, lendExchangeRateX96);
        if (balance > ownerAssetBalance) {
            return ownerAssetBalance;
        } else {
            return balance;
        }
    }

    function maxRedeem(address owner) external view override returns (uint256) {
        (uint256 debtExchangeRateX96, uint256 lendExchangeRateX96) = _calculateGlobalInterest();

        uint256 ownerShareBalance = balanceOf(owner);

        (uint256 balance,) = _getBalanceAndReserves(debtExchangeRateX96, lendExchangeRateX96);
        uint256 shareBalance = _convertToShares(balance, lendExchangeRateX96, Math.Rounding.Down);

        if (shareBalance > ownerShareBalance) {
            return ownerShareBalance;
        } else {
            return shareBalance;
        }
    }

    function previewDeposit(uint256 assets) external view override returns (uint256) {
        (, uint256 lendExchangeRateX96) = _calculateGlobalInterest();
        return _convertToShares(assets, lendExchangeRateX96, Math.Rounding.Down);
    }

    function previewMint(uint256 shares) external view override returns (uint256) {
        (, uint256 lendExchangeRateX96) = _calculateGlobalInterest();
        return _convertToAssets(shares, lendExchangeRateX96, Math.Rounding.Up);
    }

    function previewWithdraw(uint256 assets) external view override returns (uint256) {
        (, uint256 lendExchangeRateX96) = _calculateGlobalInterest();
        return _convertToShares(assets, lendExchangeRateX96, Math.Rounding.Up);
    }

    function previewRedeem(uint256 shares) external view override returns (uint256) {
        (, uint256 lendExchangeRateX96) = _calculateGlobalInterest();
        return _convertToAssets(shares, lendExchangeRateX96, Math.Rounding.Down);
    }

    function deposit(uint256 assets, address receiver) external override returns (uint256) {
        (, uint256 shares) = _deposit(receiver, assets, false, "");
        return shares;
    }

    function mint(uint256 shares, address receiver) external override returns (uint256) {
        (uint256 assets,) = _deposit(receiver, shares, true, "");
        return assets;
    }

    function withdraw(uint256 assets, address receiver, address owner) external override returns (uint256) {
        (, uint256 shares) = _withdraw(receiver, owner, assets, false);
        return shares;
    }

    function redeem(uint256 shares, address receiver, address owner) external override returns (uint256) {
        (uint256 assets,) = _withdraw(receiver, owner, shares, true);
        return assets;
    }

    function deposit(uint256 assets, address receiver, bytes calldata permitData) external override returns (uint256) {
        (, uint256 shares) = _deposit(receiver, assets, false, permitData);
        return shares;
    }

    function mint(uint256 shares, address receiver, bytes calldata permitData) external override returns (uint256) {
        (uint256 assets,) = _deposit(receiver, shares, true, permitData);
        return assets;
    }

    function create(uint256 tokenId, address recipient) external override {
        nonfungiblePositionManager.safeTransferFrom(msg.sender, address(this), tokenId, abi.encode(recipient));
    }

    function createWithPermit(uint256 tokenId, address recipient, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external
        override
    {
        nonfungiblePositionManager.permit(address(this), tokenId, deadline, v, r, s);
        nonfungiblePositionManager.safeTransferFrom(msg.sender, address(this), tokenId, abi.encode(recipient));
    }

    function onERC721Received(address,  address from, uint256 tokenId, bytes calldata data)
        external
        override
        returns (bytes4)
    {
        
        if (msg.sender != address(nonfungiblePositionManager) || from == address(this)) {
            revert WrongContract();
        }

        (uint256 debtExchangeRateX96, uint256 lendExchangeRateX96) = _updateGlobalInterest();

        uint256 oldTokenId = transformedTokenId;

        if (oldTokenId == 0) {
            address owner = from;
            if (data.length != 0) {
                owner = abi.decode(data, (address));
            }
            loans[tokenId] = Loan(0);

            _addTokenToOwner(owner, tokenId);
            emit Add(tokenId, owner, 0);
        } else {
            
            if (tokenId != oldTokenId) {
                address owner = tokenOwner[oldTokenId];

                transformedTokenId = tokenId;

                uint256 debtShares = loans[oldTokenId].debtShares;

                loans[tokenId] = Loan(debtShares);

                _addTokenToOwner(owner, tokenId);
                emit Add(tokenId, owner, oldTokenId);

                _cleanupLoan(oldTokenId, debtExchangeRateX96, lendExchangeRateX96);

                _updateAndCheckCollateral(
                    tokenId, debtExchangeRateX96, lendExchangeRateX96, 0, debtShares
                );
            }
        }

        return IERC721Receiver.onERC721Received.selector;
    }

    function approveTransform(uint256 tokenId, address target, bool isActive) external override {
        if (tokenOwner[tokenId] != msg.sender) {
            revert Unauthorized();
        }
        transformApprovals[msg.sender][tokenId][target] = isActive;

        emit ApprovedTransform(tokenId, msg.sender, target, isActive);
    }

    function transform(uint256 tokenId, address transformer, bytes calldata data)
        external
        override
        returns (uint256 newTokenId)
    {
        if (tokenId == 0 || !transformerAllowList[transformer]) {
            revert TransformNotAllowed();
        }
        if (transformedTokenId != 0) {
            revert Reentrancy();
        }
        transformedTokenId = tokenId;

        (uint256 newDebtExchangeRateX96,) = _updateGlobalInterest();

        address loanOwner = tokenOwner[tokenId];

        if (loanOwner != msg.sender && !transformApprovals[loanOwner][tokenId][msg.sender]) {
            revert Unauthorized();
        }

        // Track if position was staked before transformation
        bool wasStaked = gaugeManager != address(0) && IGaugeManager(gaugeManager).tokenIdToGauge(tokenId) != address(0);
        
        // Unstake position if it's in a gauge (for liquidations/transformations)
        if (wasStaked) {
            _unstakeForLiquidation(tokenId);
        }

        nonfungiblePositionManager.approve(transformer, tokenId);

        (bool success,) = transformer.call(data);
        if (!success) {
            revert TransformFailed();
        }

        newTokenId = transformedTokenId;

        if (tokenId != newTokenId && transformApprovals[loanOwner][tokenId][msg.sender]) {
            transformApprovals[loanOwner][newTokenId][msg.sender] = true;
            delete transformApprovals[loanOwner][tokenId][msg.sender];
        }

        address owner = nonfungiblePositionManager.ownerOf(newTokenId);
        if (owner != address(this)) {
            revert Unauthorized();
        }

        nonfungiblePositionManager.approve(address(0), newTokenId);

        uint256 debt = _convertToAssets(loans[newTokenId].debtShares, newDebtExchangeRateX96, Math.Rounding.Up);
        _requireLoanIsHealthy(newTokenId, debt, false);

        transformedTokenId = 0;
        
        // Re-stake the position if it was previously staked
        if (wasStaked) {
            nonfungiblePositionManager.approve(gaugeManager, newTokenId);
            IGaugeManager(gaugeManager).stakePosition(newTokenId);
        }
    }

    function borrow(uint256 tokenId, uint256 assets) external override {

        bool isTransformMode = tokenId != 0 && transformedTokenId == tokenId && transformerAllowList[msg.sender];

        address owner = tokenOwner[tokenId];

        if (!isTransformMode && owner != msg.sender) {
            revert Unauthorized();
        }

        (uint256 newDebtExchangeRateX96, uint256 newLendExchangeRateX96) = _updateGlobalInterest();

        _resetDailyDebtIncreaseLimit(newLendExchangeRateX96, false);

        Loan storage loan = loans[tokenId];

        uint256 shares = _convertToShares(assets, newDebtExchangeRateX96, Math.Rounding.Up);

        uint256 loanDebtShares = loan.debtShares + shares;
        loan.debtShares = loanDebtShares;
        debtSharesTotal = debtSharesTotal + shares;

        if (debtSharesTotal > _convertToShares(globalDebtLimit, newDebtExchangeRateX96, Math.Rounding.Down)) {
            revert GlobalDebtLimit();
        }
        if (assets > dailyDebtIncreaseLimitLeft) {
            revert DailyDebtIncreaseLimit();
        } else {
            dailyDebtIncreaseLimitLeft = dailyDebtIncreaseLimitLeft - assets;
        }

        _updateAndCheckCollateral(
            tokenId, newDebtExchangeRateX96, newLendExchangeRateX96, loanDebtShares - shares, loanDebtShares
        );

        uint256 debt = _convertToAssets(loanDebtShares, newDebtExchangeRateX96, Math.Rounding.Up);

        if (debt < minLoanSize) {
            revert MinLoanSize();
        }

        if (!isTransformMode) {
            _requireLoanIsHealthy(tokenId, debt, true);
        }

        SafeERC20.safeTransfer(IERC20(asset), msg.sender, assets);

        emit Borrow(tokenId, owner, assets, shares);
    }

    function decreaseLiquidityAndCollect(DecreaseLiquidityAndCollectParams calldata params)
        external
        override
        returns (uint256 amount0, uint256 amount1)
    {
        
        if (transformedTokenId != 0) {
            revert TransformNotAllowed();
        }

        address owner = tokenOwner[params.tokenId];

        if (owner != msg.sender) {
            revert Unauthorized();
        }

        (uint256 newDebtExchangeRateX96,) = _updateGlobalInterest();

        if (params.liquidity != 0) {
            (amount0, amount1) = nonfungiblePositionManager.decreaseLiquidity(
                INonfungiblePositionManager.DecreaseLiquidityParams(
                    params.tokenId, params.liquidity, params.amount0Min, params.amount1Min, params.deadline
                )
            );
        }

        INonfungiblePositionManager.CollectParams memory collectParams = INonfungiblePositionManager.CollectParams(
            params.tokenId,
            params.recipient,
            params.feeAmount0 == type(uint128).max ? type(uint128).max : SafeCast.toUint128(amount0 + params.feeAmount0),
            params.feeAmount1 == type(uint128).max ? type(uint128).max : SafeCast.toUint128(amount1 + params.feeAmount1)
        );

        (amount0, amount1) = nonfungiblePositionManager.collect(collectParams);

        uint256 debt = _convertToAssets(loans[params.tokenId].debtShares, newDebtExchangeRateX96, Math.Rounding.Up);
        _requireLoanIsHealthy(params.tokenId, debt, true);

        emit WithdrawCollateral(params.tokenId, owner, params.recipient, params.liquidity, amount0, amount1);
    }

    function repay(uint256 tokenId, uint256 amount, bool isShare)
        external
        override
        returns (uint256 assets, uint256 shares)
    {
        (assets, shares) = _repay(tokenId, amount, isShare, "");
    }

    function repay(uint256 tokenId, uint256 amount, bool isShare, bytes calldata permitData)
        external
        override
        returns (uint256 assets, uint256 shares)
    {
        (assets, shares) = _repay(tokenId, amount, isShare, permitData);
    }

    struct LiquidateState {
        uint256 newDebtExchangeRateX96;
        uint256 newLendExchangeRateX96;
        uint256 debt;
        bool isHealthy;
        uint256 liquidationValue;
        uint256 liquidatorCost;
        uint256 reserveCost;
        uint256 missing;
        uint256 fullValue;
        uint256 collateralValue;
        uint256 feeValue;
    }

    function liquidate(LiquidateParams calldata params) external override returns (uint256 amount0, uint256 amount1) {
        
        if (transformedTokenId != 0) {
            revert TransformNotAllowed();
        }

        _unstakeForLiquidation(params.tokenId);

        LiquidateState memory state;

        (state.newDebtExchangeRateX96, state.newLendExchangeRateX96) = _updateGlobalInterest();

        _resetDailyDebtIncreaseLimit(state.newLendExchangeRateX96, false);

        uint256 debtShares = loans[params.tokenId].debtShares;

        state.debt = _convertToAssets(debtShares, state.newDebtExchangeRateX96, Math.Rounding.Up);

        (state.isHealthy, state.fullValue, state.collateralValue, state.feeValue) =
            _checkLoanIsHealthy(params.tokenId, state.debt, false);
        if (state.isHealthy) {
            revert NotLiquidatable();
        }

        (state.liquidationValue, state.liquidatorCost, state.reserveCost) =
            _calculateLiquidation(state.debt, state.fullValue, state.collateralValue);

        if (state.reserveCost != 0) {
            state.missing =
                _handleReserveLiquidation(state.reserveCost, state.newDebtExchangeRateX96, state.newLendExchangeRateX96);
        }

        if (state.liquidatorCost != 0) {
            if (params.permitData.length != 0) {
                (ISignatureTransfer.PermitTransferFrom memory permit, bytes memory signature) =
                    abi.decode(params.permitData, (ISignatureTransfer.PermitTransferFrom, bytes));

                if (permit.permitted.token != asset) {
                    revert InvalidToken();
                }

                permit2.permitTransferFrom(
                    permit,
                    ISignatureTransfer.SignatureTransferDetails(address(this), state.liquidatorCost),
                    msg.sender,
                    signature
                );
            } else {
                
                SafeERC20.safeTransferFrom(IERC20(asset), msg.sender, address(this), state.liquidatorCost);
            }
        }

        debtSharesTotal = debtSharesTotal - debtShares;

        dailyDebtIncreaseLimitLeft = dailyDebtIncreaseLimitLeft + state.debt;

        (amount0, amount1) = _sendPositionValue(
            params.tokenId, state.liquidationValue, state.fullValue, state.feeValue, params.recipient, params.deadline
        );

        if (amount0 < params.amount0Min || amount1 < params.amount1Min) {
            revert SlippageError();
        }

        _cleanupLoan(params.tokenId, state.newDebtExchangeRateX96, state.newLendExchangeRateX96);

        emit Liquidate(
            params.tokenId,
            msg.sender,
            tokenOwner[params.tokenId],
            state.fullValue,
            state.liquidatorCost,
            amount0,
            amount1,
            state.reserveCost,
            state.missing
        );
    }

    function remove(uint256 tokenId, address recipient, bytes calldata data) external {
        address owner = tokenOwner[tokenId];
        if (owner != msg.sender) {
            revert Unauthorized();
        }

        if (loans[tokenId].debtShares != 0) {
            revert NeedsRepay();
        }

        _unstakeForLiquidation(tokenId);

        _removeTokenFromOwner(owner, tokenId);

        nonfungiblePositionManager.safeTransferFrom(address(this), recipient, tokenId, data);
        emit Remove(tokenId, owner, recipient);
    }



    function withdrawReserves(uint256 amount, address receiver) external onlyOwner {
        (uint256 newDebtExchangeRateX96, uint256 newLendExchangeRateX96) = _updateGlobalInterest();

        uint256 protected =
            _convertToAssets(totalSupply(), newLendExchangeRateX96, Math.Rounding.Up) * reserveProtectionFactorX32 / Q32;
        (uint256 balance, uint256 reserves) = _getBalanceAndReserves(newDebtExchangeRateX96, newLendExchangeRateX96);
        uint256 unprotected = reserves > protected ? reserves - protected : 0;
        uint256 available = balance > unprotected ? unprotected : balance;

        if (amount > available) {
            revert InsufficientLiquidity();
        }

        if (amount != 0) {
            SafeERC20.safeTransfer(IERC20(asset), receiver, amount);
        }

        emit WithdrawReserves(amount, receiver);
    }

    function setTransformer(address transformer, bool active) external onlyOwner {
        
        if (
            transformer == address(0) || transformer == address(this) || transformer == asset
                || transformer == address(nonfungiblePositionManager)
        ) {
            revert InvalidConfig();
        }

        transformerAllowList[transformer] = active;
        emit SetTransformer(transformer, active);
    }

    function setLimits(
        uint256 _minLoanSize,
        uint256 _globalLendLimit,
        uint256 _globalDebtLimit,
        uint256 _dailyLendIncreaseLimitMin,
        uint256 _dailyDebtIncreaseLimitMin
    ) external {
        if (msg.sender != emergencyAdmin && msg.sender != owner()) {
            revert Unauthorized();
        }

        minLoanSize = _minLoanSize;
        globalLendLimit = _globalLendLimit;
        globalDebtLimit = _globalDebtLimit;
        dailyLendIncreaseLimitMin = _dailyLendIncreaseLimitMin;
        dailyDebtIncreaseLimitMin = _dailyDebtIncreaseLimitMin;

        (, uint256 newLendExchangeRateX96) = _updateGlobalInterest();

        _resetDailyLendIncreaseLimit(newLendExchangeRateX96, true);
        _resetDailyDebtIncreaseLimit(newLendExchangeRateX96, true);

        emit SetLimits(
            _minLoanSize, _globalLendLimit, _globalDebtLimit, _dailyLendIncreaseLimitMin, _dailyDebtIncreaseLimitMin
        );
    }

    function setReserveFactor(uint32 _reserveFactorX32) external onlyOwner {
        
        _updateGlobalInterest();
        reserveFactorX32 = _reserveFactorX32;
        emit SetReserveFactor(_reserveFactorX32);
    }

    function setReserveProtectionFactor(uint32 _reserveProtectionFactorX32) external onlyOwner {
        if (_reserveProtectionFactorX32 < MIN_RESERVE_PROTECTION_FACTOR_X32) {
            revert InvalidConfig();
        }
        reserveProtectionFactorX32 = _reserveProtectionFactorX32;
        emit SetReserveProtectionFactor(_reserveProtectionFactorX32);
    }

    function setTokenConfig(address token, uint32 collateralFactorX32, uint32 collateralValueLimitFactorX32)
        external
        onlyOwner
    {
        if (collateralFactorX32 > MAX_COLLATERAL_FACTOR_X32) {
            revert CollateralFactorExceedsMax();
        }
        TokenConfig storage config = tokenConfigs[token];
        config.collateralFactorX32 = collateralFactorX32;
        config.collateralValueLimitFactorX32 = collateralValueLimitFactorX32;
        emit SetTokenConfig(token, collateralFactorX32, collateralValueLimitFactorX32);
    }

    function setEmergencyAdmin(address admin) external onlyOwner {
        emergencyAdmin = admin;
        emit SetEmergencyAdmin(admin);
    }



    function _deposit(address receiver, uint256 amount, bool isShare, bytes memory permitData)
        internal
        returns (uint256 assets, uint256 shares)
    {
        (, uint256 newLendExchangeRateX96) = _updateGlobalInterest();

        _resetDailyLendIncreaseLimit(newLendExchangeRateX96, false);

        if (isShare) {
            shares = amount;
            assets = _convertToAssets(shares, newLendExchangeRateX96, Math.Rounding.Up);
        } else {
            assets = amount;
            shares = _convertToShares(assets, newLendExchangeRateX96, Math.Rounding.Down);
        }

        uint256 newTotalAssets = _convertToAssets(totalSupply() + shares, newLendExchangeRateX96, Math.Rounding.Up);
        if (newTotalAssets > globalLendLimit) {
            revert GlobalLendLimit();
        }
        if (assets > dailyLendIncreaseLimitLeft) {
            revert DailyLendIncreaseLimit();
        }

        dailyLendIncreaseLimitLeft = dailyLendIncreaseLimitLeft - assets;

        if (permitData.length != 0) {
            (ISignatureTransfer.PermitTransferFrom memory permit, bytes memory signature) =
                abi.decode(permitData, (ISignatureTransfer.PermitTransferFrom, bytes));

            if (permit.permitted.token != asset) {
                revert InvalidToken();
            }

            permit2.permitTransferFrom(
                permit, ISignatureTransfer.SignatureTransferDetails(address(this), assets), msg.sender, signature
            );
        } else {
            
            SafeERC20.safeTransferFrom(IERC20(asset), msg.sender, address(this), assets);
        }

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    function _withdraw(address receiver, address owner, uint256 amount, bool isShare)
        internal
        returns (uint256 assets, uint256 shares)
    {
        (uint256 newDebtExchangeRateX96, uint256 newLendExchangeRateX96) = _updateGlobalInterest();
        _resetDailyLendIncreaseLimit(newLendExchangeRateX96, false);

        if (isShare) {
            shares = amount;
            assets = _convertToAssets(amount, newLendExchangeRateX96, Math.Rounding.Down);
        } else {
            assets = amount;
            shares = _convertToShares(amount, newLendExchangeRateX96, Math.Rounding.Up);
        }

        uint256 ownerBalance = balanceOf(owner);
        if (shares > ownerBalance) {
            shares = ownerBalance;
            assets = _convertToAssets(shares, newLendExchangeRateX96, Math.Rounding.Down);
        }

        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, shares);
        }

        (uint256 balance,) = _getBalanceAndReserves(newDebtExchangeRateX96, newLendExchangeRateX96);
        if (balance < assets) {
            revert InsufficientLiquidity();
        }

        _burn(owner, shares);
        
        dailyLendIncreaseLimitLeft = dailyLendIncreaseLimitLeft + assets;
        
        SafeERC20.safeTransfer(IERC20(asset), receiver, assets);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);
    }

    function _repay(uint256 tokenId, uint256 amount, bool isShare, bytes memory permitData)
        internal
        returns (uint256 assets, uint256 shares)
    {
        (uint256 newDebtExchangeRateX96, uint256 newLendExchangeRateX96) = _updateGlobalInterest();
        _resetDailyDebtIncreaseLimit(newLendExchangeRateX96, false);

        Loan storage loan = loans[tokenId];

        uint256 currentShares = loan.debtShares;

        if (isShare) {
            shares = amount;
            assets = _convertToAssets(amount, newDebtExchangeRateX96, Math.Rounding.Up);
        } else {
            assets = amount;
            shares = _convertToShares(amount, newDebtExchangeRateX96, Math.Rounding.Down);
        }

        if (shares == 0) {
            revert NoSharesRepayed();
        }

        if (shares > currentShares) {
            shares = currentShares;
            assets = _convertToAssets(shares, newDebtExchangeRateX96, Math.Rounding.Up);
        }

        if (assets != 0) {
            if (permitData.length != 0) {
                (ISignatureTransfer.PermitTransferFrom memory permit, bytes memory signature) =
                    abi.decode(permitData, (ISignatureTransfer.PermitTransferFrom, bytes));

                if (permit.permitted.token != asset) {
                    revert InvalidToken();
                }

                permit2.permitTransferFrom(
                    permit, ISignatureTransfer.SignatureTransferDetails(address(this), assets), msg.sender, signature
                );
            } else {
                
                SafeERC20.safeTransferFrom(IERC20(asset), msg.sender, address(this), assets);
            }
        }

        uint256 loanDebtShares = currentShares - shares;
        loan.debtShares = loanDebtShares;
        debtSharesTotal = debtSharesTotal - shares;

        dailyDebtIncreaseLimitLeft = dailyDebtIncreaseLimitLeft + assets;

        _updateAndCheckCollateral(
            tokenId, newDebtExchangeRateX96, newLendExchangeRateX96, loanDebtShares + shares, loanDebtShares
        );

        if (currentShares != shares) {
            
            if (_convertToAssets(loanDebtShares, newDebtExchangeRateX96, Math.Rounding.Up) < minLoanSize) {
                revert MinLoanSize();
            }
        }

        emit Repay(tokenId, msg.sender, tokenOwner[tokenId], assets, shares);
    }

    function _getBalanceAndReserves(uint256 debtExchangeRateX96, uint256 lendExchangeRateX96)
        internal
        view
        returns (uint256 balance, uint256 reserves)
    {
        balance = totalAssets();
        uint256 debt = _convertToAssets(debtSharesTotal, debtExchangeRateX96, Math.Rounding.Up);
        uint256 lent = _convertToAssets(totalSupply(), lendExchangeRateX96, Math.Rounding.Up);
        unchecked {
            reserves = balance + debt > lent ? balance + debt - lent : 0;
        }
    }

    function _sendPositionValue(
        uint256 tokenId,
        uint256 liquidationValue,
        uint256 fullValue,
        uint256 feeValue,
        address recipient,
        uint256 deadline
    ) internal returns (uint256 amount0, uint256 amount1) {
        uint128 liquidity;
        uint128 fees0;
        uint128 fees1;

        if (liquidationValue == fullValue) {
            (,,,,,,, liquidity,,,,) = nonfungiblePositionManager.positions(tokenId);
            fees0 = type(uint128).max;
            fees1 = type(uint128).max;
        } else {
            (liquidity, fees0, fees1) = oracle.getLiquidityAndFees(tokenId);

            if (liquidationValue <= feeValue) {
                liquidity = 0;
                unchecked {
                    fees0 = SafeCast.toUint128(liquidationValue * fees0 / feeValue);
                    fees1 = SafeCast.toUint128(liquidationValue * fees1 / feeValue);
                }
            } else {
                
                fees0 = type(uint128).max;
                fees1 = type(uint128).max;
                unchecked {
                    liquidity = SafeCast.toUint128((liquidationValue - feeValue) * liquidity / (fullValue - feeValue));
                }
            }
        }

        if (liquidity != 0) {
            nonfungiblePositionManager.decreaseLiquidity(
                INonfungiblePositionManager.DecreaseLiquidityParams(tokenId, liquidity, 0, 0, deadline)
            );
        }

        (amount0, amount1) = nonfungiblePositionManager.collect(
            INonfungiblePositionManager.CollectParams(tokenId, recipient, fees0, fees1)
        );
    }

    function _cleanupLoan(uint256 tokenId, uint256 debtExchangeRateX96, uint256 lendExchangeRateX96) internal {
        _updateAndCheckCollateral(tokenId, debtExchangeRateX96, lendExchangeRateX96, loans[tokenId].debtShares, 0);
        delete loans[tokenId];
    }

    function _calculateLiquidation(uint256 debt, uint256 fullValue, uint256 collateralValue)
        internal
        pure
        returns (uint256 liquidationValue, uint256 liquidatorCost, uint256 reserveCost)
    {

        liquidatorCost = debt;

        uint256 maxPenaltyValue = debt * (Q32 + MAX_LIQUIDATION_PENALTY_X32) / Q32;

        if (fullValue >= maxPenaltyValue) {
            if (collateralValue != 0) {
                
                uint256 startLiquidationValue = debt * fullValue / collateralValue;
                uint256 penaltyFractionX96 =
                    (Q96 - ((fullValue - maxPenaltyValue) * Q96 / (startLiquidationValue - maxPenaltyValue)));
                uint256 penaltyX32 = MIN_LIQUIDATION_PENALTY_X32
                    + (MAX_LIQUIDATION_PENALTY_X32 - MIN_LIQUIDATION_PENALTY_X32) * penaltyFractionX96 / Q96;

                liquidationValue = debt * (Q32 + penaltyX32) / Q32;
            } else {
                liquidationValue = maxPenaltyValue;
            }
        } else {
            uint256 penalty = debt * MAX_LIQUIDATION_PENALTY_X32 / Q32;

            if (fullValue > penalty) {
                liquidatorCost = fullValue - penalty;
            } else {
                
                liquidatorCost = 0;
            }

            liquidationValue = fullValue;
            unchecked {
                reserveCost = debt - liquidatorCost;
            } 
        }
    }

    function _handleReserveLiquidation(
        uint256 reserveCost,
        uint256 newDebtExchangeRateX96,
        uint256 newLendExchangeRateX96
    ) internal returns (uint256 missing) {
        (, uint256 reserves) = _getBalanceAndReserves(newDebtExchangeRateX96, newLendExchangeRateX96);

        if (reserveCost > reserves) {
            missing = reserveCost - reserves;

            uint256 totalLent = _convertToAssets(totalSupply(), newLendExchangeRateX96, Math.Rounding.Up);

            newLendExchangeRateX96 = (totalLent - missing) * newLendExchangeRateX96 / totalLent;
            lastLendExchangeRateX96 = newLendExchangeRateX96;
            emit ExchangeRateUpdate(newDebtExchangeRateX96, newLendExchangeRateX96);
        }
    }

    function _calculateTokenCollateralFactorX32(uint256 tokenId) internal view returns (uint32) {
        (,, address token0, address token1,,,,,,,,) = nonfungiblePositionManager.positions(tokenId);
        uint32 factor0X32 = tokenConfigs[token0].collateralFactorX32;
        uint32 factor1X32 = tokenConfigs[token1].collateralFactorX32;
        return factor0X32 > factor1X32 ? factor1X32 : factor0X32;
    }

    function _updateGlobalInterest()
        internal
        returns (uint256 newDebtExchangeRateX96, uint256 newLendExchangeRateX96)
    {
        
        if (block.timestamp > lastExchangeRateUpdate) {
            (newDebtExchangeRateX96, newLendExchangeRateX96) = _calculateGlobalInterest();
            lastDebtExchangeRateX96 = newDebtExchangeRateX96;
            lastLendExchangeRateX96 = newLendExchangeRateX96;
            lastExchangeRateUpdate = uint64(block.timestamp); 
            emit ExchangeRateUpdate(newDebtExchangeRateX96, newLendExchangeRateX96);
        } else {
            newDebtExchangeRateX96 = lastDebtExchangeRateX96;
            newLendExchangeRateX96 = lastLendExchangeRateX96;
        }
    }

    function _calculateGlobalInterest()
        internal
        view
        returns (uint256 newDebtExchangeRateX96, uint256 newLendExchangeRateX96)
    {
        uint256 oldDebtExchangeRateX96 = lastDebtExchangeRateX96;
        uint256 oldLendExchangeRateX96 = lastLendExchangeRateX96;

        uint256 lastRateUpdate = lastExchangeRateUpdate;
        uint256 timeElapsed = (block.timestamp - lastRateUpdate);

        if (timeElapsed != 0 && lastRateUpdate != 0) {

            (uint256 balance,) = _getBalanceAndReserves(oldDebtExchangeRateX96, oldLendExchangeRateX96);
            uint256 debt = _convertToAssets(debtSharesTotal, oldDebtExchangeRateX96, Math.Rounding.Up);
            (uint256 borrowRateX64, uint256 supplyRateX64) = interestRateModel.getRatesPerSecondX64(balance, debt);
            supplyRateX64 = supplyRateX64.mulDiv(Q32 - reserveFactorX32, Q32);

            newDebtExchangeRateX96 = oldDebtExchangeRateX96 + oldDebtExchangeRateX96 * timeElapsed * borrowRateX64 / Q64;
            newLendExchangeRateX96 = oldLendExchangeRateX96 + oldLendExchangeRateX96 * timeElapsed * supplyRateX64 / Q64;
        } else {
            newDebtExchangeRateX96 = oldDebtExchangeRateX96;
            newLendExchangeRateX96 = oldLendExchangeRateX96;
        }
    }

    function _requireLoanIsHealthy(uint256 tokenId, uint256 debt, bool withBuffer) internal view {
        (bool isHealthy,,,) = _checkLoanIsHealthy(tokenId, debt, withBuffer);
        if (!isHealthy) {
            revert CollateralFail();
        }
    }

    function _updateAndCheckCollateral(
        uint256 tokenId,
        uint256 debtExchangeRateX96,
        uint256 lendExchangeRateX96,
        uint256 oldShares,
        uint256 newShares
    ) internal {
        if (oldShares != newShares) {
            (,, address token0, address token1,,,,,,,,) = nonfungiblePositionManager.positions(tokenId);

            if (oldShares > newShares) {
                uint192 difference = SafeCast.toUint192(oldShares - newShares);
                tokenConfigs[token0].totalDebtShares -= difference;
                tokenConfigs[token1].totalDebtShares -= difference;
            } else {
                uint192 difference = SafeCast.toUint192(newShares - oldShares);
                tokenConfigs[token0].totalDebtShares += difference;
                tokenConfigs[token1].totalDebtShares += difference;

                uint256 lentAssets = _convertToAssets(totalSupply(), lendExchangeRateX96, Math.Rounding.Up);
                uint256 collateralValueLimitFactorX32 = tokenConfigs[token0].collateralValueLimitFactorX32;
                if (
                    collateralValueLimitFactorX32 < type(uint32).max
                        && _convertToAssets(tokenConfigs[token0].totalDebtShares, debtExchangeRateX96, Math.Rounding.Up)
                            > lentAssets * collateralValueLimitFactorX32 / Q32
                ) {
                    revert CollateralValueLimit();
                }
                collateralValueLimitFactorX32 = tokenConfigs[token1].collateralValueLimitFactorX32;
                if (
                    collateralValueLimitFactorX32 < type(uint32).max
                        && _convertToAssets(tokenConfigs[token1].totalDebtShares, debtExchangeRateX96, Math.Rounding.Up)
                            > lentAssets * collateralValueLimitFactorX32 / Q32
                ) {
                    revert CollateralValueLimit();
                }
            }
        }
    }

    function _resetDailyLendIncreaseLimit(uint256 newLendExchangeRateX96, bool force) internal {
        
        uint32 time = uint32(block.timestamp / 1 days);
        if (force || time > dailyLendIncreaseLimitLastReset) {
            uint256 lendIncreaseLimit = _convertToAssets(totalSupply(), newLendExchangeRateX96, Math.Rounding.Up)
                * MAX_DAILY_LEND_INCREASE_X32 / Q32;
            dailyLendIncreaseLimitLeft =
                dailyLendIncreaseLimitMin > lendIncreaseLimit ? dailyLendIncreaseLimitMin : lendIncreaseLimit;
            dailyLendIncreaseLimitLastReset = time;
        }
    }

    function _resetDailyDebtIncreaseLimit(uint256 newLendExchangeRateX96, bool force) internal {
        
        uint32 time = uint32(block.timestamp / 1 days);
        if (force || time > dailyDebtIncreaseLimitLastReset) {
            uint256 debtIncreaseLimit = _convertToAssets(totalSupply(), newLendExchangeRateX96, Math.Rounding.Up)
                * MAX_DAILY_DEBT_INCREASE_X32 / Q32;
            dailyDebtIncreaseLimitLeft =
                dailyDebtIncreaseLimitMin > debtIncreaseLimit ? dailyDebtIncreaseLimitMin : debtIncreaseLimit;
            dailyDebtIncreaseLimitLastReset = time;
        }
    }

    function _checkLoanIsHealthy(uint256 tokenId, uint256 debt, bool withBuffer)
        internal
        view
        returns (bool isHealthy, uint256 fullValue, uint256 collateralValue, uint256 feeValue)
    {
        (fullValue, feeValue,,) = oracle.getValue(tokenId, address(asset));
        uint256 collateralFactorX32 = _calculateTokenCollateralFactorX32(tokenId);
        collateralValue = fullValue.mulDiv(collateralFactorX32, Q32);
        isHealthy = (withBuffer ? collateralValue * BORROW_SAFETY_BUFFER_X32 / Q32 : collateralValue) >= debt;
    }

    function _convertToShares(uint256 amount, uint256 exchangeRateX96, Math.Rounding rounding)
        internal
        pure
        returns (uint256)
    {
        return amount.mulDiv(Q96, exchangeRateX96, rounding);
    }

    function _convertToAssets(uint256 shares, uint256 exchangeRateX96, Math.Rounding rounding)
        internal
        pure
        returns (uint256)
    {
        return shares.mulDiv(exchangeRateX96, Q96, rounding);
    }

    function _addTokenToOwner(address to, uint256 tokenId) internal {
        ownedTokensIndex[tokenId] = ownedTokens[to].length;
        ownedTokens[to].push(tokenId);
        tokenOwner[tokenId] = to;
    }

    function _removeTokenFromOwner(address from, uint256 tokenId) internal {
        uint256 lastTokenIndex = ownedTokens[from].length - 1;
        uint256 tokenIndex = ownedTokensIndex[tokenId];
        if (tokenIndex != lastTokenIndex) {
            uint256 lastTokenId = ownedTokens[from][lastTokenIndex];
            ownedTokens[from][tokenIndex] = lastTokenId;
            ownedTokensIndex[lastTokenId] = tokenIndex;
        }
        ownedTokens[from].pop();
        
        delete tokenOwner[tokenId]; 
    }

    // Gauge Integration
    
    /// @notice Set gauge manager
    function setGaugeManager(address _gaugeManager) external onlyOwner {
        gaugeManager = _gaugeManager;
        emit GaugeManagerSet(_gaugeManager);
    }

    /// @notice Stake position in gauge
    function stakePosition(uint256 tokenId) external {
        if (gaugeManager == address(0)) revert GaugeManagerNotSet();
        if (ownerOf(tokenId) != msg.sender) revert NotDepositor();
        
        nonfungiblePositionManager.approve(gaugeManager, tokenId);
        IGaugeManager(gaugeManager).stakePosition(tokenId);
    }

    /// @notice Unstake position  
    function unstakePosition(uint256 tokenId) external {
        if (gaugeManager == address(0)) revert GaugeManagerNotSet();
        if (ownerOf(tokenId) != msg.sender && transformedTokenId != tokenId) revert Unauthorized();
        
        IGaugeManager(gaugeManager).unstakePosition(tokenId);
    }



    /// @notice Emergency unstake for liquidations
    function _unstakeForLiquidation(uint256 tokenId) internal {
        if (gaugeManager != address(0) && IGaugeManager(gaugeManager).tokenIdToGauge(tokenId) != address(0)) {
            IGaugeManager(gaugeManager).unstakePosition(tokenId);
        }
    }

    event GaugeManagerSet(address indexed gaugeManager);

}
