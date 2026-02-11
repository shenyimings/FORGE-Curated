import { HardhatUserConfig } from 'hardhat/config'
import '@nomicfoundation/hardhat-toolbox'
import '@nomicfoundation/hardhat-foundry'
import dotenv from 'dotenv'
dotenv.config()

import { SolidityUserConfig } from 'hardhat/types'
import toml from 'toml'
import fs from 'fs'

const config: HardhatUserConfig = {
  solidity: getSolidityConfigFromFoundryToml(
    process.env.FOUNDRY_PROFILE || 'default'
  ),
  networks: {
    fork: {
      url: process.env.FORK_URL || 'http://localhost:8545',
    },
    arb1: {
      url: 'https://arb1.arbitrum.io/rpc',
    },
    mainnet: {
      url: 'https://mainnet.infura.io/v3/' + process.env['INFURA_KEY'],
    },
    sepolia: {
      url: 'https://sepolia.infura.io/v3/' + process.env['INFURA_KEY'],
    },
    arbSepolia: {
      url: 'https://sepolia-rollup.arbitrum.io/rpc',
    },
    nova: {
      url: 'https://nova.arbitrum.io/rpc',
    },
    holesky: {
      url: 'https://1rpc.io/holesky',
    },
  },
}

function getSolidityConfigFromFoundryToml(profile: string): SolidityUserConfig {
  const data = toml.parse(fs.readFileSync('foundry.toml', 'utf-8'))

  const defaultConfig = data.profile['default']
  const profileConfig = data.profile[profile || 'default']

  const solidity = {
    version: profileConfig?.solc_version || defaultConfig.solc_version,
    settings: {
      optimizer: {
        enabled: true,
        runs: profileConfig?.optimizer_runs || defaultConfig.optimizer_runs,
      },
    },
  }

  return solidity
}

export default config
