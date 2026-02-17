/// Scenarios to test:
/// [x] restaker undelegates using setNetworkLimit: (stakeAt(now) = 0, stakeAt(now - 1) > 0)
/// [x] restaker undelegates using setOperatorNetworkShares: (stakeAt(now) = 0, stakeAt(now - 1) > 0)
/// [x] burner router receiver config changes. Funds will not be sent to the middleware anymore
/// [~] restaker undelegates, then re-delegates, we should not be able to slash
///     -> we ensure that the current stake is exposed, but the slashing decision is made by the Network contract
/// [ ] restaker wants to opt-out of CAP, prevent new operator loans
///     and give ultimatum to existing ones (how since op don't have any funds at risk?)
/// [ ] slash(..., slashShare) is a percentage of the USD stake, needs to error if > 100%
/// [ ] coverage must account for the burner route
/// [ ] coverage must account for oracle price changes
/// [ ] slash duration must be less than the min vault epoch duration

/// vault validation
/// [ ] must have a burner router as burner
/// [ ] must have a burner router with the correct network receiver
/// [ ] must have an epoch duration > slash duration
/// [ ] delegator must be of type "NetworkRestakeDelegator"
/// [ ] must be registered in symbiotic's vault registry
/// [ ] must have a slasher of type "InstantSlasher"
/// [ ] all the parts must be initialized (burner, delegator, slasher, vault)
