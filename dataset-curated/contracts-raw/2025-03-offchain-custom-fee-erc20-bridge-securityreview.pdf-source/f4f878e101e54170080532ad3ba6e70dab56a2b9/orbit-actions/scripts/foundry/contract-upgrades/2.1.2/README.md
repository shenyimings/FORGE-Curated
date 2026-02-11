# Nitro contracts 2.1.2 upgrade

> [!CAUTION]
> This is a patch version and is only necessary for custom fee token chains with an `ERC20Bridge` contract below version `< v2.0.0`.
> 
> If your chain uses the parent chain's native asset for fees, or your `ERC20Bridge` is already at `v2.0.0` or above, do not perform this upgrade.
>
> The rest of this document assumes the chain satisfies the above.

These scripts deploy and execute the `NitroContracts2Point1Point2UpgradeAction` contract which allows Orbit chains to upgrade to [2.1.2 release](https://github.com/OffchainLabs/nitro-contracts/releases/tag/v2.1.2). Predeployed instances of the upgrade action exist on the chains listed in the following section.

Upgrading to `v2.1.2` is REQUIRED before upgrading to `v3.0.0`. Upgrading to `v2.1.0` is REQUIRED before upgrading to `v2.1.2`.

`NitroContracts2Point1Point2UpgradeAction` will perform the following action:

1. Upgrade the `ERC20Bridge` contract to `v2.1.2`
1. Force `nativeTokenDecimals` to 18

It is assumed that the native token has 18 decimals, since this was a requirement for deploying a custom fee token chain prior to `v2.0.0`.

## Requirements

This upgrade only support upgrading from the following [nitro-contract release](https://github.com/OffchainLabs/nitro-contracts/releases):

- Inbox: v1.1.0 - v1.3.0 inclusive
- Outbox: v1.1.0 - v1.3.0 inclusive
- SequencerInbox: v1.2.1 - v2.1.0 inclusive
- Bridge: v1.1.0 - v1.3.0 inclusive
- RollupProxy: v1.1.0 - v2.1.0 inclusive
- RollupAdminLogic: v2.1.0
- RollupUserLogic: v2.1.0
- ChallengeManager: v2.1.0

Please refer to the top [README](/README.md#check-version-and-upgrade-path) `Check Version and Upgrade Path` on how to determine your current nitro contracts version.

## Deployed instances

### Mainnets
- L1 Mainnet: TODO
- L2 Arb1: TODO
- L2 Nova: TODO
- L2 Base: TODO

### Testnets
- L1 Sepolia: TODO
- L1 Holesky: TODO
- L2 ArbSepolia: TODO
- L2 BaseSepolia: TODO

## How to use it

1. Setup .env according to the example files, make sure you have everything correctly defined. The .env file must be in project root for recent foundry versions.

> [!CAUTION]
> The .env file must be in project root.

2. (Skip this step if you can use the deployed instances of action contract)
   `DeployNitroContracts2Point1Point2UpgradeActionScript.s.sol` script deploys templates, and upgrade action itself. It can be executed in this directory like this:

```bash
forge script --sender $DEPLOYER --rpc-url $PARENT_CHAIN_RPC --broadcast --slow DeployNitroContracts2Point1Point2UpgradeActionScript -vvv --verify --skip-simulation
# use --account XXX / --private-key XXX / --interactive / --ledger to set the account to send the transaction from
```

As a result, all templates and upgrade action are deployed. Note the last deployed address - that's the upgrade action.

3. `ExecuteNitroContracts2Point1Point2Upgrade.s.sol` script uses previously deployed upgrade action to execute the upgrade. It makes following assumptions - L1UpgradeExecutor is the rollup owner, and there is an EOA which has executor rights on the L1UpgradeExecutor. Proceed with upgrade using the owner account (the one with executor rights on L1UpgradeExecutor):

```bash
forge script --sender $EXECUTOR --rpc-url $PARENT_CHAIN_RPC --broadcast ExecuteNitroContracts2Point1Point2UpgradeScript -vvv
# use --account XXX / --private-key XXX / --interactive / --ledger to set the account to send the transaction from
```

If you have a multisig as executor, you can still run the above command without broadcasting to get the payload for the multisig transaction.

4. That's it, upgrade has been performed. You can make sure it has successfully executed by checking the native token decimals.

```bash
# should return 18
cast call --rpc-url $PARENT_CHAIN_RPC $BRIDGE "nativeTokenDecimals()(uint8)"
```

## FAQ

### Q: intrinsic gas too low when running foundry script

A: try to add -g 1000 to the command
