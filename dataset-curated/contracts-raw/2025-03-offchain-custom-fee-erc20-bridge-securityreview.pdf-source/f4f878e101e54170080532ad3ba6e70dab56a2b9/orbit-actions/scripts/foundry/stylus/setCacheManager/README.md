# Adding the wasm CacheManager

This script empowers `AddWasmCacheManagerAction` contract which deploys and enables CacheManager for the Orbit chain. Please note that the prerequisite for this action is running the ArbOS 32 version which introduces Stylus support.

## How to use it

1. Setup .env according to the example files, make sure you provide correct values. You can use default values for `INIT_CACHE_SIZE` and `INIT_DECAY`.

> [!CAUTION]
> The .env file must be in project root.

`DeployAddWasmCacheManagerAction.s.sol` script deploys `CacheManager` behind the proxy and action `AddWasmCacheManagerAction` contract. It can be executed in this directory like this:

```bash
forge script --sender $DEPLOYER --rpc-url $CHILD_CHAIN_RPC --broadcast --slow ./DeployAddWasmCacheManagerAction.s.sol -vvv --verify --broadcast
# use --account XXX / --private-key XXX / --interactive / --ledger to set the account to send the transaction from
```

This would deploy the action. Update your .env file with the address of the upgrade action.

2. Next step is to execute the AddWasmCacheManager upgrade action. Make sure your .env file contains `UPGRADE_ACTION_ADDRESS` and `CHILD_UPGRADE_EXECUTOR_ADDRESS` vars. Assumption is that child chain UpgradeExecutor is the arbowner, and there is an EOA which has executor rights on the child chain UpgradeExecutor. Upgrade can be executed using `cast` CLI command (part of Foundry installation), using the owner account (the one with executor rights on child chain UpgradeExecutor) to send the transaction:

```bash
(export $(cat .env | xargs) && cast send $CHILD_UPGRADE_EXECUTOR_ADDRESS "execute(address, bytes)" $UPGRADE_ACTION_ADDRESS $(cast calldata "perform()") --rpc-url $CHILD_CHAIN_RPC --account EXECUTOR)
# use --account XXX / --private-key XXX / --interactive / --ledger to set the account to send the transaction from
```

If you have a multisig as executor, you will can use the following command to create the payload for calling into the CHILD_UPGRADE_EXECUTOR:

```bash
(export $(cat .env | xargs) && cast calldata "execute(address, bytes)" $UPGRADE_ACTION_ADDRESS $(cast calldata "perform()"))
```

3. That's it, CacheManager is set. You can check it like this:

```
# List all cache managers
cast call --rpc-url $CHILD_CHAIN_RPC 0x0000000000000000000000000000000000000072 "allCacheManagers() (address[])"
```
