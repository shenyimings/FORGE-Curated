// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ATokenInstance} from "@aave/contracts/instances/ATokenInstance.sol";
import {VariableDebtTokenInstance} from "@aave/contracts/instances/VariableDebtTokenInstance.sol";
import {IPool} from "@aave/contracts/interfaces/IPool.sol";
import {IPoolAddressesProvider} from "@aave/contracts/interfaces/IPoolAddressesProvider.sol";
import {MockIncentivesController} from "@aave/contracts/mocks/helpers/MockIncentivesController.sol";
import {PoolAddressesProvider} from "@aave/contracts/protocol/configuration/PoolAddressesProvider.sol";
import {DataTypes} from "@aave/contracts/protocol/libraries/types/DataTypes.sol";
import {AToken} from "@aave/contracts/protocol/tokenization/AToken.sol";
import {VariableDebtToken} from "@aave/contracts/protocol/tokenization/VariableDebtToken.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract PoolMock is IPool, Ownable {
  using SafeERC20 for IERC20Metadata;

  struct Data {
    AToken aToken;
    VariableDebtToken debtToken;
    uint256 reserveIndex;
    DataTypes.ReserveConfigurationMap configuration;
  }

  PoolAddressesProvider private immutable addressesProvider;
  mapping(address asset => Data data) private datas;

  error NotImplemented();

  constructor(address _owner) Ownable(_owner) {
    addressesProvider = new PoolAddressesProvider("", address(this));
  }

  function setLiquidityIndex(address asset, uint256 index) public onlyOwner {
    Data storage data = datas[asset];
    if (data.reserveIndex == 0) {
      data.aToken = new ATokenInstance(IPool(address(this)));
      data.debtToken = new VariableDebtTokenInstance(IPool(address(this)));
      MockIncentivesController incentivesController = new MockIncentivesController();
      uint8 decimals = IERC20Metadata(asset).decimals();
      string memory name = IERC20Metadata(asset).name();
      string memory symbol = IERC20Metadata(asset).symbol();

      data.aToken.initialize(IPool(address(this)), owner(), asset, incentivesController, decimals, string.concat("AToken ", name), string.concat("a", IERC20Metadata(asset).symbol()), "");
      data.debtToken.initialize(IPool(address(this)), asset, incentivesController, decimals, string.concat("VariableDebtToken ", name), string.concat("d", symbol), "");
      // Bit 56 = 1 (active), Bit 57 = 0 (not frozen), Bit 60 = 0 (not paused), Bits 48-55 = decimals
      data.configuration = DataTypes.ReserveConfigurationMap({data: (1 << 56) | (decimals << 48)});
    }
    data.reserveIndex = index;
  }

  function mintUnbacked(address, uint256, address, uint16) external pure {
    revert NotImplemented();
  }

  function backUnbacked(address, uint256, uint256) external pure returns (uint256) {
    revert NotImplemented();
  }

  function supply(address asset, uint256 amount, address onBehalfOf, uint16) external {
    Data memory data = datas[asset];
    IERC20Metadata(asset).safeTransferFrom(msg.sender, address(data.aToken), amount);
    data.aToken.mint(address(this), onBehalfOf, amount, data.reserveIndex);
  }

  function supplyWithPermit(address, uint256, address, uint16, uint256, uint8, bytes32, bytes32) external pure {
    revert NotImplemented();
  }

  function withdraw(address asset, uint256 amount, address to) external returns (uint256) {
    amount = amount < datas[asset].aToken.balanceOf(msg.sender) ? amount : datas[asset].aToken.balanceOf(msg.sender);
    Data memory data = datas[asset];
    data.aToken.burn(msg.sender, to, amount, data.reserveIndex);
    return amount;
  }

  function borrow(address, uint256, uint256, uint16, address) external pure {
    revert NotImplemented();
  }

  function repay(address, uint256, uint256, address) external pure returns (uint256) {
    revert NotImplemented();
  }

  function repayWithPermit(address, uint256, uint256, address, uint256, uint8, bytes32, bytes32) external pure returns (uint256) {
    revert NotImplemented();
  }

  function repayWithATokens(address, uint256, uint256) external pure returns (uint256) {
    revert NotImplemented();
  }

  function setUserUseReserveAsCollateral(address, bool) external pure {
    revert NotImplemented();
  }

  function liquidationCall(address, address, address, uint256, bool) external pure {
    revert NotImplemented();
  }

  function flashLoan(address, address[] calldata, uint256[] calldata, uint256[] calldata, address, bytes calldata, uint16) external pure {
    revert NotImplemented();
  }

  function flashLoanSimple(address, address, uint256, bytes calldata, uint16) external pure {
    revert NotImplemented();
  }

  function getUserAccountData(address) external pure returns (uint256, uint256, uint256, uint256, uint256, uint256) {
    revert NotImplemented();
  }

  function initReserve(address, address, address, address) external pure {
    revert NotImplemented();
  }

  function dropReserve(address) external pure {
    revert NotImplemented();
  }

  function setReserveInterestRateStrategyAddress(address, address) external pure {
    revert NotImplemented();
  }

  function syncIndexesState(address) external pure {
    revert NotImplemented();
  }

  function syncRatesState(address) external pure {
    revert NotImplemented();
  }

  function setConfiguration(address asset, DataTypes.ReserveConfigurationMap calldata config) external onlyOwner {
    datas[asset].configuration = config;
  }

  function getConfiguration(address) external pure returns (DataTypes.ReserveConfigurationMap memory) {
    revert NotImplemented();
  }

  function getUserConfiguration(address) external pure returns (DataTypes.UserConfigurationMap memory) {
    revert NotImplemented();
  }

  function getReserveNormalizedIncome(address asset) external view returns (uint256) {
    return datas[asset].reserveIndex;
  }

  function getReserveNormalizedVariableDebt(address) external pure returns (uint256) {
    revert NotImplemented();
  }

  function getReserveData(address reserve) external view returns (DataTypes.ReserveDataLegacy memory data) {
    data.aTokenAddress = address(datas[reserve].aToken);
    data.liquidityIndex = uint128(datas[reserve].reserveIndex);
    data.configuration = datas[reserve].configuration;
  }

  function getVirtualUnderlyingBalance(address) external pure returns (uint128) {
    revert NotImplemented();
  }

  function finalizeTransfer(address, address, address, uint256, uint256, uint256) external pure {}

  function getReservesList() external pure returns (address[] memory) {
    revert NotImplemented();
  }

  function getReservesCount() external pure returns (uint256) {
    revert NotImplemented();
  }

  function getReserveAddressById(uint16) external pure returns (address) {
    revert NotImplemented();
  }

  function ADDRESSES_PROVIDER() external view returns (IPoolAddressesProvider) {
    return addressesProvider;
  }

  function updateBridgeProtocolFee(uint256) external pure {
    revert NotImplemented();
  }

  function updateFlashloanPremiums(uint128, uint128) external pure {
    revert NotImplemented();
  }

  function configureEModeCategory(uint8, DataTypes.EModeCategoryBaseConfiguration memory) external pure {
    revert NotImplemented();
  }

  function configureEModeCategoryCollateralBitmap(uint8, uint128) external pure {
    revert NotImplemented();
  }

  function configureEModeCategoryBorrowableBitmap(uint8, uint128) external pure {
    revert NotImplemented();
  }

  function getEModeCategoryData(uint8) external pure returns (DataTypes.EModeCategoryLegacy memory) {
    revert NotImplemented();
  }

  function getEModeCategoryLabel(uint8) external pure returns (string memory) {
    revert NotImplemented();
  }

  function getEModeCategoryCollateralConfig(uint8) external pure returns (DataTypes.CollateralConfig memory) {
    revert NotImplemented();
  }

  function getEModeCategoryCollateralBitmap(uint8) external pure returns (uint128) {
    revert NotImplemented();
  }

  function getEModeCategoryBorrowableBitmap(uint8) external pure returns (uint128) {
    revert NotImplemented();
  }

  function setUserEMode(uint8) external pure {
    revert NotImplemented();
  }

  function getUserEMode(address) external pure returns (uint256) {
    revert NotImplemented();
  }

  function resetIsolationModeTotalDebt(address) external pure {
    revert NotImplemented();
  }

  function setLiquidationGracePeriod(address, uint40) external pure {
    revert NotImplemented();
  }

  function getLiquidationGracePeriod(address) external pure returns (uint40) {
    revert NotImplemented();
  }

  function FLASHLOAN_PREMIUM_TOTAL() external pure returns (uint128) {
    revert NotImplemented();
  }

  function BRIDGE_PROTOCOL_FEE() external pure returns (uint256) {
    revert NotImplemented();
  }

  function FLASHLOAN_PREMIUM_TO_PROTOCOL() external pure returns (uint128) {
    revert NotImplemented();
  }

  function MAX_NUMBER_RESERVES() external pure returns (uint16) {
    revert NotImplemented();
  }

  function mintToTreasury(address[] calldata) external pure {
    revert NotImplemented();
  }

  function rescueTokens(address, address, uint256) external pure {
    revert NotImplemented();
  }

  function deposit(address, uint256, address, uint16) external pure {
    revert NotImplemented();
  }

  function eliminateReserveDeficit(address, uint256) external pure {
    revert NotImplemented();
  }

  function getReserveDeficit(address) external pure returns (uint256) {
    revert NotImplemented();
  }

  function getReserveAToken(address) external pure returns (address) {
    revert NotImplemented();
  }

  function getReserveVariableDebtToken(address) external pure returns (address) {
    revert NotImplemented();
  }

  function getFlashLoanLogic() external pure returns (address) {
    revert NotImplemented();
  }

  function getBorrowLogic() external pure returns (address) {
    revert NotImplemented();
  }

  function getBridgeLogic() external pure returns (address) {
    revert NotImplemented();
  }

  function getEModeLogic() external pure returns (address) {
    revert NotImplemented();
  }

  function getLiquidationLogic() external pure returns (address) {
    revert NotImplemented();
  }

  function getPoolLogic() external pure returns (address) {
    revert NotImplemented();
  }

  function getSupplyLogic() external pure returns (address) {
    revert NotImplemented();
  }
}
