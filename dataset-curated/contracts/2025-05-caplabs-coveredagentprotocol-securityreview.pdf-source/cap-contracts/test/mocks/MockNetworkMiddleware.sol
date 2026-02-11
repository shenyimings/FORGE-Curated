// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { INetworkMiddleware } from "../../contracts/interfaces/INetworkMiddleware.sol";

contract MockNetworkMiddleware is INetworkMiddleware {
    NetworkMiddlewareStorage internal _storage;

    // Mock control variables
    mapping(address => uint256) public mockCoverage;
    mapping(address => uint256) public mockSlashableCollateral;
    mapping(address => mapping(address => uint256)) public mockCollateralByVault;
    mapping(address => mapping(address => uint256)) public mockSlashableCollateralByVault;

    function registerAgent(address _agent, address _vault) external {
        _storage.agentsToVault[_agent] = _vault;
        emit AgentRegistered(_agent);
    }

    function registerVault(address _vault, address _stakerRewarder) external {
        _storage.vaults[_vault] = Vault({ stakerRewarder: _stakerRewarder, exists: true });
        emit VaultRegistered(_vault);
    }

    function setFeeAllowed(uint256 _feeAllowed) external {
        _storage.feeAllowed = _feeAllowed;
    }

    function slash(address _agent, address _recipient, uint256 _slashShare, uint48) external {
        mockSlashableCollateral[_agent] -= mockSlashableCollateral[_agent] * _slashShare / 1e18;
        mockCoverage[_agent] -= mockCoverage[_agent] * _slashShare / 1e18;

        address _vault = _storage.agentsToVault[_agent];
        mockCollateralByVault[_agent][_vault] -= mockCollateralByVault[_agent][_vault] * _slashShare / 1e18;
        mockSlashableCollateralByVault[_agent][_vault] -=
            mockSlashableCollateralByVault[_agent][_vault] * _slashShare / 1e18;
        emit Slash(_agent, _recipient, _slashShare);
    }

    function coverageByVault(address, address _agent, address _vault, address, uint48)
        external
        view
        returns (uint256 collateralValue, uint256 collateral)
    {
        return (mockCollateralByVault[_agent][_vault], mockCollateralByVault[_agent][_vault]);
    }

    function slashableCollateralByVault(address, address _agent, address _vault, address, uint48)
        external
        view
        returns (uint256 collateralValue, uint256 collateral)
    {
        return (mockSlashableCollateralByVault[_agent][_vault], mockSlashableCollateralByVault[_agent][_vault]);
    }

    function coverage(address _agent) external view returns (uint256 delegation) {
        return mockCoverage[_agent];
    }

    function slashableCollateral(address _agent, uint48) external view returns (uint256 _slashableCollateral) {
        _slashableCollateral = mockSlashableCollateral[_agent];
    }

    function vaults(address _agent) external view returns (address vault) {
        return _storage.agentsToVault[_agent];
    }

    function distributeRewards(address _agent, address _token) external {
        // Mock implementation - no-op
    }

    // Mock control functions
    function setMockCoverage(address _agent, uint256 _coverage) external {
        mockCoverage[_agent] = _coverage;
    }

    function setMockSlashableCollateral(address _agent, uint256 _slashableCollateral) external {
        mockSlashableCollateral[_agent] = _slashableCollateral;
    }

    function setMockCollateralByVault(address _agent, address _vault, uint256 _collateral) external {
        mockCollateralByVault[_agent][_vault] = _collateral;
    }

    function setMockSlashableCollateralByVault(address _agent, address _vault, uint256 _slashableCollateral) external {
        mockSlashableCollateralByVault[_agent][_vault] = _slashableCollateral;
    }

    function addMockAgentCoverage(address _agent, address _vault, uint256 _coverage) external {
        mockCoverage[_agent] += _coverage;
        mockSlashableCollateral[_agent] += _coverage;
        mockCollateralByVault[_agent][_vault] += _coverage;
        mockSlashableCollateralByVault[_agent][_vault] += _coverage;
    }
}
