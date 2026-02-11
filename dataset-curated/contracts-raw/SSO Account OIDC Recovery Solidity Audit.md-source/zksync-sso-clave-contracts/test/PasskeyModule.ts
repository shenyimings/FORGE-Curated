import { fromArrayBuffer, toArrayBuffer } from "@hexagon/base64";
import { decodePartialCBOR } from "@levischuck/tiny-cbor";
import { Deployer } from "@matterlabs/hardhat-zksync-deploy";
import { ECDSASigValue } from "@peculiar/asn1-ecc";
import { AsnParser } from "@peculiar/asn1-schema";
import { bigintToBuf, bufToBigint } from "bigint-conversion";
import { assert, expect } from "chai";
import { randomBytes } from "crypto";
import { parseEther, ZeroAddress } from "ethers";
import * as hre from "hardhat";
import { encodeAbiParameters, Hex, hexToBytes, pad, toHex } from "viem";
import { SmartAccount, Wallet } from "zksync-ethers";
import { base64UrlToUint8Array } from "zksync-sso/utils";

import type { WebAuthValidator } from "../typechain-types";
import { IERC165__factory, IModuleValidator__factory, SsoAccount__factory, WebAuthValidator__factory } from "../typechain-types";
import { ContractFixtures, getProvider, getWallet, LOCAL_RICH_WALLETS, logInfo, RecordedResponse } from "./utils";

/**
 * Decode from a Base64URL-encoded string to an ArrayBuffer. Best used when converting a
 * credential ID from a JSON string to an ArrayBuffer, like in allowCredentials or
 * excludeCredentials.
 *
 * @param buffer Value to decode from base64
 * @param to (optional) The decoding to use, in case it's desirable to decode from base64 instead
 */
export function toBuffer(base64urlString: string, from: "base64" | "base64url" = "base64url"): Uint8Array {
  const _buffer = toArrayBuffer(base64urlString, from === "base64url");
  return new Uint8Array(_buffer);
}

async function deployValidator(wallet: Wallet): Promise<WebAuthValidator> {
  const deployer: Deployer = new Deployer(hre, wallet);
  const passkeyValidatorArtifact = await deployer.loadArtifact("WebAuthValidator");

  const validator = await deployer.deploy(passkeyValidatorArtifact, []);
  return WebAuthValidator__factory.connect(await validator.getAddress(), wallet);
}

/**
 * COSE Keys
 *
 * https://www.iana.org/assignments/cose/cose.xhtml#key-common-parameters
 * https://www.iana.org/assignments/cose/cose.xhtml#key-type-parameters
 */
export enum COSEKEYS {
  kty = 1,
  alg = 3,
  crv = -1,
  x = -2,
  y = -3,
  n = -1,
  e = -2,
}

/**
 * COSE Key Types
 *
 * https://www.iana.org/assignments/cose/cose.xhtml#key-type
 */
export enum COSEKTY {
  OKP = 1,
  EC = 2,
  RSA = 3,
}

/**
 * COSE Algorithms
 *
 * https://www.iana.org/assignments/cose/cose.xhtml#algorithms
 */
export enum COSEALG {
  ES256 = -7,
  EdDSA = -8,
  ES384 = -35,
  ES512 = -36,
  PS256 = -37,
  PS384 = -38,
  PS512 = -39,
  ES256K = -47,
  RS256 = -257,
  RS384 = -258,
  RS512 = -259,
  RS1 = -65535,
}

/**
 * COSE Curves
 *
 * https://www.iana.org/assignments/cose/cose.xhtml#elliptic-curves
 */
export enum COSECRV {
  P256 = 1,
  P384 = 2,
  P521 = 3,
  ED25519 = 6,
  SECP256K1 = 8,
}

export type COSEPublicKey = {
  // Getters
  get(key: COSEKEYS.kty): COSEKTY | undefined;
  get(key: COSEKEYS.alg): COSEALG | undefined;
  // Setters
  set(key: COSEKEYS.kty, value: COSEKTY): void;
  set(key: COSEKEYS.alg, value: COSEALG): void;
};

const r1KeygenParams: EcKeyGenParams = {
  name: "ECDSA",
  namedCurve: "P-256",
};

const r1KeyParams: EcdsaParams = {
  name: "ECDSA",
  hash: { name: "SHA-256" },
};
export function decodeFirst<Type>(input: Uint8Array): Type {
  // Make a copy so we don't mutate the original
  const _input = new Uint8Array(input);
  const decoded = decodePartialCBOR(_input, 0) as [Type, number];

  const [first] = decoded;

  return first;
}

export function fromBuffer(buffer: Uint8Array, to: "base64" | "base64url" = "base64url"): string {
  return fromArrayBuffer(buffer, to === "base64url");
}

async function getCrpytoKeyFromPublicBytes(publicPasskeyXyBytes: Uint8Array[]): Promise<CryptoKey> {
  const recordedPubkeyXBytes = publicPasskeyXyBytes[0];
  const recordedPubkeyYBytes = publicPasskeyXyBytes[1];
  const rawRecordedKeyMaterial = new Uint8Array(65); // 1 byte for prefix, 32 bytes for x, 32 bytes for y
  rawRecordedKeyMaterial[0] = 0x04; // Uncompressed format prefix
  rawRecordedKeyMaterial.set(recordedPubkeyXBytes, 1);
  rawRecordedKeyMaterial.set(recordedPubkeyYBytes, 33);
  const importedKeyMaterial = await crypto.subtle.importKey("raw", rawRecordedKeyMaterial, r1KeygenParams, false, [
    "verify",
  ]);
  return importedKeyMaterial;
}

async function getRawPublicKeyFromWebAuthN(
  publicPasskey: Uint8Array,
): Promise<[Uint8Array, Uint8Array]> {
  const cosePublicKey = decodeFirst<Map<number, unknown>>(publicPasskey);
  const x = cosePublicKey.get(COSEKEYS.x) as Uint8Array;
  const y = cosePublicKey.get(COSEKEYS.y) as Uint8Array;

  return [x, y];
}

// Expects simple-webauthn public key format
async function getPublicKey(publicPasskey: Uint8Array): Promise<[Hex, Hex]> {
  const [x, y] = await getRawPublicKeyFromWebAuthN(publicPasskey);
  return [`0x${Buffer.from(x).toString("hex")}`, `0x${Buffer.from(y).toString("hex")}`];
}

export async function getRawPublicKeyFromCrpyto(cryptoKeyPair: CryptoKeyPair) {
  const keyMaterial = await crypto.subtle.exportKey("raw", cryptoKeyPair.publicKey);
  return [new Uint8Array(keyMaterial.slice(1, 33)), new Uint8Array(keyMaterial.slice(33, 65))];
}

/**
 * Combine multiple Uint8Arrays into a single Uint8Array
 */
export function concat(arrays: Uint8Array[]): Uint8Array {
  let pointer = 0;
  const totalLength = arrays.reduce((prev, curr) => prev + curr.length, 0);

  const toReturn = new Uint8Array(totalLength);

  arrays.forEach((arr) => {
    toReturn.set(arr, pointer);
    pointer += arr.length;
  });

  return toReturn;
}

/**
 * Return 2 32byte words for the R & S for the EC2 signature, 0 l-trimmed
 * @param signature
 * @returns r & s bytes sequentially
 */
export function unwrapEC2Signature(signature: Uint8Array): [Uint8Array, Uint8Array] {
  const parsedSignature = AsnParser.parse(signature, ECDSASigValue);
  let rBytes = new Uint8Array(parsedSignature.r);
  let sBytes = new Uint8Array(parsedSignature.s);

  if (shouldRemoveLeadingZero(rBytes)) {
    rBytes = rBytes.slice(1);
  }

  if (shouldRemoveLeadingZero(sBytes)) {
    sBytes = sBytes.slice(1);
  }

  return [rBytes, normalizeS(sBytes)];
}

// normalize s (to prevent signature malleability)
function normalizeS(sBuf: Uint8Array): Uint8Array {
  const n = BigInt("0xFFFFFFFF00000000FFFFFFFFFFFFFFFFBCE6FAADA7179E84F3B9CAC2FC632551");
  const halfN = n / BigInt(2);
  const sNumber: bigint = bufToBigint(sBuf);

  if (sNumber / halfN) {
    return new Uint8Array(bigintToBuf(n - sNumber));
  } else {
    return sBuf;
  }
}

// normalize r (to prevent signature malleability)
function normalizeR(rBuf: Uint8Array): Uint8Array {
  const n = BigInt("0xFFFFFFFF00000000FFFFFFFFFFFFFFFFBCE6FAADA7179E84F3B9CAC2FC632551");
  const rNumber: bigint = bufToBigint(rBuf);

  if (rNumber > n) {
    return new Uint8Array(bigintToBuf(n - rNumber));
  } else {
    return rBuf;
  }
}

// denormalize s (to ensure signature malleability)
function denormalizeS(sBuf: Uint8Array): Uint8Array {
  const n = BigInt("0xFFFFFFFF00000000FFFFFFFFFFFFFFFFBCE6FAADA7179E84F3B9CAC2FC632551");
  const halfN = n / BigInt(2);
  const sNumber: bigint = bufToBigint(sBuf);

  if (sNumber / halfN) {
    return sBuf;
  } else {
    return new Uint8Array(bigintToBuf(halfN + sNumber));
  }
}

// denormalize r (to ensure signature malleability)
function denormalizeR(rBuf: Uint8Array): Uint8Array {
  const n = BigInt("0xFFFFFFFF00000000FFFFFFFFFFFFFFFFBCE6FAADA7179E84F3B9CAC2FC632551");
  const rNumber: bigint = bufToBigint(rBuf);

  if (rNumber > n) {
    return rBuf;
  } else {
    return new Uint8Array(bigintToBuf(n));
  }
}

/**
 * Determine if the DER-specific `00` byte at the start of an ECDSA signature byte sequence
 * should be removed based on the following logic:
 *
 * "If the leading byte is 0x0, and the the high order bit on the second byte is not set to 0,
 * then remove the leading 0x0 byte"
 */
function shouldRemoveLeadingZero(bytes: Uint8Array): boolean {
  return bytes[0] === 0x0 && (bytes[1] & (1 << 7)) !== 0;
}

/**
 * Returns hash digest of the given data, using the given algorithm when provided. Defaults to using
 * SHA-256.
 */
export async function toHash(data: Uint8Array | string): Promise<Uint8Array> {
  if (typeof data === "string") {
    data = new TextEncoder().encode(data);
  }

  return new Uint8Array(await crypto.subtle.digest("SHA-256", data));
}

// Generate an ECDSA key pair with the P-256 curve (secp256r1)
export async function generateES256R1Key() {
  return await crypto.subtle.generateKey(r1KeygenParams, false, ["sign", "verify"]);
}

async function signStringWithR1Key(privateKey: CryptoKey, messageBuffer: Uint8Array) {
  const signatureBytes = await crypto.subtle.sign(r1KeyParams, privateKey, messageBuffer);

  // Check for SEQUENCE marker (0x30) for DER encoding
  if (signatureBytes[0] !== 0x30) {
    if (signatureBytes.byteLength != 64) {
      console.error("no idea what format this is");
      return null;
    }
    return {
      r: new Uint8Array(signatureBytes.slice(0, 32)),
      s: new Uint8Array(signatureBytes.slice(32)),
      signature: new Uint8Array(signatureBytes),
    };
  }

  const totalLength = signatureBytes[1];

  if (signatureBytes[2] !== 0x02) {
    console.error("No r marker");
    return null;
  }

  const rLength = signatureBytes[3];

  if (signatureBytes[4 + rLength] !== 0x02) {
    console.error("No s marker");
    return null;
  }

  const sLength = signatureBytes[5 + rLength];

  if (totalLength !== rLength + sLength + 4) {
    console.error("unexpected data");
    return null;
  }

  const r = new Uint8Array(signatureBytes.slice(4, 4 + rLength));
  const s = new Uint8Array(signatureBytes.slice(4 + rLength + 1, 4 + rLength + 1 + sLength));

  return { r, s, signature: new Uint8Array(signatureBytes) };
}

async function verifySignatureWithR1Key(
  messageBuffer: Uint8Array,
  signatureArray: Uint8Array[],
  publicKeyBytes: Uint8Array[],
) {
  const publicKey = await getCrpytoKeyFromPublicBytes(publicKeyBytes);
  const verification = await crypto.subtle.verify(r1KeyParams, publicKey, concat(signatureArray), messageBuffer);

  return verification;
}

function encodeFatSignature(
  passkeyResponse: {
    authenticatorData: string;
    clientDataJSON: string;
    signature: string;
  },
  credentialId: string) {
  const signature = unwrapEC2Signature(base64UrlToUint8Array(passkeyResponse.signature));
  return encodeAbiParameters(
    [
      { type: "bytes" }, // authData
      { type: "bytes" }, // clientDataJson
      { type: "bytes32[2]" }, // signature (two elements)
      { type: "bytes" }, // credentialId
    ],
    [
      toHex(base64UrlToUint8Array(passkeyResponse.authenticatorData)),
      toHex(base64UrlToUint8Array(passkeyResponse.clientDataJSON)),
      [toHex(signature[0]), toHex(signature[1])],
      toHex(base64UrlToUint8Array(credentialId)),
    ],
  );
}

const ZEROKEY = toHex(new Uint8Array(32).fill(0));

async function verifyKeyStorage(
  passkeyValidator: WebAuthValidator,
  domain: string,
  publicKeys,
  credentialId: string,
  wallet: Wallet,
  error: string,
) {
  const storedPublicKey = await passkeyValidator.getAccountKey(domain, credentialId, wallet.address);
  expect(storedPublicKey[0]).to.eq(publicKeys[0], `lower key ${error}`);
  expect(storedPublicKey[1]).to.eq(publicKeys[1], `upper key ${error}`);

  const accountAddress = await passkeyValidator.registeredAddress(domain, credentialId);
  if (publicKeys[0] == ZEROKEY && publicKeys[1] == ZEROKEY) {
    expect(accountAddress).to.eq(ZeroAddress, `key ownership matches for ${error}`);
  } else {
    expect(accountAddress).to.eq(wallet.address, `key ownership matches for ${error}`);
  }
}

function encodeKeyFromHex(credentialId: Hex, keyHexStrings: [Hex, Hex], domain: string) {
  return encodeAbiParameters(
    [
      { name: "credentialId", type: "bytes" },
      { name: "publicKeys", type: "bytes32[2]" },
      { name: "domain", type: "string" },
    ],
    [credentialId, keyHexStrings, domain],
  );
}

export function encodeKeyFromBytes(credentialId: Hex, bytes: [Uint8Array, Uint8Array], domain: string) {
  return encodeKeyFromHex(credentialId, [toHex(bytes[0]), toHex(bytes[1])], domain);
}

async function validateSignatureTest(
  wallet: Wallet,
  keyDomain: string,
  authData: Uint8Array,
  sNormalization: (s: Uint8Array) => Uint8Array,
  rNormalization: (s: Uint8Array) => Uint8Array,
  sampleClientString: string,
  transactionHash: Buffer,
) {
  const passkeyValidator = await deployValidator(wallet);
  const generatedR1Key = await generateES256R1Key();
  const credentialId = toHex(randomBytes(64));

  assert(generatedR1Key != null, "no key was generated");
  const [generatedX, generatedY] = await getRawPublicKeyFromCrpyto(generatedR1Key);
  const addingKey = await passkeyValidator.addValidationKey(credentialId, [generatedX, generatedY], keyDomain);
  const addingKeyResult = await addingKey.wait();
  expect(addingKeyResult?.status).to.eq(1, "failed to add key during setup");

  const sampleClientBuffer = Buffer.from(sampleClientString);
  const partiallyHashedData = concat([authData, await toHash(sampleClientBuffer)]);
  const generatedSignature = await signStringWithR1Key(generatedR1Key.privateKey, partiallyHashedData);
  assert(generatedSignature, "valid generated signature");
  const fatSignature = encodeAbiParameters([
    { name: "authData", type: "bytes" },
    { name: "clientDataJson", type: "string" },
    { name: "rs", type: "bytes32[2]" },
    { name: "credentialId", type: "bytes" },
  ],
  [
    toHex(authData),
    sampleClientString,
    [
      pad(toHex(rNormalization(generatedSignature.r))),
      pad(toHex(sNormalization(generatedSignature.s))),
    ],
    credentialId,
  ]);
  return await passkeyValidator.validateSignature(transactionHash, fatSignature);
}

describe("Passkey validation", function () {
  const wallet = getWallet(LOCAL_RICH_WALLETS[0].privateKey);
  const otherWallet = getWallet(LOCAL_RICH_WALLETS[1].privateKey);
  const ethersResponse = new RecordedResponse("test/signed-challenge.json");
  // this is a binary object formatted by @simplewebauthn that contains the alg type and public key
  const publicKeyEs256Bytes = new Uint8Array([
    165, 1, 2, 3, 38, 32, 1, 33, 88, 32, 167, 69, 109, 166, 67, 163, 110, 143, 71, 60, 77, 232, 220, 7, 121, 156, 141,
    24, 71, 28, 210, 116, 124, 90, 115, 166, 213, 190, 89, 4, 216, 128, 34, 88, 32, 193, 67, 151, 85, 245, 24, 139, 246,
    220, 204, 228, 76, 247, 65, 179, 235, 81, 41, 196, 37, 216, 117, 201, 244, 128, 8, 73, 37, 195, 20, 194, 9,
  ]);

  describe("account integration", () => {
    const fixtures = new ContractFixtures();
    const provider = getProvider();

    async function deployAccount() {
      const factoryContract = await fixtures.getAaFactory();
      const passKeyModuleAddress = await fixtures.getPasskeyModuleAddress();
      const passKeyModuleContract = await fixtures.getWebAuthnVerifierContract();

      const randomSalt = randomBytes(32);
      const credentialId = toHex(randomBytes(64));
      const sampleDomain = "http://example.com";
      const generatedR1Key = await generateES256R1Key();
      assert(generatedR1Key != null, "no key was generated");
      const [generatedX, generatedY] = await getRawPublicKeyFromCrpyto(generatedR1Key);
      const initPasskeyData = encodeKeyFromBytes(credentialId, [generatedX, generatedY], sampleDomain);

      const passKeyPayload = encodeAbiParameters(
        [{ name: "moduleAddress", type: "address" }, { name: "moduleData", type: "bytes" }],
        [passKeyModuleAddress, initPasskeyData]);
      logInfo(`\`deployProxySsoAccount\` args: ${initPasskeyData}`);
      const deployTx = await factoryContract.deployProxySsoAccount(
        randomSalt,
        [passKeyPayload],
        [wallet.address],
      );

      const deployTxReceipt = await deployTx.wait();
      logInfo(`\`deployProxySsoAccount\` gas used: ${deployTxReceipt?.gasUsed.toString()}`);

      const proxyAccountAddress = deployTxReceipt!.contractAddress!;
      expect(proxyAccountAddress, "the proxy account location via logs").to.not.equal(ZeroAddress, "be a valid address");

      const fundTx = await wallet.sendTransaction({ value: parseEther("1"), to: proxyAccountAddress });
      const receipt = await fundTx.wait();
      expect(receipt.status).to.eq(1, "send funds to proxy account");

      return { passKeyModuleContract, sampleDomain, proxyAccountAddress, generatedR1Key, passKeyModuleAddress, credentialId };
    }

    it("should deploy proxy account via factory", async () => {
      const { passKeyModuleContract, sampleDomain, proxyAccountAddress, generatedR1Key, passKeyModuleAddress, credentialId } = await deployAccount();

      const [generatedX, generatedY] = await getRawPublicKeyFromCrpyto(generatedR1Key);

      const initAccountKey = await passKeyModuleContract.getAccountKey(sampleDomain, credentialId, proxyAccountAddress);
      expect(initAccountKey[0]).to.equal(toHex(generatedX), "initial lower key should exist");
      expect(initAccountKey[1]).to.equal(toHex(generatedY), "initial upper key should exist");

      const account = SsoAccount__factory.connect(proxyAccountAddress, provider);
      assert(await account.isK1Owner(fixtures.wallet.address));
      assert(!await account.isHook(passKeyModuleAddress), "passkey module should not be an execution hook");
      assert(await account.isModuleValidator(passKeyModuleAddress), "passkey module should be a validator");
    });

    it("should sign transaction with passkey", async () => {
      const authData = toBuffer(ethersResponse.authenticatorData);
      const { sampleDomain, proxyAccountAddress, generatedR1Key, passKeyModuleAddress, credentialId } = await deployAccount();

      const sessionAccount = new SmartAccount({
        payloadSigner: async (hash: Hex) => {
          const sampleClientObject = {
            type: "webauthn.get",
            challenge: fromBuffer(hexToBytes(hash)),
            origin: sampleDomain,
            crossOrigin: false,
          };
          const sampleClientString = JSON.stringify(sampleClientObject);
          const sampleClientBuffer = Buffer.from(sampleClientString);
          const partiallyHashedData = concat([authData, await toHash(sampleClientBuffer)]);
          const generatedSignature = await signStringWithR1Key(generatedR1Key.privateKey, partiallyHashedData);
          assert(generatedSignature != null, "no signature generated");
          const fatSignature = encodeAbiParameters([
            { name: "authData", type: "bytes" },
            { name: "clientDataJson", type: "string" },
            { name: "rs", type: "bytes32[2]" },
            { name: "credentialId", type: "bytes" },
          ], [
            toHex(authData),
            sampleClientString,
            [toHex(normalizeR(generatedSignature.r)), toHex(normalizeS(generatedSignature.s))],
            credentialId,
          ]);

          const moduleSignature = encodeAbiParameters(
            [{ name: "signature", type: "bytes" }, { name: "moduleAddress", type: "address" }, { name: "validatorData", type: "bytes" }],
            [fatSignature, passKeyModuleAddress, "0x"]);
          return moduleSignature;
        },
        address: proxyAccountAddress,
        secret: wallet.privateKey, // generatedR1Key.privateKey,
      }, provider);

      const aaTransaction = {
        to: wallet.address,
        type: 113,
        from: proxyAccountAddress,
        data: "0x",
        value: 0,
        chainId: (await provider.getNetwork()).chainId,
        nonce: await provider.getTransactionCount(proxyAccountAddress),
        gasPrice: await provider.getGasPrice(),
        gasLimit: 100_000_000n,
      };

      const signedTransaction = await sessionAccount.signTransaction(aaTransaction);
      const transactionResponse = await provider.broadcastTransaction(signedTransaction);
      const transactionReceipt = await transactionResponse.wait();
      expect(transactionReceipt.status).to.eq(1, "transaction should be successful");
      logInfo(`passkey transaction gas used: ${transactionReceipt?.gasUsed.toString()}`);
    });
  });

  it("should support ERC165 and IModuleValidator", async () => {
    const passkeyValidator = await deployValidator(wallet);
    const ierc165 = IERC165__factory.createInterface().getFunction("supportsInterface").selector;
    const erc165Supported = await passkeyValidator.supportsInterface(ierc165);
    assert(erc165Supported, "should support ERC165");

    const ivalidator = IModuleValidator__factory.createInterface();
    const xoredSelectors
      = BigInt(ivalidator.getFunction("validateSignature").selector)
      ^ BigInt(ivalidator.getFunction("validateTransaction").selector);
    const ivalidatorId = "0x" + xoredSelectors.toString(16).padStart(8, "0");
    const iModuleValidatorSupported = await passkeyValidator.supportsInterface(ivalidatorId);
    assert(iModuleValidatorSupported, "should support IModuleValidator");
  });

  describe("addValidationKey", () => {
    it("should save a passkey", async function () {
      const passkeyValidator = await deployValidator(wallet);
      const credentialId = toHex(randomBytes(64));

      const publicKeys = await getPublicKey(publicKeyEs256Bytes);
      const createdKey = await passkeyValidator.addValidationKey(credentialId, publicKeys, "http://localhost:5173");
      const keyReceipt = await createdKey.wait();
      assert(keyReceipt != null, "key was saved");
      assert(keyReceipt?.status == 1, "key was saved");
      logInfo(`gas used to save a passkey: ${keyReceipt.gasUsed.toString()}`);

      const accountAddress = await passkeyValidator.registeredAddress("http://localhost:5173", credentialId);
      assert(accountAddress == wallet.address, "saved account address");
    });

    it("should add a second validation key", async function () {
      const passkeyValidator = await deployValidator(wallet);
      const credentialId = toHex(randomBytes(64));
      const firstDomain = randomBytes(32).toString("hex");

      const publicKeys = await getPublicKey(publicKeyEs256Bytes);
      const initTransaction = await passkeyValidator.addValidationKey(credentialId, publicKeys, firstDomain);
      const initReceipt = await initTransaction.wait();
      assert(initReceipt?.status == 1, "first domain key was saved");

      const secondDomain = randomBytes(32).toString("hex");
      const secondCreatedKey = await passkeyValidator.addValidationKey(credentialId, publicKeys, secondDomain);
      const keyReceipt = await secondCreatedKey.wait();
      assert(keyReceipt?.status == 1, "second key was saved");

      await verifyKeyStorage(passkeyValidator, firstDomain, publicKeys, credentialId, wallet, "first domain");
      await verifyKeyStorage(passkeyValidator, secondDomain, publicKeys, credentialId, wallet, "second domain");
    });

    it("should add second key to the same domain", async () => {
      const passkeyValidator = await deployValidator(wallet);
      const keyDomain = randomBytes(32).toString("hex");
      const credentialId = toHex(randomBytes(64));
      const generatedR1Key = await generateES256R1Key();
      assert(generatedR1Key != null, "no key was generated");
      const [generatedX, generatedY] = await getRawPublicKeyFromCrpyto(generatedR1Key);
      const generatedKeyAdded = await passkeyValidator.addValidationKey(credentialId, [generatedX, generatedY], keyDomain);
      const receipt = await generatedKeyAdded.wait();
      assert(receipt?.status == 1, "generated key added");

      await verifyKeyStorage(passkeyValidator, keyDomain, [toHex(generatedX), toHex(generatedY)], credentialId, wallet, "first key");

      const nextR1Key = await generateES256R1Key();
      assert(nextR1Key != null, "no second key was generated");
      const [newX, newY] = await getRawPublicKeyFromCrpyto(nextR1Key);
      const keyUpdated = await passkeyValidator.addValidationKey(credentialId, [newX, newY], keyDomain);
      const keyUpdatedReceipt = await keyUpdated.wait();
      assert(keyUpdatedReceipt?.status == 1, "return false instead of revert");
      await verifyKeyStorage(passkeyValidator, keyDomain, [toHex(generatedX), toHex(generatedY)], credentialId, wallet, "ensure it was untouched");

      const newCredentialId = toHex(randomBytes(64));
      const nextKeyAdded = await passkeyValidator.addValidationKey(newCredentialId, [newX, newY], keyDomain);
      const newReceipt = await nextKeyAdded.wait();
      assert(newReceipt?.status == 1, "added new key, same domain");

      await verifyKeyStorage(passkeyValidator, keyDomain, [toHex(newX), toHex(newY)], newCredentialId, wallet, "different key, same domain");
      await verifyKeyStorage(passkeyValidator, keyDomain, [toHex(generatedX), toHex(generatedY)], credentialId, wallet, "not overwritten");
    });

    it("should allow clearing existing key", async () => {
      const passkeyValidator = await deployValidator(wallet);
      const generatedR1Key = await generateES256R1Key();
      assert(generatedR1Key != null, "no key was generated");
      const [generatedX, generatedY] = await getRawPublicKeyFromCrpyto(generatedR1Key);
      const keyDomain = randomBytes(32).toString("hex");
      const credentialId = toHex(randomBytes(64));
      const generatedKeyAdded = await passkeyValidator.addValidationKey(credentialId, [generatedX, generatedY], keyDomain);
      const receipt = await generatedKeyAdded.wait();
      assert(receipt?.status == 1, "generated key added");
      await verifyKeyStorage(passkeyValidator, keyDomain, [toHex(generatedX), toHex(generatedY)], credentialId, wallet, "added");

      const emptyKeyAdded = await passkeyValidator.removeValidationKey(credentialId, keyDomain);
      const emptyReceipt = await emptyKeyAdded.wait();
      assert(emptyReceipt?.status == 1, "key removed");

      const zeroKey = new Uint8Array(32).fill(0);
      await verifyKeyStorage(passkeyValidator, keyDomain, [toHex(zeroKey), toHex(zeroKey)], credentialId, wallet, "key removed");

      const accountAddress = await passkeyValidator.registeredAddress(keyDomain, credentialId);
      assert(accountAddress == ZeroAddress, "removed account address");
    });

    it("should not allow clearing other sender keys", async () => {
      const passkeyValidator = await deployValidator(wallet);
      const generatedR1Key = await generateES256R1Key();
      assert(generatedR1Key != null, "no key was generated");
      const [generatedX, generatedY] = await getRawPublicKeyFromCrpyto(generatedR1Key);
      const keyDomain = randomBytes(32).toString("hex");
      const credentialId = toHex(randomBytes(64));
      const generatedKeyAdded = await passkeyValidator.addValidationKey(credentialId, [generatedX, generatedY], keyDomain);
      const receipt = await generatedKeyAdded.wait();
      assert(receipt?.status == 1, "generated key added");
      await verifyKeyStorage(passkeyValidator, keyDomain, [toHex(generatedX), toHex(generatedY)], credentialId, wallet, "added");

      expect(otherWallet.address).not.to.eq(wallet.address, "different wallet");
      const otherPasskeyValidator = await deployValidator(otherWallet);
      const otherGeneratedKeyAdded = await otherPasskeyValidator.addValidationKey(credentialId, [generatedX, generatedY], keyDomain);
      const duplicateKeyReceipt = await otherGeneratedKeyAdded.wait();
      assert(duplicateKeyReceipt?.status == 1, "attempted duplicate key");

      await verifyKeyStorage(passkeyValidator, keyDomain, [toHex(generatedX), toHex(generatedY)], credentialId, wallet, "old key remains after duplicate");

      const keyRemovalAttempt = await otherPasskeyValidator.removeValidationKey(credentialId, keyDomain);
      const keyRemovalAttemptReceipt = await keyRemovalAttempt.wait();
      assert(keyRemovalAttemptReceipt?.status == 1);

      await verifyKeyStorage(passkeyValidator, keyDomain, [toHex(generatedX), toHex(generatedY)], credentialId, wallet, "old key remains after removal");
    });
  });

  describe("validateSignature", () => {
    it("should validate signature", async function () {
      const passkeyValidator = await deployValidator(wallet);

      const publicKeys = await getPublicKey(ethersResponse.passkeyBytes);
      const fatSignature = encodeFatSignature(
        {
          authenticatorData: ethersResponse.authenticatorData,
          clientDataJSON: ethersResponse.clientData,
          signature: ethersResponse.b64SignedChallenge,
        },
        ethersResponse.credentialId,
      );

      const credentialId = toHex(base64UrlToUint8Array(ethersResponse.credentialId));
      await passkeyValidator.addValidationKey(credentialId, publicKeys, ethersResponse.expectedOrigin);

      // get the signature from the same place the checker gets it
      const clientDataJson = JSON.parse(new TextDecoder().decode(ethersResponse.clientDataBuffer));
      const signatureData = base64UrlToUint8Array(clientDataJson["challenge"]);

      const createdKey = await passkeyValidator.validateSignature(signatureData, fatSignature);
      assert(createdKey, "invalid sig");
    });
  });

  describe("webAuthVerify", () => {
    it("should verify a signature", async () => {
      const keyDomain = randomBytes(32).toString("hex");
      const sampleClientObject = {
        type: "webauthn.get",
        challenge: "iBBiiOGt1aSBy1WAuRGxqU7YzRM5oWpMA9g8MKydjPI",
        origin: keyDomain,
        crossOrigin: false,
      };
      const sampleClientString = JSON.stringify(sampleClientObject);
      const authData = toBuffer(ethersResponse.authenticatorData);
      const transactionHash = Buffer.from(sampleClientObject.challenge, "base64url");
      const isValidSignature = await validateSignatureTest(
        wallet,
        keyDomain,
        authData,
        normalizeS,
        normalizeR,
        sampleClientString,
        transactionHash,
      );
      assert(isValidSignature, "valid signature");
    });

    it("should verify a signature without cross-origin set", async () => {
      const keyDomain = randomBytes(32).toString("hex");
      const sampleClientObject = {
        type: "webauthn.get",
        challenge: "iBBiiOGt1aSBy1WAuRGxqU7YzRM5oWpMA9g8MKydjPI",
        origin: keyDomain,
      };
      const sampleClientString = JSON.stringify(sampleClientObject);
      const authData = toBuffer(ethersResponse.authenticatorData);
      const transactionHash = Buffer.from(sampleClientObject.challenge, "base64url");
      const isValidSignature = await validateSignatureTest(
        wallet,
        keyDomain,
        authData,
        normalizeS,
        normalizeR,
        sampleClientString,
        transactionHash,
      );
      assert(isValidSignature, "valid signature");
    });

    it("should fail to verify a signature with low-s", async () => {
      const keyDomain = randomBytes(32).toString("hex");
      const sampleClientObject = {
        type: "webauthn.get",
        challenge: "iBBiiOGt1aSBy1WAuRGxqU7YzRM5oWpMA9g8MKydjPI",
        origin: keyDomain,
        crossOrigin: false,
      };
      const sampleClientString = JSON.stringify(sampleClientObject);
      const authData = toBuffer(ethersResponse.authenticatorData);
      const transactionHash = Buffer.from(sampleClientObject.challenge, "base64url");
      const isValidSignature = await validateSignatureTest(
        wallet,
        keyDomain,
        authData,
        denormalizeS,
        normalizeR,
        sampleClientString,
        transactionHash,
      );
      assert(!isValidSignature, "invalid signature for s");
    });

    it("should fail to verify a signature with high-r", async () => {
      const keyDomain = randomBytes(32).toString("hex");
      const sampleClientObject = {
        type: "webauthn.get",
        challenge: "iBBiiOGt1aSBy1WAuRGxqU7YzRM5oWpMA9g8MKydjPI",
        origin: keyDomain,
        crossOrigin: false,
      };
      const sampleClientString = JSON.stringify(sampleClientObject);
      const authData = toBuffer(ethersResponse.authenticatorData);
      const transactionHash = Buffer.from(sampleClientObject.challenge, "base64url");
      const isValidSignature = await validateSignatureTest(
        wallet,
        keyDomain,
        authData,
        normalizeS,
        denormalizeR,
        sampleClientString,
        transactionHash,
      );
      assert(!isValidSignature, "invalid signature for s");
    });

    it("should fail to verify a signature with bad auth data", async () => {
      const keyDomain = randomBytes(32).toString("hex");
      const sampleClientObject = {
        type: "webauthn.get",
        challenge: "iBBiiOGt1aSBy1WAuRGxqU7YzRM5oWpMA9g8MKydjPI",
        origin: keyDomain,
        crossOrigin: false,
      };
      const sampleClientString = JSON.stringify(sampleClientObject);
      const invalidAuthData = toBuffer(ethersResponse.authenticatorData);
      invalidAuthData[32] = 0x00;
      const transactionHash = Buffer.from(sampleClientObject.challenge, "base64url");
      const isValidSignature = await validateSignatureTest(
        wallet,
        keyDomain,
        invalidAuthData,
        normalizeS,
        normalizeR,
        sampleClientString,
        transactionHash,
      );
      assert(!isValidSignature, "invalid signature for auth data");
    });

    it("should fail to verify a signature with duplicate json keys", async () => {
      const keyDomain = randomBytes(32).toString("hex");
      const sampleClientObject = {
        type: "webauthn.get",
        challenge: "iBBiiOGt1aSBy1WAuRGxqU7YzRM5oWpMA9g8MKydjPI",
        origin: keyDomain,
        crossOrigin: false,
      };
      // only the last of the duplicate keys is checked, and it is invalid
      const partialClientObject = {
        challenge: "jBBiiOGt1aSBy1WAuRGxqU7YzRM5oWpMA9g8MKydjPI",
      };
      const duplicatedClientString
        = JSON.stringify(sampleClientObject).slice(0, -1)
        + ","
        + JSON.stringify(partialClientObject).slice(1);
      const authData = toBuffer(ethersResponse.authenticatorData);
      const transactionHash = Buffer.from(sampleClientObject.challenge, "base64url");
      const isValidSignature = await validateSignatureTest(
        wallet,
        keyDomain,
        authData,
        normalizeS,
        normalizeR,
        duplicatedClientString,
        transactionHash,
      );
      assert(!isValidSignature, "invalid signature for client data json");
    });

    it("should fail to verify a signature with an empty json", async () => {
      const keyDomain = randomBytes(32).toString("hex");
      const sampleClientObject = {
      };
      const sampleClientString = JSON.stringify(sampleClientObject);
      const authData = toBuffer(ethersResponse.authenticatorData);
      const randomTransactionHash = Buffer.from(randomBytes(32));
      await expect(validateSignatureTest(
        wallet,
        keyDomain,
        authData,
        normalizeS,
        normalizeR,
        sampleClientString,
        randomTransactionHash,
      )).to.be.reverted;
    });

    it("should fail to verify a signature a mismached signature", async () => {
      const keyDomain = randomBytes(32).toString("hex");
      const sampleClientObject = {
        type: "webauthn.get",
        challenge: "iBBiiOGt1aSBy1WAuRGxqU7YzRM5oWpMA9g8MKydjPI",
        origin: keyDomain,
        crossOrigin: false,
      };
      const sampleClientString = JSON.stringify(sampleClientObject);
      const authData = toBuffer(ethersResponse.authenticatorData);
      const randomTransactionHash = Buffer.from(randomBytes(32));
      const isValidSignature = await validateSignatureTest(
        wallet,
        keyDomain,
        authData,
        normalizeS,
        normalizeR,
        sampleClientString,
        randomTransactionHash,
      );
      assert(!isValidSignature, "invalid signature for mismatched signature");
    });

    it("should fail to verify a signature a bad json type", async () => {
      const keyDomain = randomBytes(32).toString("hex");
      const sampleClientObject = {
        type: "webauthn.create",
        challenge: "iBBiiOGt1aSBy1WAuRGxqU7YzRM5oWpMA9g8MKydjPI",
        origin: keyDomain,
        crossOrigin: false,
      };
      const sampleClientString = JSON.stringify(sampleClientObject);
      const authData = toBuffer(ethersResponse.authenticatorData);
      const transactionHash = Buffer.from(sampleClientObject.challenge, "base64url");
      const isValidSignature = await validateSignatureTest(
        wallet,
        keyDomain,
        authData,
        normalizeS,
        normalizeR,
        sampleClientString,
        transactionHash,
      );
      assert(!isValidSignature, "invalid signature for bad type");
    });

    it("should fail to verify a signature a bad origin", async () => {
      const sampleClientObject = {
        type: "webauthn.get",
        challenge: "iBBiiOGt1aSBy1WAuRGxqU7YzRM5oWpMA9g8MKydjPI",
        origin: "http://badorigin.com",
        crossOrigin: false,
      };
      const keyDomain = randomBytes(32).toString("hex");
      const sampleClientString = JSON.stringify(sampleClientObject);
      const authData = toBuffer(ethersResponse.authenticatorData);
      const transactionHash = Buffer.from(sampleClientObject.challenge, "base64url");
      const isValidSignature = await validateSignatureTest(
        wallet,
        keyDomain,
        authData,
        normalizeS,
        normalizeR,
        sampleClientString,
        transactionHash,
      );
      assert(!isValidSignature, "invalid signature for bad origin");
    });
  });
});
