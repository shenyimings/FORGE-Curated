// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IPool} from "aave-v3-core/contracts/interfaces/IPool.sol";
import {DataTypes} from "aave-v3-core/contracts/protocol/libraries/types/DataTypes.sol";
import {IPoolAddressesProvider} from "aave-v3-core/contracts/interfaces/IPoolAddressesProvider.sol";

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./MockAToken.sol";

contract MockAaveV3Pool is IPool {
    using DataTypes for DataTypes.ReserveData;
    using DataTypes for DataTypes.ReserveConfigurationMap;
    using DataTypes for DataTypes.UserConfigurationMap;

    mapping(address => mapping(address => uint256)) private userSupplies;
    mapping(address => mapping(address => uint256)) private userBorrows;
    mapping(address => DataTypes.ReserveData) private reserveData;
    mapping(address => DataTypes.UserConfigurationMap)
        private userConfigurations;
    mapping(uint8 => DataTypes.EModeCategory) private eModeCategoryData;
    mapping(address => uint8) private userEModes;
    mapping(address => address) public aTokens;

    address[] private reservesList;
    uint256 public MAX_STABLE_RATE_BORROW_SIZE_PERCENT = 2500;
    uint128 public FLASHLOAN_PREMIUM_TOTAL = 9;
    uint256 public BRIDGE_PROTOCOL_FEE = 0;
    uint128 public FLASHLOAN_PREMIUM_TO_PROTOCOL = 0;
    uint16 public MAX_NUMBER_RESERVES = 128;

    function ADDRESSES_PROVIDER()
        external
        view
        returns (IPoolAddressesProvider)
    {
        return IPoolAddressesProvider(address(0));
    }

    function getConfiguration(
        address asset
    ) external view returns (DataTypes.ReserveConfigurationMap memory) {
        // Dummy implementation
        return DataTypes.ReserveConfigurationMap(0);
    }

    function getEModeCategoryData(
        uint8 id
    ) external view returns (DataTypes.EModeCategory memory) {
        // Dummy implementation
        return
            DataTypes.EModeCategory({
                ltv: 0,
                liquidationThreshold: 0,
                liquidationBonus: 0,
                priceSource: address(0),
                label: ""
            });
    }

    function getUserConfiguration(
        address user
    ) external view returns (DataTypes.UserConfigurationMap memory) {
        // Dummy implementation
        return userConfigurations[user];
    }

    function initReserve(address asset, string memory aTokenName) external {
        require(aTokens[asset] == address(0), "Reserve already initialized");
        MockAToken aToken = new MockAToken(
            aTokenName,
            "AToken",
            ERC20(asset).decimals()
        );
        aTokens[asset] = address(aToken);
        reservesList.push(asset);

        DataTypes.ReserveData storage reserve = reserveData[asset];
        reserve.aTokenAddress = address(aToken);
    }

    function supply(
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint16 referralCode
    ) external override {
        require(aTokens[asset] != address(0), "Reserve not initialized");
        IERC20(asset).transferFrom(msg.sender, address(this), amount);
        MockAToken(aTokens[asset]).mint(onBehalfOf, amount);
        userSupplies[onBehalfOf][asset] += amount;
        emit Supply(asset, msg.sender, onBehalfOf, amount, referralCode);
    }

    function withdraw(
        address asset,
        uint256 amount,
        address to
    ) external override returns (uint256) {
        require(aTokens[asset] != address(0), "Reserve not initialized");
        require(
            userSupplies[msg.sender][asset] >= amount,
            "Insufficient balance"
        );
        userSupplies[msg.sender][asset] -= amount;
        MockAToken(aTokens[asset]).burn(msg.sender, amount);
        IERC20(asset).transfer(to, amount);
        emit Withdraw(asset, msg.sender, to, amount);
        return amount;
    }

    function borrow(
        address asset,
        uint256 amount,
        uint256 interestRateMode,
        uint16 referralCode,
        address onBehalfOf
    ) external {
        require(
            IERC20(asset).balanceOf(address(this)) >= amount,
            "Insufficient liquidity"
        );
        userBorrows[onBehalfOf][asset] += amount;
        IERC20(asset).transfer(msg.sender, amount);
        emit Borrow(
            asset,
            onBehalfOf,
            onBehalfOf,
            amount,
            DataTypes.InterestRateMode(interestRateMode),
            0,
            referralCode
        );
    }

    function repay(
        address asset,
        uint256 amount,
        uint256 interestRateMode,
        address onBehalfOf
    ) external returns (uint256) {
        uint256 repayAmount = amount > userBorrows[onBehalfOf][asset]
            ? userBorrows[onBehalfOf][asset]
            : amount;
        IERC20(asset).transferFrom(msg.sender, address(this), repayAmount);
        userBorrows[onBehalfOf][asset] -= repayAmount;
        emit Repay(asset, onBehalfOf, msg.sender, repayAmount, false);
        return repayAmount;
    }

    function getReserveData(
        address asset
    ) external view returns (DataTypes.ReserveData memory) {
        return reserveData[asset];
    }

    // Dummy implementations for other functions

    function mintUnbacked(
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint16 referralCode
    ) external {
        // Dummy implementation
    }

    function backUnbacked(
        address asset,
        uint256 amount,
        uint256 fee
    ) external returns (uint256) {
        // Dummy implementation
        return 0;
    }

    function supplyWithPermit(
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint16 referralCode,
        uint256 deadline,
        uint8 permitV,
        bytes32 permitR,
        bytes32 permitS
    ) external {
        // Dummy implementation
    }

    function repayWithPermit(
        address asset,
        uint256 amount,
        uint256 interestRateMode,
        address onBehalfOf,
        uint256 deadline,
        uint8 permitV,
        bytes32 permitR,
        bytes32 permitS
    ) external returns (uint256) {
        // Dummy implementation
        return 0;
    }

    function repayWithATokens(
        address asset,
        uint256 amount,
        uint256 interestRateMode
    ) external returns (uint256) {
        // Dummy implementation
        return 0;
    }

    function swapBorrowRateMode(
        address asset,
        uint256 interestRateMode
    ) external {
        // Dummy implementation
    }

    function rebalanceStableBorrowRate(address asset, address user) external {
        // Dummy implementation
    }

    function setUserUseReserveAsCollateral(
        address asset,
        bool useAsCollateral
    ) external {
        // Dummy implementation
    }

    function liquidationCall(
        address collateralAsset,
        address debtAsset,
        address user,
        uint256 debtToCover,
        bool receiveAToken
    ) external {
        // Dummy implementation
    }

    function flashLoan(
        address receiverAddress,
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata interestRateModes,
        address onBehalfOf,
        bytes calldata params,
        uint16 referralCode
    ) external {
        // Dummy implementation
    }

    function flashLoanSimple(
        address receiverAddress,
        address asset,
        uint256 amount,
        bytes calldata params,
        uint16 referralCode
    ) external {
        // Dummy implementation
    }

    function getUserAccountData(
        address user
    )
        external
        view
        returns (
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            uint256 availableBorrowsBase,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        )
    {
        // Dummy implementation
        return (0, 0, 0, 0, 0, 0);
    }

    function dropReserve(address asset) external {
        // Dummy implementation
    }

    function setReserveInterestRateStrategyAddress(
        address asset,
        address rateStrategyAddress
    ) external {
        // Dummy implementation
    }

    function getReservesList() external view returns (address[] memory) {
        return reservesList;
    }

    function getReserveAddressById(uint16 id) external view returns (address) {
        // Dummy implementation
        return address(0);
    }

    function updateBridgeProtocolFee(uint256 bridgeProtocolFee) external {
        BRIDGE_PROTOCOL_FEE = bridgeProtocolFee;
    }

    function updateFlashloanPremiums(
        uint128 flashLoanPremiumTotal,
        uint128 flashLoanPremiumToProtocol
    ) external {
        FLASHLOAN_PREMIUM_TOTAL = flashLoanPremiumTotal;
        FLASHLOAN_PREMIUM_TO_PROTOCOL = flashLoanPremiumToProtocol;
    }

    function configureEModeCategory(
        uint8 id,
        DataTypes.EModeCategory memory config
    ) external {
        eModeCategoryData[id] = config;
    }

    function setUserEMode(uint8 categoryId) external {
        userEModes[msg.sender] = categoryId;
    }

    function getUserEMode(address user) external view returns (uint256) {
        return userEModes[user];
    }

    function resetIsolationModeTotalDebt(address asset) external {
        // Dummy implementation
    }

    function mintToTreasury(address[] calldata assets) external {
        // Dummy implementation
    }

    function rescueTokens(address token, address to, uint256 amount) external {
        // Dummy implementation
    }

    function deposit(
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint16 referralCode
    ) external override {
        // Dummy implementation
    }

    function initReserve(
        address asset,
        address aTokenAddress,
        address stableDebtAddress,
        address variableDebtAddress,
        address interestRateStrategyAddress
    ) external override {
        // Implementation
    }

    function setConfiguration(
        address asset,
        DataTypes.ReserveConfigurationMap calldata configuration
    ) external override {
        // Implementation
    }

    function getReserveNormalizedIncome(
        address asset
    ) external view override returns (uint256) {
        // Implementation
        return 0;
    }

    function getReserveNormalizedVariableDebt(
        address asset
    ) external view override returns (uint256) {
        // Implementation
        return 0;
    }

    function finalizeTransfer(
        address asset,
        address from,
        address to,
        uint256 amount,
        uint256 balanceFromBefore,
        uint256 balanceToBefore
    ) external override {
        // Implementation
    }
    // add this to be excluded from coverage report
    function test() public {}
}
