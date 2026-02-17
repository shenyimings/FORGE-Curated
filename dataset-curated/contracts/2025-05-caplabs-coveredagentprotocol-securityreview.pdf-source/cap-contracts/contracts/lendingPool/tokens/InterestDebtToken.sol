// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { ERC20Upgradeable, IERC20 } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { Access } from "../../access/Access.sol";

import { IInterestDebtToken } from "../../interfaces/IInterestDebtToken.sol";
import { IOracle } from "../../interfaces/IOracle.sol";

import { InterestDebtTokenStorageUtils } from "../../storage/InterestDebtTokenStorageUtils.sol";
import { MathUtils } from "../libraries/math/MathUtils.sol";
import { WadRayMath } from "../libraries/math/WadRayMath.sol";

/// @title Interest debt token for a market on the Lender
/// @author kexley, @capLabs
/// @notice Compound interest accrues for agents borrowing an asset.
/// @dev Total supply is calculated therefore an estimation rather than exact.
contract InterestDebtToken is
    IInterestDebtToken,
    UUPSUpgradeable,
    ERC20Upgradeable,
    Access,
    InterestDebtTokenStorageUtils
{
    using MathUtils for uint256;
    using WadRayMath for uint256;

    /// @dev Disable initializers on the implementation
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialize the interest debt token with the underlying asset
    /// @param _accessControl Access control address
    /// @param _oracle Oracle address
    /// @param _debtToken Principal debt token
    /// @param _asset Asset address
    function initialize(address _accessControl, address _oracle, address _debtToken, address _asset)
        external
        initializer
    {
        InterestDebtTokenStorage storage $ = getInterestDebtTokenStorage();
        $.oracle = _oracle;
        $.debtToken = _debtToken;
        $.asset = _asset;
        $.decimals = IERC20Metadata(_asset).decimals();
        $.index = 1e27;
        $.lastUpdate = block.timestamp;

        string memory _name = string.concat("interest", IERC20Metadata(_asset).name());
        string memory _symbol = string.concat("interest", IERC20Metadata(_asset).symbol());

        __ERC20_init(_name, _symbol);
        __Access_init(_accessControl);
        __UUPSUpgradeable_init();
    }

    /// @notice Update the accrued interest and the interest rate
    /// @dev Left permissionless
    /// @param _agent Agent address to accrue interest for
    function update(address _agent) external {
        _update(_agent);
    }

    /// @notice Interest rate index representing the increase of debt per asset borrowed
    /// @dev A value of 1e27 means there is no debt. As time passes, the debt is accrued. A value
    /// of 2*1e27 means that for each unit of debt, one unit worth of interest has been accumulated
    /// @return latestIndex Current interest rate index
    function currentIndex() public view returns (uint256 latestIndex) {
        InterestDebtTokenStorage storage $ = getInterestDebtTokenStorage();
        uint256 timestamp = block.timestamp;
        if (timestamp != $.lastUpdate) {
            latestIndex = MathUtils.calculateCompoundedInterest($.interestRate, $.lastUpdate).rayMul($.index);
        } else {
            latestIndex = $.index;
        }
    }

    /// @notice Burn the debt token, only callable by the lender
    /// @dev All underlying token transfers are handled by the lender instead of this contract
    /// @param _agent Agent address that will have it's debt repaid
    /// @param _amount Amount of underlying asset to repay to lender
    /// @return actualRepaid Actual amount repaid
    function burn(address _agent, uint256 _amount)
        external
        checkAccess(this.burn.selector)
        returns (uint256 actualRepaid)
    {
        _update(_agent);

        uint256 agentBalance = super.balanceOf(_agent);

        actualRepaid = _amount > agentBalance ? agentBalance : _amount;

        if (actualRepaid > 0) {
            _burn(_agent, actualRepaid);

            InterestDebtTokenStorage storage $ = getInterestDebtTokenStorage();
            if (actualRepaid < $.totalSupply) {
                $.totalSupply -= actualRepaid;
            } else {
                $.totalSupply = 0;
            }
        }
    }

    /// @notice Interest accrued by an agent
    /// @param _agent Agent address
    /// @return balance Interest amount
    function balanceOf(address _agent) public view override returns (uint256 balance) {
        InterestDebtTokenStorage storage $ = getInterestDebtTokenStorage();
        uint256 timestamp = block.timestamp;
        if (timestamp > $.lastAgentUpdate[_agent]) {
            balance = super.balanceOf(_agent)
                + (IERC20($.debtToken).balanceOf(_agent) + super.balanceOf(_agent))
                    * (currentIndex() - $.storedIndex[_agent]) / 1e27;
        } else {
            balance = super.balanceOf(_agent);
        }
    }

    /// @notice Total amount of interest accrued by agents
    /// @return supply Total amount of interest
    function totalSupply() public view override returns (uint256 supply) {
        InterestDebtTokenStorage storage $ = getInterestDebtTokenStorage();
        uint256 timestamp = block.timestamp;
        if (timestamp > $.lastUpdate) {
            supply =
                $.totalSupply + (IERC20($.debtToken).totalSupply() + $.totalSupply) * (currentIndex() - $.index) / 1e27;
        } else {
            supply = $.totalSupply;
        }
    }

    /// @notice Next interest rate on update
    /// @dev Value is encoded in ray (27 decimals) and encodes yearly rates
    /// @param rate Interest rate
    function nextInterestRate() public returns (uint256 rate) {
        InterestDebtTokenStorage storage $ = getInterestDebtTokenStorage();
        address _oracle = $.oracle;
        uint256 marketRate = IOracle(_oracle).marketRate($.asset);
        uint256 benchmarkRate = IOracle(_oracle).benchmarkRate($.asset);
        uint256 utilizationRate = IOracle(_oracle).utilizationRate($.asset);

        rate = marketRate > benchmarkRate ? marketRate : benchmarkRate;
        rate += utilizationRate;
    }

    /// @notice Accrue interest for a specific agent and the total supply
    /// @param _agent Agent address
    function _update(address _agent) internal {
        InterestDebtTokenStorage storage $ = getInterestDebtTokenStorage();
        uint256 timestamp = block.timestamp;

        if (timestamp > $.lastAgentUpdate[_agent]) {
            uint256 amount = (IERC20($.debtToken).balanceOf(_agent) + super.balanceOf(_agent))
                * (currentIndex() - $.storedIndex[_agent]) / 1e27;

            if (amount > 0) _mint(_agent, amount);

            $.storedIndex[_agent] = currentIndex();
            $.lastAgentUpdate[_agent] = timestamp;
        }

        if (timestamp > $.lastUpdate) {
            $.totalSupply += (IERC20($.debtToken).totalSupply() + $.totalSupply) * (currentIndex() - $.index) / 1e27;

            $.index = currentIndex();

            $.lastUpdate = timestamp;
        }

        $.interestRate = nextInterestRate();
    }

    /// @notice Match decimals with underlying asset
    /// @return decimals
    function decimals() public view override returns (uint8) {
        return getInterestDebtTokenStorage().decimals;
    }

    /// @notice Disabled due to this being a non-transferrable token
    function transfer(address, uint256) public pure override returns (bool) {
        revert OperationNotSupported();
    }

    /// @notice Disabled due to this being a non-transferrable token
    function allowance(address, address) public pure override returns (uint256) {
        revert OperationNotSupported();
    }

    /// @notice Disabled due to this being a non-transferrable token
    function approve(address, uint256) public pure override returns (bool) {
        revert OperationNotSupported();
    }

    /// @notice Disabled due to this being a non-transferrable token
    function transferFrom(address, address, uint256) public pure override returns (bool) {
        revert OperationNotSupported();
    }

    /// @notice Get the current state for a restaker/agent
    /// @param _agent The address of the agent/restaker
    /// @return _storedIndex The stored index for the agent
    /// @return _lastUpdate The timestamp of the last update for this agent
    function agent(address _agent) external view returns (uint256 _storedIndex, uint256 _lastUpdate) {
        InterestDebtTokenStorage storage $ = getInterestDebtTokenStorage();
        _storedIndex = $.storedIndex[_agent];
        _lastUpdate = $.lastAgentUpdate[_agent];
    }

    /// @notice Get the oracle address
    /// @return _oracle The oracle address
    function oracle() external view returns (address _oracle) {
        _oracle = getInterestDebtTokenStorage().oracle;
    }

    /// @notice Get the debt token address
    /// @return _debtToken The debt token address
    function debtToken() external view returns (address _debtToken) {
        _debtToken = getInterestDebtTokenStorage().debtToken;
    }

    /// @notice Get the asset address
    /// @return _asset The asset address
    function asset() external view returns (address _asset) {
        _asset = getInterestDebtTokenStorage().asset;
    }

    /// @notice Get the current interest rate
    /// @dev Value is encoded in ray (27 decimals) and encodes yearly rates
    /// @return _interestRate The current interest rate
    function interestRate() external view returns (uint256 _interestRate) {
        _interestRate = getInterestDebtTokenStorage().interestRate;
    }

    /// @notice Get the current index
    /// @return _index The current index
    function index() external view returns (uint256 _index) {
        _index = getInterestDebtTokenStorage().index;
    }

    /// @notice Get the last update timestamp
    /// @return _lastUpdate The last update timestamp
    function lastUpdate() external view returns (uint256 _lastUpdate) {
        _lastUpdate = getInterestDebtTokenStorage().lastUpdate;
    }

    function _authorizeUpgrade(address) internal override checkAccess(bytes4(0)) { }
}
