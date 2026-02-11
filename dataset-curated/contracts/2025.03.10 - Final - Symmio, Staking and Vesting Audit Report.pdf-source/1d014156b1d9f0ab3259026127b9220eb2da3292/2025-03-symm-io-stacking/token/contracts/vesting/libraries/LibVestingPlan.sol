// SPDX-License-Identifier: MIT
pragma solidity >=0.8.18;

struct VestingPlan {
	uint256 amount;
	uint256 claimedAmount;
	uint256 startTime;
	uint256 endTime;
}

library VestingPlanOps {
	error AlreadySetup();
	error ShouldClaimFirst();
	error ShouldSetupFirst();
	error PlanIsFinished();

	/// @notice Calculates the unlocked amount for a vesting plan.
	/// @param self The vesting plan.
	/// @return The unlocked token amount.
	function unlockedAmount(VestingPlan storage self) public view returns (uint256) {
		uint256 currentTime = block.timestamp;
		if (currentTime >= self.endTime) return self.amount;
		if (currentTime <= self.startTime) return 0;
		uint256 duration = self.endTime - self.startTime;
		uint256 elapsed = currentTime - self.startTime;
		return (self.amount * elapsed) / duration;
	}

	/// @notice Calculates the locked token amount.
	/// @param self The vesting plan.
	/// @return The locked token amount.
	function lockedAmount(VestingPlan storage self) public view returns (uint256) {
		return self.amount - unlockedAmount(self);
	}

	/// @notice Calculates the claimable amount.
	/// @param self The vesting plan.
	/// @return The claimable token amount.
	function claimable(VestingPlan storage self) public view returns (uint256) {
		return unlockedAmount(self) - self.claimedAmount;
	}

	/// @notice Returns the remaining duration of the vesting plan.
	/// @param self The vesting plan.
	/// @return The number of seconds remaining.
	function remainingDuration(VestingPlan storage self) public view returns (uint256) {
		return self.endTime > block.timestamp ? self.endTime - block.timestamp : 0;
	}

	/// @notice Sets up a new vesting plan.
	/// @dev Reverts if the vesting plan was already set up.
	/// @param self The vesting plan.
	/// @param amount Total tokens allocated.
	/// @param startTime Start time of vesting.
	/// @param endTime End time of vesting.
	/// @return The updated vesting plan.
	function setup(VestingPlan storage self, uint256 amount, uint256 startTime, uint256 endTime) public returns (VestingPlan storage) {
		if (isSetup(self)) revert AlreadySetup();
		self.startTime = startTime;
		self.endTime = endTime;
		self.amount = amount;
		self.claimedAmount = 0;
		return self;
	}

	/// @notice Resets the token amount in a vesting plan.
	/// @dev Reverts if there are claimable tokens or the plan was not setup.
	/// @param self The vesting plan.
	/// @param amount The new total token amount.
	/// @return The updated vesting plan.
	function resetAmount(VestingPlan storage self, uint256 amount) public returns (VestingPlan storage) {
		if (claimable(self) != 0) revert ShouldClaimFirst();
		if (!isSetup(self)) revert ShouldSetupFirst();
		// Rebase the vesting plan from now.
		uint256 remaining = remainingDuration(self);
		if (remaining == 0) revert PlanIsFinished();
		self.startTime = block.timestamp;
		self.endTime = block.timestamp + remaining;
		self.amount = amount;
		self.claimedAmount = 0;
		return self;
	}

	/// @notice Checks if a vesting plan is already set up.
	/// @param self The vesting plan.
	/// @return True if the vesting plan is set up, false otherwise.
	function isSetup(VestingPlan storage self) public view returns (bool) {
		return self.amount != 0;
	}
}
