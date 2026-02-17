// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { ERC20Upgradeable, IERC20 } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { Access } from "../../access/Access.sol";
import { IOracle } from "../../interfaces/IOracle.sol";
import { IRestakerDebtToken } from "../../interfaces/IRestakerDebtToken.sol";
import { RestakerDebtTokenStorageUtils } from "../../storage/RestakerDebtTokenStorageUtils.sol";

/// @title Restaker debt token for a market on the Lender
/// @author kexley, @capLabs
/// @notice Restaker debt tokens accrue over time representing the debt in the underlying asset to be
/// paid to the restakers collateralizing an agent
/// @dev Each agent can have a different rate so the weighted mean is used to calculate the total
/// accrued debt. This means that the total supply may not be exact.
contract RestakerDebtToken is
    IRestakerDebtToken,
    UUPSUpgradeable,
    ERC20Upgradeable,
    Access,
    RestakerDebtTokenStorageUtils
{
    /// @dev Disable initializers on the implementation
    constructor() {
        _disableInitializers();
    }

    uint256 internal constant SECONDS_PER_YEAR = 365 days;

    /// @notice Initialize the debt token with the underlying asset
    /// @param _accessControl Access control address
    /// @param _oracle Oracle address
    /// @param _debtToken Principal debt token
    /// @param _asset Asset address
    function initialize(address _accessControl, address _oracle, address _debtToken, address _asset)
        external
        initializer
    {
        RestakerDebtTokenStorage storage $ = getRestakerDebtTokenStorage();
        $.oracle = _oracle;
        $.debtToken = _debtToken;
        $.asset = _asset;
        $.decimals = IERC20Metadata(_asset).decimals();

        string memory _name = string.concat("restaker", IERC20Metadata(_asset).name());
        string memory _symbol = string.concat("restaker", IERC20Metadata(_asset).symbol());

        __ERC20_init(_name, _symbol);
        __Access_init(_accessControl);
        __UUPSUpgradeable_init();
    }

    /// @notice Update the interest per second of the agent and the scaled total supply
    /// @dev Left permissionless
    /// @param _agent Agent address to update interest rate for
    function update(address _agent) external {
        _update(_agent);
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

            RestakerDebtTokenStorage storage $ = getRestakerDebtTokenStorage();
            if (actualRepaid < $.totalSupply) {
                $.totalSupply -= actualRepaid;
            } else {
                $.totalSupply = 0;
            }
        }
    }

    /// @notice Interest accrued by an agent to be repaid to restakers
    /// @param _agent Agent address
    /// @return balance Interest amount
    function balanceOf(address _agent) public view override returns (uint256 balance) {
        RestakerDebtTokenStorage storage $ = getRestakerDebtTokenStorage();
        uint256 timestamp = block.timestamp;
        if (timestamp > $.lastAgentUpdate[_agent]) {
            balance =
                super.balanceOf(_agent) + $.interestPerSecond[_agent] * (timestamp - $.lastAgentUpdate[_agent]) / 1e27;
        } else {
            balance = super.balanceOf(_agent);
        }
    }

    /// @notice Total amount of interest accrued by agents
    /// @return supply Total amount of interest
    function totalSupply() public view override returns (uint256 supply) {
        RestakerDebtTokenStorage storage $ = getRestakerDebtTokenStorage();
        uint256 timestamp = block.timestamp;
        if (timestamp > $.lastUpdate) {
            supply = $.totalSupply + $.totalInterestPerSecond * (timestamp - $.lastUpdate) / 1e27;
        } else {
            supply = $.totalSupply;
        }
    }

    /// @notice Average rate of all restakers weighted by debt
    /// @param rate Average rate
    function averageRate() external view returns (uint256 rate) {
        RestakerDebtTokenStorage storage $ = getRestakerDebtTokenStorage();
        uint256 totalDebt = IERC20($.debtToken).totalSupply();
        rate = totalDebt > 0 ? $.totalInterestPerSecond * SECONDS_PER_YEAR / totalDebt : 0;
    }

    /// @dev Update the interest per second of the agent and the scaled total supply
    /// @param _agent Agent address to update interest rate for
    function _update(address _agent) internal {
        _accrueInterest(_agent);

        RestakerDebtTokenStorage storage $ = getRestakerDebtTokenStorage();
        uint256 rate = IOracle($.oracle).restakerRate(_agent);
        uint256 oldInterestPerSecond = $.interestPerSecond[_agent];
        uint256 newInterestPerSecond = IERC20($.debtToken).balanceOf(_agent) * rate / SECONDS_PER_YEAR;

        $.interestPerSecond[_agent] = newInterestPerSecond;
        $.totalInterestPerSecond = $.totalInterestPerSecond + newInterestPerSecond - oldInterestPerSecond;
    }

    /// @notice Accrue interest for a specific agent and the total supply
    /// @param _agent Agent address
    function _accrueInterest(address _agent) internal {
        RestakerDebtTokenStorage storage $ = getRestakerDebtTokenStorage();
        uint256 timestamp = block.timestamp;

        if (timestamp > $.lastAgentUpdate[_agent]) {
            uint256 amount = $.interestPerSecond[_agent] * (timestamp - $.lastAgentUpdate[_agent]) / 1e27;

            if (amount > 0) _mint(_agent, amount);

            $.lastAgentUpdate[_agent] = timestamp;
        }

        if (timestamp > $.lastUpdate) {
            $.totalSupply += $.totalInterestPerSecond * (timestamp - $.lastUpdate) / 1e27;

            $.lastUpdate = timestamp;
        }
    }

    /// @notice Match decimals with underlying asset
    /// @return decimals
    function decimals() public view override returns (uint8) {
        return getRestakerDebtTokenStorage().decimals;
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
    /// @return _interestPerSecond The current interest rate per second for the agent
    /// @return _lastUpdate The timestamp of the last update for this agent
    function agent(address _agent) external view returns (uint256 _interestPerSecond, uint256 _lastUpdate) {
        RestakerDebtTokenStorage storage $ = getRestakerDebtTokenStorage();
        _interestPerSecond = $.interestPerSecond[_agent];
        _lastUpdate = $.lastAgentUpdate[_agent];
    }

    /// @notice Get the oracle address
    /// @return _oracle The oracle address
    function oracle() external view returns (address _oracle) {
        _oracle = getRestakerDebtTokenStorage().oracle;
    }

    /// @notice Get the debt token address
    /// @return _debtToken The debt token address
    function debtToken() external view returns (address _debtToken) {
        _debtToken = getRestakerDebtTokenStorage().debtToken;
    }

    /// @notice Get the asset address
    /// @return _asset The asset address
    function asset() external view returns (address _asset) {
        _asset = getRestakerDebtTokenStorage().asset;
    }

    /// @notice Get the total interest per second
    /// @return _totalInterestPerSecond The total interest per second
    function totalInterestPerSecond() external view returns (uint256 _totalInterestPerSecond) {
        _totalInterestPerSecond = getRestakerDebtTokenStorage().totalInterestPerSecond;
    }

    /// @notice Get the last update timestamp
    /// @return _lastUpdate The last update timestamp
    function lastUpdate() external view returns (uint256 _lastUpdate) {
        _lastUpdate = getRestakerDebtTokenStorage().lastUpdate;
    }

    function _authorizeUpgrade(address) internal override checkAccess(bytes4(0)) { }
}
