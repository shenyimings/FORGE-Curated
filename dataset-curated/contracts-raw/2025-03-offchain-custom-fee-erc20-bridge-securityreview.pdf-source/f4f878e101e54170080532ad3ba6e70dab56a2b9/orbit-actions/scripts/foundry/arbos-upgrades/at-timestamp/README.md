# ArbOS Upgrade at Timestamp
These scripts empower `UpgradeArbOSVersionAtTimestampAction` contract which schedule an ArbOS at specific timestamp for existing Orbit chains. Please note that ArbOS upgrade usually have a prerequisite of upgrading nitro-contracts and wasm module root to a specific version. Please make sure to check if your orbit chain met those prerequisite before performing ArbOS upgrade.

## How to use it
1. Setup .env according to the example files, make sure you have the correct ArbOS version and timestamp defined in the env file.

`DeployUpgradeArbOSVersionAtTimestampAction.s.sol` script deploys `UpgradeArbOSVersionAtTimestampAction` contract. It can be executed in this directory like this:
```bash
forge script --sender $DEPLOYER --rpc-url $CHILD_CHAIN_RPC --broadcast --slow ./DeployUpgradeArbOSVersionAtTimestampAction.s.sol -vvv --verify
# use --account XXX / --private-key XXX / --interactive / --ledger to set the account to send the transaction from
```
This would deploy the upgrade action. Update your .env file with the address of the upgrade action.

> [!CAUTION]
> The .env file must be in project root.

2. Next step is to execute the ArbOs upgrade action. Assumption is that child chain UpgradeExecutor is the arbowner, and there is an EOA which has executor rights on the child chain UpgradeExecutor. Upgrade can be executed using `cast` CLI command (part of Foundry installation), using the owner account (the one with executor rights on child chain UpgradeExecutor) to send the transaction:
```bash
(export $(cat .env | xargs) && cast send $CHILD_UPGRADE_EXECUTOR_ADDRESS "execute(address, bytes)" $UPGRADE_ACTION_ADDRESS $(cast calldata "perform()") --rpc-url $CHILD_CHAIN_RPC --account EXECUTOR)
# use --account XXX / --private-key XXX / --interactive / --ledger to set the account to send the transaction from
```

If you have a multisig as executor, you will can use the following command to create the payload for calling into the CHILD_UPGRADE_EXECUTOR:
```bash
(export $(cat .env | xargs) && cast calldata "execute(address, bytes)" $UPGRADE_ACTION_ADDRESS $(cast calldata "perform()"))
```

3. That's it, the ArbOS upgrade has been scheduled. You can make sure it has successfully executed by checking:
```
# Check the scheduled upgrade (only avaliable if you are already on ArbOS20 or higher)
cast call --rpc-url $CHILD_CHAIN_RPC 0x000000000000000000000000000000000000006b "getScheduledUpgrade()(uint64, uint64)"

# Check the current ArbOS version (subtract the result by 55 to get the actual version)
cast call --rpc-url $CHILD_CHAIN_RPC 0x0000000000000000000000000000000000000064 "arbOSVersion()(uint64)"
```
