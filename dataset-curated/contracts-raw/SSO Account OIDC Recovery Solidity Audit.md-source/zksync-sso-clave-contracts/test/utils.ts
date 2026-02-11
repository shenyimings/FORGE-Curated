import "@matterlabs/hardhat-zksync-node/dist/type-extensions";
import "@matterlabs/hardhat-zksync-verify/dist/src/type-extensions";

import {
  SnapshotRestorer,
  takeSnapshot,
} from "@nomicfoundation/hardhat-network-helpers";
import dotenv from "dotenv";
import { ethers, parseEther, randomBytes } from "ethers";
import { readFileSync } from "fs";
import { promises } from "fs";
import * as hre from "hardhat";
import { AsyncFunc } from "mocha";
import { Address, isHex, toHex } from "viem";
import { ContractFactory, Provider, utils, Wallet } from "zksync-ethers";
import { base64UrlToUint8Array, getPublicKeyBytesFromPasskeySignature, unwrapEC2Signature } from "zksync-sso/utils";

import type {
  AAFactory,
  AccountProxy,
  ERC20,
  ExampleAuthServerPaymaster,
  Groth16VerifierTest,
  GuardianRecoveryValidator,
  OidcKeyRegistry,
  OidcRecoveryValidator,
  SessionKeyValidator,
  SsoAccount,
  SsoBeacon,
  WebAuthValidator,
} from "../typechain-types";
import {
  AAFactory__factory,
  AccountProxy__factory,
  ERC20__factory,
  ExampleAuthServerPaymaster__factory,
  Groth16VerifierTest__factory,
  GuardianRecoveryValidator__factory,
  OidcKeyRegistry__factory,
  OidcRecoveryValidator__factory,
  SessionKeyValidator__factory,
  SsoAccount__factory,
  SsoBeacon__factory,
  TestPaymaster__factory,
  WebAuthValidator__factory,
} from "../typechain-types";

export const ethersStaticSalt = new Uint8Array([
  205, 241, 161, 186, 101, 105, 79,
  248, 98, 64, 50, 124, 168, 204,
  200, 71, 214, 169, 195, 118, 199,
  62, 140, 111, 128, 47, 32, 21,
  177, 177, 174, 166,
]);

export const CIRCOM_BIGINT_K = 17;
export const CIRCOM_BIGINT_N = 121;

export class ContractFixtures {
  readonly wallet: Wallet = getWallet(LOCAL_RICH_WALLETS[0].privateKey);
  readonly keyRegistryOwner: Wallet = getWallet(LOCAL_RICH_WALLETS[1].privateKey);

  private _aaFactory: AAFactory;
  async getAaFactory() {
    const beaconAddress = await this.getBeaconAddress();
    if (!this._aaFactory) {
      this._aaFactory = await deployFactory(this.wallet, beaconAddress, ethersStaticSalt);
    }
    return this._aaFactory;
  }

  async getAaFactoryAddress() {
    return (await this.getAaFactory()).getAddress();
  }

  private _sessionKeyModule: SessionKeyValidator;
  async getSessionKeyContract() {
    if (!this._sessionKeyModule) {
      const contract = await create2("SessionKeyValidator", this.wallet, ethersStaticSalt);
      this._sessionKeyModule = SessionKeyValidator__factory.connect(await contract.getAddress(), this.wallet);
    }
    return this._sessionKeyModule;
  }

  async getSessionKeyModuleAddress() {
    return (await this.getSessionKeyContract()).getAddress();
  }

  private _beacon: SsoBeacon;
  async getBeaconContract() {
    if (!this._beacon) {
      const implAddress = await this.getAccountImplAddress();
      const contract = await create2("SsoBeacon", this.wallet, ethersStaticSalt, [implAddress]);
      this._beacon = SsoBeacon__factory.connect(await contract.getAddress(), this.wallet);
    }
    return this._beacon;
  }

  async getBeaconAddress() {
    return (await this.getBeaconContract()).getAddress();
  }

  private _webauthnValidatorModule: WebAuthValidator;
  // does passkey validation via modular interface
  async getWebAuthnVerifierContract() {
    if (!this._webauthnValidatorModule) {
      const contract = await create2("WebAuthValidator", this.wallet, ethersStaticSalt);
      this._webauthnValidatorModule = WebAuthValidator__factory.connect(await contract.getAddress(), this.wallet);
    }
    return this._webauthnValidatorModule;
  }

  async getPasskeyModuleAddress(): Promise<Address> {
    const webAuthnVerifierContract = await this.getWebAuthnVerifierContract();
    const contractAddress = await webAuthnVerifierContract.getAddress();
    return isHex(contractAddress) ? contractAddress : toHex(contractAddress);
  }

  private _oidcVerifier: Groth16VerifierTest;
  async getOidcVerifier() {
    if (!this._oidcVerifier) {
      const contract = await create2("Groth16VerifierTest", this.wallet, ethersStaticSalt);
      this._oidcVerifier = Groth16VerifierTest__factory.connect(await contract.getAddress(), this.wallet);
    }
    return this._oidcVerifier;
  }

  private _oidcRecoveryValidator: OidcRecoveryValidator;
  async getOidcRecoveryValidator() {
    if (this._oidcRecoveryValidator === undefined) {
      const verifier = await this.getOidcVerifier();
      const oidcKeyRegistry = await this.getOidcKeyRegistryContract();
      const webAuthValidator = await this.getWebAuthnVerifierContract();
      const contract = await create2("OidcRecoveryValidator", this.wallet, ethersStaticSalt, []);
      const proxyContract = await create2("TransparentProxy", this.wallet, ethersStaticSalt, [
        await contract.getAddress(),
        contract.interface.encodeFunctionData(
          "initialize",
          [await oidcKeyRegistry.getAddress(), await verifier.getAddress(), await webAuthValidator.getAddress()],
        ),
      ]);
      this._oidcRecoveryValidator = OidcRecoveryValidator__factory.connect(await proxyContract.getAddress(), this.wallet);
    }

    return this._oidcRecoveryValidator;
  }

  private _guardianRecoveryValidator: GuardianRecoveryValidator;
  async getGuardianRecoveryValidator() {
    if (this._guardianRecoveryValidator === undefined) {
      const webAuthVerifier = await this.getWebAuthnVerifierContract();
      const contract = await create2("GuardianRecoveryValidator", this.wallet, ethersStaticSalt, []);
      const proxyContract = await create2("TransparentProxy", this.wallet, ethersStaticSalt, [
        await contract.getAddress(),
        contract.interface.encodeFunctionData(
          "initialize",
          [await webAuthVerifier.getAddress()],
        )]);
      this._guardianRecoveryValidator = GuardianRecoveryValidator__factory.connect(await proxyContract.getAddress(), this.wallet);
    }
    return this._guardianRecoveryValidator;
  }

  private _accountImplContract: SsoAccount;
  async getAccountImplContract(salt?: ethers.BytesLike) {
    if (!this._accountImplContract) {
      const contract = await create2("SsoAccount", this.wallet, salt ?? ethersStaticSalt);
      this._accountImplContract = SsoAccount__factory.connect(await contract.getAddress(), this.wallet);
    }
    return this._accountImplContract;
  }

  private _accountProxyContract: AccountProxy;
  async getAccountProxyContract() {
    if (!this._accountProxyContract) {
      const contract = await create2("AccountProxy", this.wallet, ethersStaticSalt, [await this.getBeaconAddress()]);
      this._accountProxyContract = AccountProxy__factory.connect(await contract.getAddress(), this.wallet);
    }
    return this._accountProxyContract;
  }

  private _oicdKeyRegistryContract: OidcKeyRegistry;
  async getOidcKeyRegistryContract() {
    if (!this._oicdKeyRegistryContract) {
      const contract = await create2("OidcKeyRegistry", this.wallet, randomBytes(32));
      const proxyContract = await create2("TransparentProxy", this.wallet, ethersStaticSalt, [await contract.getAddress(), "0x"]);
      this._oicdKeyRegistryContract = OidcKeyRegistry__factory.connect(await proxyContract.getAddress(), this.keyRegistryOwner);
      await this._oicdKeyRegistryContract.initialize();
    }
    return this._oicdKeyRegistryContract;
  }

  async getAccountImplAddress(salt?: ethers.BytesLike) {
    return (await this.getAccountImplContract(salt)).getAddress();
  }

  async deployERC20(mintTo: string): Promise<ERC20> {
    const contract = await create2("TestERC20", this.wallet, ethersStaticSalt, [mintTo]);
    return ERC20__factory.connect(await contract.getAddress(), this.wallet);
  }

  async deployTestPaymaster() {
    const contract = await create2("TestPaymaster", this.wallet, ethersStaticSalt);
    return TestPaymaster__factory.connect(await contract.getAddress(), this.wallet);
  }

  async deployExampleAuthServerPaymaster(
    aaFactoryAddress: string,
    sessionKeyValidatorAddress: string,
    guardianRecoveryValidatorAddress: string,
    webAuthValidatorAddress: string,
    oidcRecoveryValidatorAddress: string,
  ): Promise<ExampleAuthServerPaymaster> {
    const contract = await create2(
      "ExampleAuthServerPaymaster",
      this.wallet,
      ethersStaticSalt,
      [
        aaFactoryAddress,
        sessionKeyValidatorAddress,
        guardianRecoveryValidatorAddress,
        webAuthValidatorAddress,
        oidcRecoveryValidatorAddress,
      ],
    );
    const paymasterAddress = ExampleAuthServerPaymaster__factory.connect(await contract.getAddress(), this.wallet);

    // Fund the paymaster with 1 ETH
    await (
      await this.wallet.sendTransaction({
        to: paymasterAddress,
        value: parseEther("1"),
      })
    ).wait();

    return paymasterAddress;
  }
}

// Load env file
dotenv.config();

export const getProvider = () => {
  const rpcUrl = hre.network.config["url"];
  if (!rpcUrl) throw `⛔️ RPC URL wasn't found in "${hre.network.name}"! Please add a "url" field to the network config in hardhat.config.ts`;

  // Initialize ZKsync Provider
  const provider = new Provider(rpcUrl);

  return provider;
};

export const getProviderL1 = () => {
  const rpcUrl = hre.network.config["ethNetwork"];
  if (!rpcUrl) {
    console.warn(`No ethNetwork URL specified for network ${hre.network.name}`);
  }

  const provider = new ethers.JsonRpcProvider(rpcUrl);
  return provider;
};

export async function deployFactory(wallet: Wallet, beaconAddress: string, salt?: ethers.BytesLike): Promise<AAFactory> {
  const factoryArtifact = JSON.parse(await promises.readFile("artifacts-zk/src/AAFactory.sol/AAFactory.json", "utf8"));
  const proxyAaArtifact = JSON.parse(await promises.readFile("artifacts-zk/src/AccountProxy.sol/AccountProxy.json", "utf8"));

  const deployer = new ContractFactory(factoryArtifact.abi, factoryArtifact.bytecode, wallet, "create2");
  const bytecodeHash = utils.hashBytecode(proxyAaArtifact.bytecode);
  const factoryBytecodeHash = utils.hashBytecode(factoryArtifact.bytecode);
  const factorySalt = ethers.hexlify(salt ?? randomBytes(32));
  const constructorArgs = deployer.interface.encodeDeploy([bytecodeHash, beaconAddress]);
  const standardCreate2Address = utils.create2Address(wallet.address, factoryBytecodeHash, factorySalt, constructorArgs);
  const accountCode = await wallet.provider.getCode(standardCreate2Address);
  if (accountCode != "0x") {
    logInfo(`Factory already exists at ${standardCreate2Address}`);
    return AAFactory__factory.connect(standardCreate2Address, wallet);
  }
  const factory = await deployer.deploy(
    bytecodeHash,
    beaconAddress,
    { customData: { salt: factorySalt, factoryDeps: [proxyAaArtifact.bytecode] } },
  );
  const factoryAddress = await factory.getAddress();

  if (hre.network.config.verifyURL) {
    logInfo(`Requesting contract verification...`);
    logInfo(`src/AAFactory.sol:AAFactory`);
    await verifyContract({
      address: factoryAddress,
      contract: `src/AAFactory.sol:AAFactory`,
      constructorArguments: deployer.interface.encodeDeploy([bytecodeHash, beaconAddress]),
      bytecode: factoryArtifact.bytecode,
    });
  }

  return AAFactory__factory.connect(factoryAddress, wallet);
}

export const getWallet = (privateKey?: string) => {
  if (!privateKey) {
    // Get wallet private key from .env file
    if (!process.env.WALLET_PRIVATE_KEY) throw "Wallet private key wasn't found in .env file!";
  }

  const provider = getProvider();
  const providerL1 = getProviderL1();

  // Initialize zkSync Wallet
  const wallet = new Wallet(privateKey ?? process.env.WALLET_PRIVATE_KEY!, provider, providerL1);

  return wallet;
};

export const verifyEnoughBalance = async (wallet: Wallet, amount: bigint) => {
  // Check if the wallet has enough balance
  const balance = await wallet.getBalance();
  if (balance < amount) throw `Wallet balance is too low! Required ${ethers.formatEther(amount)} ETH, but current ${wallet.address} balance is ${ethers.formatEther(balance)} ETH`;
};

/**
 * @param {string} data.contract The contract's path and name. E.g., "contracts/Greeter.sol:Greeter"
 */
export const verifyContract = async (data: {
  address: string;
  contract: string;
  constructorArguments: string;
  bytecode: string;
}) => {
  const verificationRequestId: number = await hre.run("verify:verify", {
    ...data,
    noCompile: true,
  });
  return verificationRequestId;
};

export const create2 = async (contractName: string, wallet: Wallet, salt: ethers.BytesLike, args?: ReadonlyArray<string>) => {
  salt = ethers.hexlify(salt);
  const contractArtifact = await hre.artifacts.readArtifact(contractName);
  const deployer = new ContractFactory(contractArtifact.abi, contractArtifact.bytecode, wallet, "create2");
  const bytecodeHash = utils.hashBytecode(contractArtifact.bytecode);
  const constructorArgs = deployer.interface.encodeDeploy(args);
  const standardCreate2Address = utils.create2Address(wallet.address, bytecodeHash, salt, args ? constructorArgs : "0x");
  const accountCode = await wallet.provider.getCode(standardCreate2Address);
  if (accountCode != "0x") {
    logInfo(`Contract ${contractName} already exists!`);
    return new ethers.Contract(standardCreate2Address, contractArtifact.abi, wallet);
  }

  const deployingContract = await (args ? deployer.deploy(...args, { customData: { salt } }) : deployer.deploy({ customData: { salt } }));
  const deployedContract = await deployingContract.waitForDeployment();
  const deployedContractAddress = await deployedContract.getAddress();
  logInfo(`"${contractName}" was successfully deployed to ${deployedContractAddress}`);

  if (standardCreate2Address != deployedContractAddress) {
    logWarning("Unexpected Create2 address, perhaps salt is misconfigured?");
    logWarning(`addressFromCreate2: ${standardCreate2Address}`);
    logWarning(`deployedContractAddress: ${deployedContractAddress}`);
  }

  if (hre.network.config.verifyURL) {
    logInfo(`Requesting contract verification...`);
    logInfo(`${contractArtifact.sourceName}:${contractName}`);
    await verifyContract({
      address: deployedContractAddress,
      contract: `${contractArtifact.sourceName}:${contractName}`,
      constructorArguments: constructorArgs,
      bytecode: accountCode,
    });
  }

  return new ethers.Contract(deployedContractAddress, contractArtifact.abi, wallet);
};

export function logInfo(message: string) {
  console.log("\x1b[36m%s\x1b[0m", message);
}

export function logWarning(message: string) {
  console.log("\x1b[33m%s\x1b[0m", message);
}

const masterWallet = ethers.Wallet.fromPhrase("stuff slice staff easily soup parent arm payment cotton trade scatter struggle");

/**
 * Rich wallets can be used for testing purposes.
 * Available on ZKsync In-memory node and docker node.
 */
export const LOCAL_RICH_WALLETS = [
  hre.network.name == "dockerizedNode"
    ? {
        address: masterWallet.address,
        privateKey: masterWallet.privateKey,
      }
    : {
        address: "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
        privateKey: "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80",
      },
  {
    address: "0x36615Cf349d7F6344891B1e7CA7C72883F5dc049",
    privateKey: "0x7726827caac94a7f9e1b160f7ea819f172f7b6f9d2a97f992c38edeab82d4110",
  },
  {
    address: "0xa61464658AfeAf65CccaaFD3a512b69A83B77618",
    privateKey: "0xac1e735be8536c6534bb4f17f06f6afc73b2b5ba84ac2cfb12f7461b20c0bbe3",
  },
  {
    address: "0x0D43eB5B8a47bA8900d84AA36656c92024e9772e",
    privateKey: "0xd293c684d884d56f8d6abd64fc76757d3664904e309a0645baf8522ab6366d9e",
  },
  {
    address: "0xA13c10C0D5bd6f79041B9835c63f91de35A15883",
    privateKey: "0x850683b40d4a740aa6e745f889a6fdc8327be76e122f5aba645a5b02d0248db8",
  },
  {
    address: "0x8002cD98Cfb563492A6fB3E7C8243b7B9Ad4cc92",
    privateKey: "0xf12e28c0eb1ef4ff90478f6805b68d63737b7f33abfa091601140805da450d93",
  },
  {
    address: "0x4F9133D1d3F50011A6859807C837bdCB31Aaab13",
    privateKey: "0xe667e57a9b8aaa6709e51ff7d093f1c5b73b63f9987e4ab4aa9a5c699e024ee8",
  },
  {
    address: "0xbd29A1B981925B94eEc5c4F1125AF02a2Ec4d1cA",
    privateKey: "0x28a574ab2de8a00364d5dd4b07c4f2f574ef7fcc2a86a197f65abaec836d1959",
  },
  {
    address: "0xedB6F5B4aab3dD95C7806Af42881FF12BE7e9daa",
    privateKey: "0x74d8b3a188f7260f67698eb44da07397a298df5427df681ef68c45b34b61f998",
  },
  {
    address: "0xe706e60ab5Dc512C36A4646D719b889F398cbBcB",
    privateKey: "0xbe79721778b48bcc679b78edac0ce48306a8578186ffcb9f2ee455ae6efeace1",
  },
  {
    address: "0xE90E12261CCb0F3F7976Ae611A29e84a6A85f424",
    privateKey: "0x3eb15da85647edd9a1159a4a13b9e7c56877c4eb33f614546d4db06a51868b1c",
  },
];

const convertObjArrayToUint8Array = (objArray: {
  [key: string]: number;
}): Uint8Array => {
  const objEntries = Object.entries(objArray);
  return objEntries.reduce((existingArray, nextKv) => {
    const index = parseInt(nextKv[0]);
    existingArray[index] = nextKv[1];
    return existingArray;
  }, new Uint8Array(objEntries.length));
};

// steps to get the data for this class
// 1. build a transaction in a test (aaTx)
// 2. use this sample signer to get the transaction hash of a realistic transaction
// 3. take that transaction hash to another app, and sign it (as the challenge)
// 4. bring that signed hash back here and have it returned as the signer
export class RecordedResponse {
  constructor(filename: string) {
    // loading directly from the response that was written (verifyAuthenticationResponse)
    const jsonFile = readFileSync(filename, "utf-8");
    const responseData = JSON.parse(jsonFile);
    this.authenticatorData = responseData.response.response.authenticatorData;
    this.clientData = responseData.response.response.clientDataJSON;
    this.b64SignedChallenge = responseData.response.response.signature;
    this.passkeyBytes = convertObjArrayToUint8Array(responseData.authenticator.credentialPublicKey);
    this.expectedOrigin = responseData.expectedOrigin;
    this.credentialId = responseData.authenticator.credentialID;
  }

  getXyPublicKeys() {
    return getPublicKeyBytesFromPasskeySignature(this.passkeyBytes);
  }

  get authDataBuffer() { return base64UrlToUint8Array(this.authenticatorData); }
  get clientDataBuffer() { return base64UrlToUint8Array(this.clientData); }
  get rs() { return unwrapEC2Signature(base64UrlToUint8Array(this.b64SignedChallenge)); }

  // this is the encoded data explaining what authenticator was used (fido, web, etc)
  readonly authenticatorData: string;
  // this is a b64 encoded json object
  readonly clientData: string;
  // signed challange should come from signed transaction hash (challange is the transaction hash)
  readonly b64SignedChallenge: string;
  // This is a binary object formatted by @simplewebauthn that contains the alg type and public key
  readonly passkeyBytes: Uint8Array;
  // the domain linked the passkey that needs to be validated
  readonly expectedOrigin: string;
  // the unique id encoded in the client data
  readonly credentialId: string;
}

const SNAPSHOTS: SnapshotRestorer[] = [];

export function cacheBeforeEach(initializer: AsyncFunc): void {
  let initialized = false;

  beforeEach(async function () {
    if (!initialized) {
      await initializer.call(this);
      SNAPSHOTS.push(await takeSnapshot());
      initialized = true;
    } else {
      const snapshotId = SNAPSHOTS.pop()!;
      await snapshotId.restore();
      SNAPSHOTS.push(await takeSnapshot());
    }
  });

  after(async function () {
    if (initialized) {
      const snapshotId = SNAPSHOTS.pop()!;
      await snapshotId.restore();
    }
  });
}

export const base64ToCircomBigInt = (data: string): string[] => {
  const vec = Buffer.from(data, "base64url").reverse();
  let num = 0n;
  for (let i = 0; i < vec.length; i++) {
    num += BigInt(vec[i]) << BigInt(8 * i);
  }
  const res: string[] = [];
  const msk = (1n << BigInt(CIRCOM_BIGINT_N)) - 1n;
  for (let i = 0; i < CIRCOM_BIGINT_K; ++i) {
    res.push(((num >> BigInt(i * CIRCOM_BIGINT_N)) & msk).toString());
  }
  return res;
};
