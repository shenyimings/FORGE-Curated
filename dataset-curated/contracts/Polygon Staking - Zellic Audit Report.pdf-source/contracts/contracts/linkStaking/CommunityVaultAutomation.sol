// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

import {CommunityVCS} from "./CommunityVCS.sol";
import {IVault} from "./interfaces/IVault.sol";
import {AutomationCompatibleInterface} from "@chainlink/contracts/src/v0.8/automation/interfaces/AutomationCompatibleInterface.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract CommunityVaultAutomation is AutomationCompatibleInterface, Ownable {
    CommunityVCS internal communityVCS;
    uint256 public minRewardsTotal;
    uint256 public minRewardsPerVault;

    error RewardsMinimumNotMet();

    constructor(address _communityVCS, uint256 _minRewardsTotal, uint256 _minRewardsPerVault) {
        communityVCS = CommunityVCS(_communityVCS);
        minRewardsTotal = _minRewardsTotal;
        minRewardsPerVault = _minRewardsPerVault;
    }

    /**
     * @notice returns whether or not rewards is equal to or greater than the minimum rewards set
     * @return upkeepNeeded whether or not rewards should be claimed
     * @return performData abi encoded list of vault indexes to claim from
     *
     */
    function checkUpkeep(
        bytes calldata
    ) external returns (bool upkeepNeeded, bytes memory performData) {
        (uint256 totalRewards, uint256[] memory vaultList) = checkRewards();
        if (totalRewards >= minRewardsTotal) {
            return (true, abi.encode(vaultList));
        }
        return (false, abi.encode(vaultList));
    }

    /**
     * @notice Claims rewards from vaults
     * @param performData abi encoded list of vault indexes to claim from
     */
    function performUpkeep(bytes calldata performData) external {
        uint256[] memory vaultList = abi.decode(performData, (uint256[]));

        uint256 claimedRewards = communityVCS.claimRewards(vaultList, minRewardsPerVault);
        if (claimedRewards < minRewardsTotal) {
            revert RewardsMinimumNotMet();
        }
    }

    /**
     * @notice Calculates total rewards from vaults and last index of vaults with rewards
     * @dev The last index is used to avoid iterating over all vaults when claiming rewards to save gas
     * @return (uint256, uint256[]) total rewards from vaults and list of vault indexes that meet the minimum rewards
     */
    function checkRewards() public view returns (uint256, uint256[] memory) {
        IVault[] memory vaults = communityVCS.getVaults();
        uint256 totalRewards = 0;

        uint256 maxVaults = vaults.length;
        uint256[] memory vaultsToClaim = new uint256[](maxVaults);
        uint256 count = 0;

        for (uint256 i = 0; i < vaults.length; i++) {
            IVault vault = IVault(vaults[i]);
            uint256 rewards = vault.getRewards();
            if (rewards >= minRewardsPerVault) {
                totalRewards += rewards;
                vaultsToClaim[count] = i;
                count++;
            }
        }
        uint256[] memory finalVaultsToClaim = new uint256[](count);
        for (uint256 j = 0; j < count; j++) {
            finalVaultsToClaim[j] = vaultsToClaim[j];
        }

        return (totalRewards, finalVaultsToClaim);
    }

    function setCommunityVCS(address _communityVCS) external onlyOwner {
        communityVCS = CommunityVCS(_communityVCS);
    }

    function setMinRewardsTotal(uint256 _minRewards) external onlyOwner {
        minRewardsTotal = _minRewards;
    }

    function setMinRewardsPerVault(uint256 _minRewards) external onlyOwner {
        minRewardsPerVault = _minRewards;
    }
}
