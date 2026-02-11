# Nitro contracts 2.1.0 upgrade

These scripts empower `NitroContracts2Point1Point0UpgradeAction` action contract which performs upgrade to [2.1.0 release](https://github.com/OffchainLabs/nitro-contracts/releases/tag/v2.1.0) of Nitro contracts for existing Orbit chains. Predeployed instances of the upgrade action exists on the chains listed in the following section with vanilla ArbOS32 wasm module root set. If you have a custom nitro machine, you will need to deploy the upgrade action yourself.

NitroContracts2Point1Point0UpgradeAction will perform the following action:

1. Upgrade ChallengeManager to v2.1.0
2. Set the wasm module root to the new version
3. Set the conditional wasm root and one step proof
4. Upgrade RollupAdminLogic and RollupUserLogic contracts

Note that contracts without code changes are not upgraded. It is normal to have some contracts still in the old version after the upgrade as they are equivalent to the new version. After the contract upgrade, you would need to schedule an ArbOS upgrade to ArbOS31 to enable the new features.

## Requirements

This upgrade only support upgrading from the following [nitro-contract release](https://github.com/OffchainLabs/nitro-contracts/releases):

- Inbox: v1.1.0 - v1.3.0 inclusive
- Outbox: v1.1.0 - v1.3.0 inclusive
- SequencerInbox: v1.2.1 - v2.1.0 inclusive
- Bridge: v1.1.0 - v1.3.0 inclusive
- RollupProxy: v1.1.0 - v2.1.0 inclusive
- RollupAdminLogic: v1.1.0 - v1.3.0 inclusive
- RollupUserLogic: v1.1.0 - v1.3.0 inclusive
- ChallengeManager: v1.2.1 - v1.3.0 inclusive

Please refer to the top [README](../../README.md) `Check Version and Upgrade Path` on how to determine your current nitro contracts version.

Also, expectation is that rollup being upgraded currently uses official ArbOS20 wasm module root. If other module root is used upgrade will revert with `NitroContracts2Point1Point0UpgradeAction: wasm root mismatch` message. In case you're using custom module root and want to perform this upgrade, please deploy another instance of upgrade action and provide yours wasm module root as cond root in the constructor.

## Deployed instances

### Mainnets
- L1 Mainnet: 0x7F7C304843e6B933C01A0462cAD0Acc2FBB865E7
- L2 Arb1: 0x6B9a2769B259f36FBd503fec0bbF4408459a3876
- L2 Nova: 0x917e701B4F4ff29dd5e0e1585E88d59147069D29
- L2 Base: 0xA3Cf11DEcb78C4699dAb7039F471F08c0655986C

### Testnets
- L1 Sepolia: 0xa21C4006b9C61d2fd0Bdd6A735dA665509cF649C
- L1 Holesky: 0x02B74b729e3F00BF1f3645f9A9e94dD791b2c348
- L2 ArbSepolia: 0x5A81728757b52e2A3b4889531399B015F24C7772
- L2 BaseSepolia: 0xEa5e25Faf37e5d23eCe60D49b11252794Ac2DA0E

## How to use it

1. Setup .env according to the example files, make sure you have everything correctly defined. The script will do some sanity checks but not everything can be checked. The .env file must be in project root for recent foundry versions.

> [!CAUTION]
> The .env file must be in project root.

2. (Skip this step if you can use the deployed instances of action contract)
   `DeployNitroContracts2Point1Point0UpgradeActionScript.s.sol` script deploys templates, and upgrade action itself. It can be executed in this directory like this:

```bash
forge script --sender $DEPLOYER --rpc-url $PARENT_CHAIN_RPC --broadcast --slow DeployNitroContracts2Point1Point0UpgradeActionScript -vvv --verify --skip-simulation
# use --account XXX / --private-key XXX / --interactive / --ledger to set the account to send the transaction from
```

As a result, all templates and upgrade action are deployed. Note the last deployed address - that's the upgrade action.

3. `ExecuteNitroContracts2Point1Point0Upgrade.s.sol` script uses previously deployed upgrade action to execute the upgrade. It makes following assumptions - L1UpgradeExecutor is the rollup owner, and there is an EOA which has executor rights on the L1UpgradeExecutor. Proceed with upgrade using the owner account (the one with executor rights on L1UpgradeExecutor):

```bash
forge script --sender $EXECUTOR --rpc-url $PARENT_CHAIN_RPC --broadcast ExecuteNitroContracts2Point1Point0UpgradeScript -vvv
# use --account XXX / --private-key XXX / --interactive / --ledger to set the account to send the transaction from
```

If you have a multisig as executor, you can still run the above command without broadcasting to get the payload for the multisig transaction.

4. That's it, upgrade has been performed. You can make sure it has successfully executed by checking wasm module root:

```bash
cast call --rpc-url $PARENT_CHAIN_RPC $ROLLUP "wasmModuleRoot()"
```

## FAQ

### Q: node error: unable to find validator machine directory for the on-chain WASM module root

```
unable to find validator machine directory for the on-chain WASM module root err="stat /home/user/target/machines/0x260f5fa5c3176a856893642e149cf128b5a8de9f828afec8d11184415dd8dc69: no such file or directory"
```

A: upgrade to nitro-node v3.1.0+

### Q: error generating node action: wasmroot doesn't match rollup

```
error acting as staker                   err="error advancing stake from node 0 (hash 0x0000000000000000000000000000000000000000000000000000000000000000): error generating node action: wasmroot doesn't match rollup : 0x260f5fa5c3176a856893642e149cf128b5a8de9f828afec8d11184415dd8dc69, valid: [0x8b104a2e80ac6165dc58b9048de12f301d70b02a0ab51396c22b4b4b802a16a4]"
```

A: make sure there is activity on the child chain and a new batch is posted after the upgrade

### Q: intrinsic gas too low when running foundry script

A: try to add -g 1000 to the command
