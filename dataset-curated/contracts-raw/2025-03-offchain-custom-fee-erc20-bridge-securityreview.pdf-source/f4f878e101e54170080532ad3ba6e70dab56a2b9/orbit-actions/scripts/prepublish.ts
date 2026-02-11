import * as fs from 'fs'
import hardhatConfig from '../hardhat.config'

/*
Generates a minimal package.json and hardhat.config.js for publishing to npm
Prompts the user to confirm the changes before writing the files
*/

const packageJson = JSON.parse(fs.readFileSync('package.json', 'utf8'))

const minimalJson = {
  name: packageJson.name,
  version: packageJson.version,
  license: packageJson.license,
  description: packageJson.description,
  author: packageJson.author,
  repository: {
    type: 'git',
    url: packageJson.repository,
  },
  files: ['hardhat.config.js', 'contracts/', 'build/contracts/contracts/'],
  private: false,
  dependencies: packageJson.dependencies,
  scripts: {
    prepublishOnly: 'hardhat clean && hardhat compile',
    build: 'hardhat compile',
    format: 'forge fmt',
  },
}

const minimalHardhatConfig = {
  paths: {
    artifacts: 'build/contracts',
  },
  solidity: hardhatConfig.solidity,
}

console.log(JSON.stringify(minimalHardhatConfig, null, 2))
console.log(JSON.stringify(minimalJson, null, 2))
console.log('Does this package.json and hardhat.config.js look correct? (y/n)')

process.stdin.on('data', data => {
  const answer = data.toString().trim()
  process.stdin.pause()

  if (answer !== 'y') {
    console.log('Aborting')
    process.exit(1)
  }

  fs.renameSync('package.json', 'package.json.bak')
  fs.writeFileSync('package.json', JSON.stringify(minimalJson, null, 2))

  fs.renameSync('hardhat.config.ts', 'hardhat.config.ts.bak')
  fs.writeFileSync(
    'hardhat.config.js',
    `module.exports = ${JSON.stringify(minimalHardhatConfig, null, 2)}`
  )
})
