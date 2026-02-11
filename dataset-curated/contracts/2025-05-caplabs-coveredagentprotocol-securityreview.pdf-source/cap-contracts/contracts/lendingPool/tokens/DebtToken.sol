// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { Access } from "../../access/Access.sol";
import { IDebtToken } from "../../interfaces/IDebtToken.sol";
import { IOracle } from "../../interfaces/IOracle.sol";
import { DebtTokenStorageUtils } from "../../storage/DebtTokenStorageUtils.sol";

import { MathUtils } from "../libraries/math/MathUtils.sol";
import { WadRayMath } from "../libraries/math/WadRayMath.sol";
import { MintableERC20 } from "./base/MintableERC20.sol";
import { ScaledToken } from "./base/ScaledToken.sol";

/// @title Debt token for a market on the Lender
/// @author kexley, @capLabs
contract DebtToken is IDebtToken, UUPSUpgradeable, Access, ScaledToken, DebtTokenStorageUtils {
    using WadRayMath for uint256;

    /// @notice Update the index before minting or burning
    modifier updateIndex() {
        _updateIndex();
        _;
    }

    /// @dev Disable initializers on the implementation
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialize the debt token with the underlying asset
    /// @param _accessControl Access control
    /// @param _asset Asset address
    /// @param _oracle Oracle address
    function initialize(address _accessControl, address _asset, address _oracle) external initializer {
        DebtTokenStorage storage $ = getDebtTokenStorage();
        $.asset = _asset;
        $.index = 1e27;
        $.lastIndexUpdate = block.timestamp;
        $.oracle = _oracle;

        string memory _name = string.concat("debt", IERC20Metadata(_asset).name());
        string memory _symbol = string.concat("debt", IERC20Metadata(_asset).symbol());
        uint8 _decimals = IERC20Metadata(_asset).decimals();

        __ScaledToken_init(_name, _symbol, _decimals);
        __Access_init(_accessControl);
        __UUPSUpgradeable_init();
    }

    /// @notice Get the balance of an agent
    /// @param _agent The agent address
    /// @return balance The balance of the agent
    function balanceOf(address _agent) public view override(IERC20, MintableERC20) returns (uint256) {
        uint256 scaledBalance = super.balanceOf(_agent);

        if (scaledBalance == 0) {
            return 0;
        }

        return scaledBalance.rayMul(index());
    }

    /// @notice Get the total supply of the debt token
    /// @return totalSupply The total supply of the debt token
    function totalSupply() public view override(IERC20, MintableERC20) returns (uint256) {
        return super.totalSupply().rayMul(index());
    }

    /// @notice Lender will mint debt tokens to match the amount borrowed by an agent. Interest and
    /// restaker interest is accrued to the agent.
    /// @param to Address to mint tokens to
    /// @param amount Amount of tokens to mint
    function mint(address to, uint256 amount) external updateIndex checkAccess(this.mint.selector) {
        _mintScaled(to, amount, getDebtTokenStorage().index);
    }

    /// @notice Lender will burn debt tokens when the principal debt is repaid by an agent
    /// @param from Burn tokens from agent
    /// @param amount Amount to burn
    function burn(address from, uint256 amount) external updateIndex checkAccess(this.burn.selector) {
        _burnScaled(from, amount, getDebtTokenStorage().index);
    }

    /// @notice Get the current index
    /// @return currentIndex The current index
    function index() public view returns (uint256 currentIndex) {
        DebtTokenStorage storage $ = getDebtTokenStorage();

        currentIndex = $.index;

        if ($.lastIndexUpdate != block.timestamp) {
            currentIndex = currentIndex.rayMul(MathUtils.calculateCompoundedInterest($.interestRate, $.lastIndexUpdate));
        }
    }

    /// @notice Update the index
    function _updateIndex() internal {
        DebtTokenStorage storage $ = getDebtTokenStorage();
        if (super.totalSupply() > 0) $.index = index();
        $.lastIndexUpdate = block.timestamp;
        $.interestRate = _nextInterestRate();
    }

    /// @notice Next interest rate on update
    /// @dev Value is encoded in ray (27 decimals) and encodes yearly rates
    /// @param rate Interest rate
    function _nextInterestRate() internal returns (uint256 rate) {
        DebtTokenStorage storage $ = getDebtTokenStorage();
        address _oracle = $.oracle;
        uint256 marketRate = IOracle(_oracle).marketRate($.asset);
        uint256 benchmarkRate = IOracle(_oracle).benchmarkRate($.asset);
        uint256 utilizationRate = IOracle(_oracle).utilizationRate($.asset);

        rate = marketRate > benchmarkRate ? marketRate : benchmarkRate;
        rate += utilizationRate;
    }

    function _authorizeUpgrade(address) internal override checkAccess(bytes4(0)) { }
}
