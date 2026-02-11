// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IVaultHub} from "../../src/interfaces/core/IVaultHub.sol";
import {MockStETH} from "./MockStETH.sol";
import {MockStakingVault} from "./MockStakingVault.sol";
import {MockVaultHub} from "./MockVaultHub.sol";
import {MockWstETH} from "./MockWstETH.sol";
import {AccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";

contract MockDashboard is AccessControlEnumerable {
    MockStETH public immutable STETH;
    MockWstETH public immutable WSTETH;
    MockVaultHub public immutable VAULT_HUB;
    address public immutable VAULT;

    event DashboardFunded(address sender, uint256 amount);

    uint256 public locked;

    bytes32 public constant MINT_ROLE = keccak256("MINT_ROLE");
    bytes32 public constant BURN_ROLE = keccak256("BURN_ROLE");
    bytes32 public constant FUND_ROLE = keccak256("FUND_ROLE");
    bytes32 public constant WITHDRAW_ROLE = keccak256("WITHDRAW_ROLE");
    bytes32 public constant REBALANCE_ROLE = keccak256("REBALANCE_ROLE");
    bytes32 public constant PAUSE_BEACON_CHAIN_DEPOSITS_ROLE = keccak256("PAUSE_BEACON_CHAIN_DEPOSITS_ROLE");

    constructor(address _steth, address _wsteth, address _vaultHub, address _stakingVault, address _admin) {
        STETH = MockStETH(_steth);
        WSTETH = MockWstETH(payable(_wsteth));
        VAULT_HUB = MockVaultHub(payable(_vaultHub));
        VAULT = _stakingVault; // Mock staking vault address
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);

        // Set default report freshness to true
        VAULT_HUB.mock_setReportFreshness(VAULT, true);
        VAULT_HUB.mock_setConnectionParameters(VAULT, 10_00, 9_75); // 10% reserve, 9.75% forced rebalance
    }

    function initialize() external {
        STETH.approve(address(WSTETH), type(uint256).max);
    }

    function fund() external payable {
        emit DashboardFunded(msg.sender, msg.value);
        VAULT_HUB.fund{value: msg.value}(VAULT);
    }

    function withdrawableValue() external view returns (uint256) {
        return address(VAULT).balance - locked;
    }

    function maxLockableValue() external view returns (uint256) {
        return VAULT_HUB.totalValue(VAULT);
    }

    function withdraw(address recipient, uint256 etherAmount) external {
        VAULT_HUB.withdraw(VAULT, recipient, etherAmount);
    }

    function vaultHub() external view returns (MockVaultHub) {
        return VAULT_HUB;
    }

    function stakingVault() external view returns (address) {
        return VAULT;
    }

    function mock_setLocked(uint256 _locked) external {
        locked = _locked;
    }

    function mock_simulateRewards(int256 amount) external {
        VAULT_HUB.mock_simulateRewards(VAULT, amount);
    }

    function mock_increaseLiability(uint256 amount) external {
        VAULT_HUB.mock_increaseLiability(VAULT, amount);
    }

    function liabilityShares() external view returns (uint256) {
        return VAULT_HUB.vaultLiabilityShares(VAULT);
    }

    // Mock implementation for minting stETH
    function mintShares(address to, uint256 amount) external {
        VAULT_HUB.mintShares(VAULT, to, amount);
    }

    function mintWstETH(address to, uint256 amount) external {
        VAULT_HUB.mintShares(VAULT, address(this), amount);
        uint256 mintedStETH = STETH.getPooledEthBySharesRoundUp(amount);
        uint256 wrappedWstETH = WSTETH.wrap(mintedStETH);
        require(WSTETH.transfer(to, wrappedWstETH), "transfer failed");
    }

    function burnShares(uint256 amount) external {
        STETH.transferSharesFrom(msg.sender, address(VAULT_HUB), amount);
        VAULT_HUB.burnShares(VAULT, amount);
    }

    function burnWstETH(uint256 amount) external {
        require(WSTETH.transferFrom(msg.sender, address(this), amount), "transferFrom failed");
        uint256 unwrappedStETH = WSTETH.unwrap(amount);
        uint256 unwrappedShares = STETH.getSharesByPooledEth(unwrappedStETH);

        STETH.transferShares(address(VAULT_HUB), unwrappedShares);
        VAULT_HUB.burnShares(VAULT, unwrappedShares);
    }

    function remainingMintingCapacityShares(
        uint256 /* vaultId */
    )
        external
        pure
        returns (uint256)
    {
        return 1000 ether; // Mock large capacity
    }

    function totalMintingCapacityShares() external pure returns (uint256) {
        return 1000 ether; // Mock large capacity
    }

    function vaultConnection() external view returns (IVaultHub.VaultConnection memory) {
        return VAULT_HUB.vaultConnection(VAULT);
    }

    function requestValidatorExit(bytes calldata pubkeys) external {
        // Mock implementation
    }

    function triggerValidatorWithdrawals(
        bytes calldata pubkeys,
        uint64[] calldata amountsInGwei,
        address refundRecipient
    ) external payable {
        // Mock implementation
    }

    function rebalanceVaultWithShares(uint256 _shares) external {
        _rebalanceVault(_shares);
    }

    function rebalanceVaultWithEther(uint256 _ether) external payable {
        _rebalanceVault(STETH.getSharesByPooledEth(_ether));
        VAULT_HUB.fund{value: msg.value}(VAULT);
    }

    function _rebalanceVault(uint256 _shares) internal {
        VAULT_HUB.rebalance(VAULT, _shares);
    }

    function voluntaryDisconnect() external {
        // Mock implementation
    }

    function connectToVaultHub() external payable {
        // Mock implementation - just accept the ETH for connection deposit
        VAULT_HUB.fund{value: msg.value}(VAULT);
    }

    receive() external payable {}
}

contract MockDashboardFactory {
    function createMockDashboard(address _owner) external returns (MockDashboard) {
        MockVaultHub vaultHub = new MockVaultHub();
        MockStakingVault stakingVault = new MockStakingVault();
        MockStETH steth = MockStETH(vaultHub.LIDO());
        MockWstETH wsteth = new MockWstETH(address(steth));

        steth.mock_setTotalPooled(1000 ether, 800 * 10 ** 18);

        MockDashboard dashboard =
            new MockDashboard(address(steth), address(wsteth), address(vaultHub), address(stakingVault), _owner);

        dashboard.initialize();

        return dashboard;
    }
}
