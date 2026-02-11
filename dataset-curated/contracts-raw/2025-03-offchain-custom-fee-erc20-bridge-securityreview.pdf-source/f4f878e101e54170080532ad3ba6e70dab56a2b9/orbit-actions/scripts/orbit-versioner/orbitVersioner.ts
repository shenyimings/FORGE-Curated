import { ethers } from 'hardhat'
import metadataHashes from './referentMetadataHashes.json'
import { HardhatEthersProvider } from '@nomicfoundation/hardhat-ethers/internal/hardhat-ethers-provider'
import {
  IBridge__factory,
  IInbox__factory,
  IRollupCore__factory,
} from '../../typechain-types'

main()
  .then(() => process.exit(0))
  .catch((error: Error) => {
    console.error(error)
  })

/**
 * Interfaces
 */
interface BridgeHashes {
  Inbox: string[]
  Outbox: string[]
  SequencerInbox: string[]
  Bridge: string[]
  RollupEventInbox: string[]
}
interface MetadataHashesByNativeToken {
  eth: BridgeHashes
  erc20: BridgeHashes
}
interface RollupHashes {
  RollupProxy: string[]
  RollupAdminLogic: string[]
  RollupUserLogic: string[]
  ChallengeManager: string[]
}
interface MetadataHashesByVersion {
  [version: string]: MetadataHashesByNativeToken & RollupHashes
}

/**
 * Load the referent metadata hashes
 */

const referentMetadataHashes: MetadataHashesByVersion = metadataHashes

/**
 * Script will
 */
async function main() {
  if (!process.env.INBOX_ADDRESS) {
    throw new Error('INBOX_ADDRESS env variable shall be set')
  }

  /// get provider
  const provider = ethers.provider
  const chainId = (await provider.getNetwork()).chainId
  const inboxAddress = process.env.INBOX_ADDRESS!

  console.log(
    `Get the version of Orbit chain's nitro contracts (inbox ${inboxAddress}), hosted on chain ${chainId}`
  )

  // get all core addresses from inbox address
  const inbox = IInbox__factory.connect(inboxAddress, provider)
  const bridgeAddress = await inbox.bridge()
  const bridge = IBridge__factory.connect(bridgeAddress, provider)
  const seqInboxAddress = await bridge.sequencerInbox()
  const rollupAddress = await bridge.rollup()
  const rollup = IRollupCore__factory.connect(rollupAddress, provider)
  const outboxAddress = await rollup.outbox()
  const challengeManagerAddress = await rollup.challengeManager()
  const rollupEventInboxAddress = await rollup.rollupEventInbox()

  // get metadata hashes
  const metadataHashes: { [key: string]: string } = {
    Inbox: await _getMetadataHash(
      await _getLogicAddress(inboxAddress, provider),
      provider
    ),
    Outbox: await _getMetadataHash(
      await _getLogicAddress(outboxAddress, provider),
      provider
    ),
    SequencerInbox: await _getMetadataHash(
      await _getLogicAddress(seqInboxAddress, provider),
      provider
    ),
    Bridge: await _getMetadataHash(
      await _getLogicAddress(bridgeAddress, provider),
      provider
    ),
    RollupEventInbox: await _getMetadataHash(
      await _getLogicAddress(rollupEventInboxAddress, provider),
      provider
    ),
    RollupProxy: await _getMetadataHash(rollupAddress, provider),
    RollupAdminLogic: await _getMetadataHash(
      await _getLogicAddress(rollupAddress, provider),
      provider
    ),
    RollupUserLogic: await _getMetadataHash(
      await _getAddressAtStorageSlot(
        rollupAddress,
        provider,
        '0x2b1dbce74324248c222f0ec2d5ed7bd323cfc425b336f0253c5ccfda7265546d'
      ),
      provider
    ),
    ChallengeManager: await _getMetadataHash(
      await _getLogicAddress(challengeManagerAddress, provider),
      provider
    ),
  }

  if (process.env.DEV === 'true') {
    console.log('\nMetadataHashes of deployed contracts:', metadataHashes, '\n')
  }

  let isFeeTokenChain = false
  const versions: { [key: string]: string | null } = {}
  // get and print version per bridge contract
  Object.keys(metadataHashes).forEach(key => {
    const { version, isErc20 } = _getVersionOfDeployedContract(
      metadataHashes[key]
    )
    versions[key] = version
    if (isErc20) isFeeTokenChain = true
    console.log(
      `Version of deployed ${key}: ${versions[key] ? versions[key] : 'unknown'}`
    )
  })

  // TODO: make this more generic to support other other upgrade paths in the future
  // TODO: also check  osp
  _checkForPossibleUpgrades(versions, isFeeTokenChain)
}

function _checkForPossibleUpgrades(
  currentVersions: {
    [key: string]: string | null
  },
  isFeeTokenChain: boolean
) {
  const targetVersionsDescending = [
    {
      version: 'v3.0.0',
      actionName: 'BOLD UpgradeAction',
    },
    {
      version: 'v2.1.3',
      actionName: 'NitroContracts2Point1Point3UpgradeAction',
    },
    {
      version: 'v2.1.2',
      actionName: 'NitroContracts2Point1Point2UpgradeAction',
    },
    {
      version: 'v2.1.0',
      actionName: 'NitroContracts2Point1Point0UpgradeAction',
    },
    {
      version: 'v1.2.1',
      actionName: 'NitroContracts1Point2Point1UpgradeAction',
    },
  ]

  for (const target of targetVersionsDescending) {
    if (
      _canBeUpgradedToTargetVersion(
        target.version,
        currentVersions,
        isFeeTokenChain
      )
    ) {
      console.log(
        `This deployment can be upgraded to ${target.version} using ${target.actionName}`
      )
      return
    }
  }

  console.log('No upgrade path found')
}

function _canBeUpgradedToTargetVersion(
  targetVersion: string,
  currentVersions: {
    [key: string]: string | null
  },
  isFeeTokenChain: boolean
): boolean {
  console.log('\nChecking if deployment can be upgraded to', targetVersion)

  let supportedSourceVersionsPerContract: { [key: string]: string[] } = {}
  if (targetVersion === 'v3.0.0') {
    // v3.0.0 will upgrade bridge, inbox, rollupEventInbox, outbox, sequencerInbox, rollup logics, challengeManager
    supportedSourceVersionsPerContract = {
      Inbox: [
        'v1.1.0',
        'v1.1.1',
        'v1.2.0',
        'v1.2.1',
        'v1.3.0',
        'v2.0.0',
        'v2.1.0',
      ],
      Outbox: ['any'],
      Bridge: [
        'v1.1.0',
        'v1.1.1',
        'v1.2.0',
        'v1.2.1',
        'v1.3.0',
        'v2.0.0',
        'v2.1.0',
      ],
      RollupEventInbox: ['any'],
      RollupProxy: ['any'],
      RollupAdminLogic: ['v2.0.0', 'v2.1.0'],
      RollupUserLogic: ['v2.0.0', 'v2.1.0'],
      ChallengeManager: ['v2.0.0', 'v2.1.0'],
      SequencerInbox: ['v1.2.1', 'v1.3.0', 'v2.0.0', 'v2.1.0'],
    }
    if (isFeeTokenChain) {
      // cannot upgrade erc20 orbit chains from v1 to v3 right now due to a storage diff
      supportedSourceVersionsPerContract.Bridge = [
        'v2.0.0',
        'v2.1.0',
        'v2.1.2',
        '2.1.3',
      ]
    }
  } else if (targetVersion === 'v2.1.3') {
    // v2.1.3 will upgrade the SequencerInbox and Inbox contracts to prevent 7702 accounts from calling certain functions
    // v2.1.3 or v3.0.0 must be performed before the parent chain upgrades with 7702
    // has the same prerequisites as v3.0.0
    supportedSourceVersionsPerContract = {
      Inbox: [
        'v1.1.0',
        'v1.1.1',
        'v1.2.0',
        'v1.2.1',
        'v1.3.0',
        'v2.0.0',
        'v2.1.0',
      ],
      Outbox: ['any'],
      Bridge: [
        'v1.1.0',
        'v1.1.1',
        'v1.2.0',
        'v1.2.1',
        'v1.3.0',
        'v2.0.0',
        'v2.1.0',
      ],
      RollupEventInbox: ['any'],
      RollupProxy: ['any'],
      RollupAdminLogic: ['v2.0.0', 'v2.1.0'],
      RollupUserLogic: ['v2.0.0', 'v2.1.0'],
      ChallengeManager: ['v2.0.0', 'v2.1.0'],
      SequencerInbox: ['v1.2.1', 'v1.3.0', 'v2.0.0', 'v2.1.0'],
    }
    if (isFeeTokenChain) {
      supportedSourceVersionsPerContract.Bridge = ['v2.0.0', 'v2.1.0', 'v2.1.2']
    }
  } else if (targetVersion === 'v2.1.2') {
    // v2.1.2 will upgrade the ERC20Bridge contract to set decimals in storage
    // v2.1.2 is only required for custom fee token chains
    // only necessary if ERC20Bridge is < v2.0.0
    // must have performed v2.1.0 upgrade first
    if (!isFeeTokenChain) {
      supportedSourceVersionsPerContract = {
        Inbox: [],
        Outbox: [],
        Bridge: [],
        RollupEventInbox: [],
        RollupProxy: [],
        RollupAdminLogic: [],
        RollupUserLogic: [],
        ChallengeManager: [],
        SequencerInbox: [],
      }
    } else {
      supportedSourceVersionsPerContract = {
        Inbox: ['v1.1.0', 'v1.1.1', 'v1.2.0', 'v1.2.1', 'v1.3.0'],
        Outbox: ['any'],
        Bridge: ['v1.1.0', 'v1.1.1', 'v1.2.0', 'v1.2.1', 'v1.3.0'],
        RollupEventInbox: ['any'],
        RollupProxy: ['any'],
        RollupAdminLogic: ['v2.1.0'],
        RollupUserLogic: ['v2.1.0'],
        ChallengeManager: ['v2.1.0'],
        SequencerInbox: ['v1.2.1', 'v1.3.0', 'v2.0.0', 'v2.1.0'],
      }
    }
  } else if (targetVersion === 'v2.1.0') {
    // v2.1.0 will upgrade rollup logics and challenge manager
    supportedSourceVersionsPerContract = {
      Inbox: ['v1.1.0', 'v1.1.1', 'v1.2.0', 'v1.2.1', 'v1.3.0'],
      Outbox: ['any'],
      Bridge: ['v1.1.0', 'v1.1.1', 'v1.2.0', 'v1.2.1', 'v1.3.0'],
      RollupEventInbox: ['any'],
      RollupProxy: ['any'],
      RollupAdminLogic: ['v1.1.0', 'v1.1.1', 'v1.2.0', 'v1.2.1', 'v1.3.0'],
      RollupUserLogic: ['v1.1.0', 'v1.1.1', 'v1.2.0', 'v1.2.1', 'v1.3.0'],
      ChallengeManager: ['v1.2.1', 'v1.3.0'],
      SequencerInbox: ['v1.2.1', 'v1.3.0', 'v2.0.0', 'v2.1.0'],
    }
  } else if (targetVersion === 'v1.2.1') {
    // v1.2.1 will upgrade sequencer inbox and challenge manager
    supportedSourceVersionsPerContract = {
      Inbox: ['v1.1.0', 'v1.1.1', 'v1.2.0', 'v1.2.1'],
      Outbox: ['any'],
      Bridge: ['v1.1.0', 'v1.1.1', 'v1.2.0', 'v1.2.1'],
      RollupEventInbox: ['any'],
      RollupProxy: ['any'],
      RollupAdminLogic: ['v1.1.0', 'v1.1.1', 'v1.2.0', 'v1.2.1'],
      RollupUserLogic: ['v1.1.0', 'v1.1.1', 'v1.2.0', 'v1.2.1'],
      ChallengeManager: ['v1.1.0', 'v1.1.1', 'v1.2.0', 'v1.2.1'],
      SequencerInbox: ['v1.1.0', 'v1.1.1'],
    }
  } else {
    console.log('Unsupported target version')
    return false
  }

  // check if all contracts can be upgraded to target version
  for (const [contract, supportedSourceVersions] of Object.entries(
    supportedSourceVersionsPerContract
  )) {
    if (supportedSourceVersions.includes('any')) {
      continue
    }
    if (!supportedSourceVersions.includes(currentVersions[contract]!)) {
      // found contract that can't be upgraded to target version
      console.log('Cannot upgrade', contract, 'to', targetVersion)
      return false
    }
  }
  // all contracts can be upgraded to target version
  return true
}

function _getVersionOfDeployedContract(metadataHash: string): {
  version: string | null
  isErc20: boolean
} {
  for (const [version] of Object.entries(referentMetadataHashes)) {
    // check if given hash matches any of the referent hashes for specific version
    const versionHashes = referentMetadataHashes[version]
    const allHashes = [
      ...Object.values(versionHashes.eth).flat(),
      ...Object.values(versionHashes.erc20).flat(),
      ...versionHashes.RollupProxy,
      ...versionHashes.RollupAdminLogic,
      ...versionHashes.RollupUserLogic,
      ...versionHashes.ChallengeManager,
    ]

    const erc20Hashes = [...Object.values(versionHashes.erc20).flat()]

    if (allHashes.includes(metadataHash)) {
      if (erc20Hashes.includes(metadataHash)) {
        return { version, isErc20: true }
      }
      return { version, isErc20: false }
    }
  }
  return { version: null, isErc20: false }
}

async function _getMetadataHash(
  contractAddress: string,
  provider: HardhatEthersProvider
): Promise<string> {
  const bytecode = await provider.getCode(contractAddress)

  // Pattern to match the metadata prefix and the following 64 hex characters (32 bytes)
  const metadataPattern = /a264697066735822([a-fA-F0-9]{64})/
  const matches = bytecode.match(metadataPattern)

  if (matches && matches.length > 1) {
    // The actual metadata hash is in the first capturing group
    return matches[1]
  } else {
    throw new Error('No metadata hash found in bytecode')
  }
}

async function _getLogicAddress(
  contractAddress: string,
  provider: HardhatEthersProvider
): Promise<string> {
  const logic = (
    await _getAddressAtStorageSlot(
      contractAddress,
      provider,
      '0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc'
    )
  ).toLowerCase()

  if (logic == '' || logic == ethers.ZeroAddress) {
    return contractAddress
  }

  return logic
}

async function _getAddressAtStorageSlot(
  contractAddress: string,
  provider: HardhatEthersProvider,
  storageSlotBytes: string
): Promise<string> {
  const storageValue = await provider.getStorage(
    contractAddress,
    storageSlotBytes
  )

  if (!storageValue) {
    return ''
  }

  // remove excess bytes
  const formatAddress =
    storageValue.substring(0, 2) + storageValue.substring(26)

  // return address as checksum address
  return ethers.getAddress(formatAddress)
}
