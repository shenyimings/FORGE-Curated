import { StandardMerkleTree } from "@openzeppelin/merkle-tree";
import { expect } from "chai";
import { randomBytes } from "crypto";
import { ethers } from "ethers";
import { Hex, pad, parseEther, toHex, zeroAddress } from "viem";
import { Provider, SmartAccount, Wallet } from "zksync-ethers";

import { AAFactory, OidcKeyRegistry, OidcRecoveryValidator, WebAuthValidator } from "../typechain-types";
import { base64ToCircomBigInt, cacheBeforeEach, ContractFixtures, getProvider, LOCAL_RICH_WALLETS } from "./utils";

describe("OidcRecoveryValidator", function () {
  let fixtures: ContractFixtures;
  const provider = getProvider();
  let oidcValidator: OidcRecoveryValidator;
  let keyRegistry: OidcKeyRegistry;
  let webAuthValidator: WebAuthValidator;
  let ownerWallet: Wallet;
  const secondWallet: Wallet = new Wallet(LOCAL_RICH_WALLETS[1].privateKey, provider);
  const testWallet: Wallet = new Wallet("0x447f61a10b23ca123671e0ca8b2bb4f81d3d7485b70be9ec03fe8cdd49b7ec2e", provider);
  const JWK_MODULUS_64 = "305hOVGLdm68E40mUPrxs02vabZGnsqOBEcKQWf4btOP0BWywIwQiRdGDQ3fx5f77HG5ZvZlnvVMkhFCLAGBXT7WeO37fHAKvSgTCN42iMC-x_GjlEuqq3rYP17dDjtiaaRjxQ5BvFgyMnQU5S_xS9m7GHNplVyX-tB53hPprUWzMYPMVBIsFMbN71KdHTF1u5ZqhyUMsIW0CtU-CfBLUF_i9UD8UcbUp0J9Ov7707vKMqve_o2E6ppjs5X8GrPDw2tIqqebPjE49DTK1aww6PiqC93a6o9PNlHm8W2mFx8Dq4MXe5yVIIfAOO0-YmbWc_H1DHlBG2Bu4Z73xOv0lQ";
  const JWK_MODULUS = base64ToCircomBigInt(JWK_MODULUS_64);
  const AUD = "866068535821-e9em0h73pee93q4evoajtnnkldsjhqdk.apps.googleusercontent.com";

  this.beforeEach(async () => {
    fixtures = new ContractFixtures();
    ownerWallet = new Wallet(Wallet.createRandom().privateKey, provider);
    oidcValidator = await fixtures.getOidcRecoveryValidator();
    keyRegistry = await fixtures.getOidcKeyRegistryContract();
    webAuthValidator = await fixtures.getWebAuthnVerifierContract();

    // Fund the test wallet
    await (await fixtures.wallet.sendTransaction({
      value: parseEther("0.2"),
      to: ownerWallet.address,
    })).wait();
    await (await fixtures.wallet.sendTransaction({
      value: parseEther("0.2"),
      to: testWallet.address,
    })).wait();
  });

  describe("addValidationKey", () => {
    it("should add new OIDC validation key", async function () {
      const oidcDigest = ethers.hexlify(randomBytes(32));
      const iss = "https://issuer.com";

      const tx = await oidcValidator.connect(testWallet).addOidcAccount(oidcDigest, iss);
      await tx.wait();

      const storedData = await oidcValidator.connect(testWallet).oidcDataForAddress(testWallet.address);

      expect(storedData.oidcDigest).to.equal(oidcDigest);
      expect(storedData.iss).to.equal(iss);
      // eslint-disable-next-line @typescript-eslint/no-unused-expressions
      expect(storedData.readyToRecover).to.be.false;
      expect(storedData.pendingPasskeyHash).to.equal("0x0000000000000000000000000000000000000000000000000000000000000000");
      expect(storedData.recoverNonce).to.equal(0);
    });

    it("should prevent duplicate oidc_digest registration", async function () {
      const oidcDigest = ethers.hexlify(randomBytes(32));
      const iss = "https://issuer.com";

      // First registration should succeed
      await oidcValidator.connect(testWallet).addOidcAccount(oidcDigest, iss);

      // Create another wallet
      const otherWallet = new Wallet(Wallet.createRandom().privateKey, provider);
      await (await fixtures.wallet.sendTransaction({
        value: parseEther("0.2"),
        to: otherWallet.address,
      })).wait();

      // Second registration with same digest should fail
      await expect(
        oidcValidator.connect(otherWallet).addOidcAccount(oidcDigest, iss),
      ).to.be.revertedWithCustomError(oidcValidator, "OidcDigestAlreadyRegisteredInAnotherAccount")
        .withArgs(oidcDigest);
    });
  });

  describe("deleteOidcAccount", () => {
    it("should delete OIDC account", async function () {
      const oidcDigest = ethers.hexlify(randomBytes(32));
      const iss = "https://issuer.com";

      await oidcValidator.connect(testWallet).addOidcAccount(oidcDigest, iss);
      await expect(oidcValidator.connect(testWallet).deleteOidcAccount()).to.emit(oidcValidator, "OidcAccountDeleted").withArgs(testWallet.address, oidcDigest);
      await expect(oidcValidator.connect(testWallet).oidcDataForAddress(testWallet.address)).to.be.revertedWithCustomError(oidcValidator, "NoOidcDataForGivenAddress")
        .withArgs(testWallet.address);
    });
  });

  describe("startRecovery", () => {
    function makeTuple<T>(a: T, b: T): [T, T] {
      return [a, b];
    }

    function tuple(a: bigint, b: bigint): [Hex, Hex] {
      return makeTuple(toHex(a), toHex(b));
    }

    xit("should start recovery process", async function () {
      const oidcDigest = ethers.hexlify(randomBytes(32));
      const issuer = "https://accounts.google.com";
      const issHash = await keyRegistry.hashIssuer(issuer);

      const key = {
        issHash,
        kid: pad("0x914fb9b087180bc0303284500c5f540c6d4f5e2f"),
        n: JWK_MODULUS,
        e: "0x010001",
      };
      await keyRegistry.addKey(key);

      await oidcValidator.connect(ownerWallet).addOidcAccount(oidcDigest, issuer);

      const keypassPubKey = [ethers.hexlify(randomBytes(32)), ethers.hexlify(randomBytes(32))];
      const keypassPubKeyHash = ethers.keccak256(ethers.AbiCoder.defaultAbiCoder().encode(["bytes32[2]"], [keypassPubKey]));

      const startRecoveryData = {
        zkProof: {
          pA: tuple(16172984678736261064958018006543644663675721049254871031320428491359281707274n, 19682431337788456825193349438229814518020252724069919756952412680705418500225n),
          pB: makeTuple(
            tuple(4150567369693550792379557470122636765225925125808212654712117759263853163613n, 4324367369496459256550590895398624150055064944874752252817645707715962332440n),
            tuple(15155910480833446214566736928531140340900353508329289325257128020116593056943n, 4987027780752140197944134054529005934989743270130418989900064225742700176611n),
          ),
          pC: tuple(3219988720289544328950179753252331035111876645844990660209918063379681209091n, 12683682623277827522761038492333188030929656831193042116084774843687392335592n),
        },
        issHash,
        kid: key.kid,
        pendingPasskeyHash: keypassPubKeyHash,
      };

      await oidcValidator.connect(secondWallet).startRecovery(startRecoveryData, ownerWallet.address, { gasLimit: 20_000_000 });

      const storedData = await oidcValidator.oidcDataForAddress(ownerWallet.address);
      // eslint-disable-next-line @typescript-eslint/no-unused-expressions
      expect(storedData.readyToRecover).to.be.true;
      expect(storedData.pendingPasskeyHash).to.equal(keypassPubKeyHash);
      expect(storedData.recoverNonce).to.equal(1);
    });
  });

  describe("validateTransaction", () => {
    xit("should validate transaction", async function () {
      const issuer = "https://example.com";
      const issHash = await keyRegistry.hashIssuer(issuer);

      const key = {
        issHash,
        kid: "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef",
        n: JWK_MODULUS,
        e: "0x010001",
      };

      // Add key to registry
      await keyRegistry.addKey(key);

      const keys = Array.from({ length: 8 }, () => [
        "0x0000000000000000000000000000000000000000000000000000000000000000",
        "0x0000000000000000000000000000000000000000000000000000000000000000",
        Array(17).fill("0"),
        "0x",
      ]);

      const currentIndex = await keyRegistry.keyIndex();
      const nextIndex = ((currentIndex + 1n) % 8n) as unknown as number;
      keys[nextIndex] = [key.issHash, key.kid, key.n, key.e];

      const tree = StandardMerkleTree.of(keys, ["bytes32", "bytes32", "uint256[17]", "bytes"]);
      const proof = tree.getProof([key.issHash, key.kid, key.n, key.e]);

      const aud = "test-client-id";
      const oidcData = {
        oidcDigest: ethers.hexlify(randomBytes(32)),
        iss: ethers.toUtf8Bytes(issuer),
        aud: ethers.toUtf8Bytes(aud),
      };

      const encodedData = ethers.AbiCoder.defaultAbiCoder().encode(
        ["tuple(bytes32 oidcDigest, bytes iss, bytes aud)"],
        [oidcData],
      );

      await oidcValidator.connect(ownerWallet).addValidationKey(encodedData);

      const signature = {
        zkProof: {
          pA: [ethers.hexlify(randomBytes(32)), ethers.hexlify(randomBytes(32))],
          pB: [
            [ethers.hexlify(randomBytes(32)), ethers.hexlify(randomBytes(32))],
            [ethers.hexlify(randomBytes(32)), ethers.hexlify(randomBytes(32))],
          ],
          pC: [ethers.hexlify(randomBytes(32)), ethers.hexlify(randomBytes(32))],
        },
        key: key,
        merkleProof: proof,
      };

      const encodedSignature = ethers.AbiCoder.defaultAbiCoder().encode(
        ["tuple(tuple(bytes32[2] pA, bytes32[2][2] pB, bytes32[2] pC) zkProof, tuple(bytes32 issHash, bytes32 kid, uint256[17] n, bytes e) key, bytes32[] merkleProof)"],
        [signature],
      );

      const data = webAuthValidator.interface.encodeFunctionData("addValidationKey", ["0x"]);
      const transaction = {
        txType: 0n,
        from: BigInt(ownerWallet.address),
        to: BigInt(await webAuthValidator.getAddress()),
        gasLimit: 0n,
        gasPerPubdataByteLimit: 0n,
        maxFeePerGas: 0n,
        maxPriorityFeePerGas: 0n,
        paymaster: 0n,
        nonce: 0n,
        value: 0n,
        reserved: [0n, 0n, 0n, 0n],
        data,
        signature: "0x01",
        factoryDeps: [],
        paymasterInput: "0x",
        reservedDynamic: "0x",
      };

      // Should not revert
      await oidcValidator.connect(ownerWallet).validateTransaction(
        ethers.hexlify(randomBytes(32)),
        encodedSignature,
        transaction,
      );
    });

    xit("should revert if oidc key is not registered", async function () {
      const issuer = "https://another-example.com";
      const issHash = await keyRegistry.hashIssuer(issuer);

      // Do not add key to registry
      const key = {
        issHash,
        kid: "0xdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef",
        n: JWK_MODULUS,
        e: "0x010001",
      };

      const keys = Array.from({ length: 8 }, () => [
        "0x0000000000000000000000000000000000000000000000000000000000000000",
        "0x0000000000000000000000000000000000000000000000000000000000000000",
        Array(17).fill("0"),
        "0x",
      ]);

      const currentIndex = await keyRegistry.keyIndex();
      const nextIndex = ((currentIndex + 1n) % 8n) as unknown as number;
      keys[nextIndex] = [key.issHash, key.kid, key.n, key.e];

      const tree = StandardMerkleTree.of(keys, ["bytes32", "bytes32", "uint256[17]", "bytes"]);
      const proof = tree.getProof([key.issHash, key.kid, key.n, key.e]);

      const aud = "test-client-id";
      const oidcData = {
        oidcDigest: ethers.hexlify(randomBytes(32)),
        iss: ethers.toUtf8Bytes(issuer),
        aud: ethers.toUtf8Bytes(aud),
      };

      const encodedData = ethers.AbiCoder.defaultAbiCoder().encode(
        ["tuple(bytes32 oidcDigest, bytes iss, bytes aud)"],
        [oidcData],
      );

      await oidcValidator.connect(ownerWallet).addValidationKey(encodedData);

      const signature = {
        zkProof: {
          pA: [ethers.hexlify(randomBytes(32)), ethers.hexlify(randomBytes(32))],
          pB: [
            [ethers.hexlify(randomBytes(32)), ethers.hexlify(randomBytes(32))],
            [ethers.hexlify(randomBytes(32)), ethers.hexlify(randomBytes(32))],
          ],
          pC: [ethers.hexlify(randomBytes(32)), ethers.hexlify(randomBytes(32))],
        },
        key: key,
        merkleProof: proof,
      };

      const encodedSignature = ethers.AbiCoder.defaultAbiCoder().encode(
        ["tuple(tuple(bytes32[2] pA, bytes32[2][2] pB, bytes32[2] pC) zkProof, tuple(bytes32 issHash, bytes32 kid, uint256[17] n, bytes e) key, bytes32[] merkleProof)"],
        [signature],
      );

      const data = webAuthValidator.interface.encodeFunctionData("addValidationKey", ["0x"]);
      const transaction = {
        txType: 0n,
        from: BigInt(ownerWallet.address),
        to: BigInt(await webAuthValidator.getAddress()),
        gasLimit: 0n,
        gasPerPubdataByteLimit: 0n,
        maxFeePerGas: 0n,
        maxPriorityFeePerGas: 0n,
        paymaster: 0n,
        nonce: 0n,
        value: 0n,
        reserved: [0n, 0n, 0n, 0n],
        data,
        signature: "0x01",
        factoryDeps: [],
        paymasterInput: "0x",
        reservedDynamic: "0x",
      };

      await expect(
        oidcValidator.validateTransaction(
          ethers.hexlify(randomBytes(32)),
          encodedSignature,
          transaction,
        ),
      ).to.be.revertedWith("OidcRecoveryValidator: oidc provider pub key not present in key registry");
    });

    xit("should revert if passkey module address is not valid", async function () {
      const issuer = "https://example.com";
      const issHash = await keyRegistry.hashIssuer(issuer);

      const key = {
        issHash,
        kid: "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef",
        n: JWK_MODULUS,
        e: "0x010001",
      };

      // Add key to registry
      await keyRegistry.addKey(key);

      const keys = Array.from({ length: 8 }, () => [
        "0x0000000000000000000000000000000000000000000000000000000000000000",
        "0x0000000000000000000000000000000000000000000000000000000000000000",
        Array(17).fill("0"),
        "0x",
      ]);

      const currentIndex = await keyRegistry.keyIndex();
      const nextIndex = ((currentIndex + 1n) % 8n) as unknown as number;
      keys[nextIndex] = [key.issHash, key.kid, key.n, key.e];

      const tree = StandardMerkleTree.of(keys, ["bytes32", "bytes32", "uint256[17]", "bytes"]);
      const proof = tree.getProof([key.issHash, key.kid, key.n, key.e]);

      const aud = "test-client-id";
      const oidcData = {
        oidcDigest: ethers.hexlify(randomBytes(32)),
        iss: ethers.toUtf8Bytes(issuer),
        aud: ethers.toUtf8Bytes(aud),
      };

      const encodedData = ethers.AbiCoder.defaultAbiCoder().encode(
        ["tuple(bytes32 oidcDigest, bytes iss, bytes aud)"],
        [oidcData],
      );

      await oidcValidator.connect(ownerWallet).addValidationKey(encodedData);

      const signature = {
        zkProof: {
          pA: [ethers.hexlify(randomBytes(32)), ethers.hexlify(randomBytes(32))],
          pB: [
            [ethers.hexlify(randomBytes(32)), ethers.hexlify(randomBytes(32))],
            [ethers.hexlify(randomBytes(32)), ethers.hexlify(randomBytes(32))],
          ],
          pC: [ethers.hexlify(randomBytes(32)), ethers.hexlify(randomBytes(32))],
        },
        key: key,
        merkleProof: proof,
      };

      const encodedSignature = ethers.AbiCoder.defaultAbiCoder().encode(
        ["tuple(tuple(bytes32[2] pA, bytes32[2][2] pB, bytes32[2] pC) zkProof, tuple(bytes32 issHash, bytes32 kid, uint256[17] n, bytes e) key, bytes32[] merkleProof)"],
        [signature],
      );

      const data = webAuthValidator.interface.encodeFunctionData("addValidationKey", ["0x"]);

      const transaction = {
        txType: 0n,
        from: BigInt(ownerWallet.address),
        to: BigInt(ownerWallet.address),
        gasLimit: 0n,
        gasPerPubdataByteLimit: 0n,
        maxFeePerGas: 0n,
        maxPriorityFeePerGas: 0n,
        paymaster: 0n,
        nonce: 0n,
        value: 0n,
        reserved: [0n, 0n, 0n, 0n],
        data,
        signature: "0x01",
        factoryDeps: [],
        paymasterInput: "0x",
        reservedDynamic: "0x",
      };

      await expect(
        oidcValidator.connect(ownerWallet).validateTransaction(
          ethers.hexlify(randomBytes(32)),
          encodedSignature,
          transaction,
        ),
      ).to.be.revertedWith("OidcRecoveryValidator: invalid webauthn validator address");
    });

    xit("should revert with invalid transaction data", async function () {
      const issuer = "https://example.com";
      const issHash = await keyRegistry.hashIssuer(issuer);

      const key = {
        issHash,
        kid: "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef",
        n: JWK_MODULUS,
        e: "0x010001",
      };

      // Add key to registry
      await keyRegistry.addKey(key);

      const keys = Array.from({ length: 8 }, () => [
        "0x0000000000000000000000000000000000000000000000000000000000000000",
        "0x0000000000000000000000000000000000000000000000000000000000000000",
        Array(17).fill("0"),
        "0x",
      ]);

      const currentIndex = await keyRegistry.keyIndex();
      const nextIndex = ((currentIndex + 1n) % 8n) as unknown as number;
      keys[nextIndex] = [key.issHash, key.kid, key.n, key.e];

      const tree = StandardMerkleTree.of(keys, ["bytes32", "bytes32", "uint256[17]", "bytes"]);
      const proof = tree.getProof([key.issHash, key.kid, key.n, key.e]);

      const aud = "test-client-id";
      const oidcData = {
        oidcDigest: ethers.hexlify(randomBytes(32)),
        iss: ethers.toUtf8Bytes(issuer),
        aud: ethers.toUtf8Bytes(aud),
      };

      const encodedData = ethers.AbiCoder.defaultAbiCoder().encode(
        ["tuple(bytes32 oidcDigest, bytes iss, bytes aud)"],
        [oidcData],
      );

      await oidcValidator.connect(ownerWallet).addValidationKey(encodedData);

      const signature = {
        zkProof: {
          pA: [ethers.hexlify(randomBytes(32)), ethers.hexlify(randomBytes(32))],
          pB: [
            [ethers.hexlify(randomBytes(32)), ethers.hexlify(randomBytes(32))],
            [ethers.hexlify(randomBytes(32)), ethers.hexlify(randomBytes(32))],
          ],
          pC: [ethers.hexlify(randomBytes(32)), ethers.hexlify(randomBytes(32))],
        },
        key: key,
        merkleProof: proof,
      };

      const encodedSignature = ethers.AbiCoder.defaultAbiCoder().encode(
        ["tuple(tuple(bytes32[2] pA, bytes32[2][2] pB, bytes32[2] pC) zkProof, tuple(bytes32 issHash, bytes32 kid, uint256[17] n, bytes e) key, bytes32[] merkleProof)"],
        [signature],
      );

      const transaction = {
        txType: 0n,
        from: BigInt(ownerWallet.address),
        to: BigInt(await webAuthValidator.getAddress()),
        gasLimit: 0n,
        gasPerPubdataByteLimit: 0n,
        maxFeePerGas: 0n,
        maxPriorityFeePerGas: 0n,
        paymaster: 0n,
        nonce: 0n,
        value: 0n,
        reserved: [0n, 0n, 0n, 0n],
        data: "0x",
        signature: "0x01",
        factoryDeps: [],
        paymasterInput: "0x",
        reservedDynamic: "0x",
      };

      await expect(
        oidcValidator.connect(ownerWallet).validateTransaction(
          ethers.hexlify(randomBytes(32)),
          encodedSignature,
          transaction,
        ),
      ).to.be.revertedWith("Only function calls are supported");
    });

    xit("should revert with invalid transaction function selector", async function () {
      const issuer = "https://example.com";
      const issHash = await keyRegistry.hashIssuer(issuer);

      const key = {
        issHash,
        kid: "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef",
        n: JWK_MODULUS,
        e: "0x010001",
      };

      // Add key to registry
      await keyRegistry.addKey(key);

      const keys = Array.from({ length: 8 }, () => [
        "0x0000000000000000000000000000000000000000000000000000000000000000",
        "0x0000000000000000000000000000000000000000000000000000000000000000",
        Array(17).fill("0"),
        "0x",
      ]);

      const currentIndex = await keyRegistry.keyIndex();
      const nextIndex = ((currentIndex + 1n) % 8n) as unknown as number;
      keys[nextIndex] = [key.issHash, key.kid, key.n, key.e];

      const tree = StandardMerkleTree.of(keys, ["bytes32", "bytes32", "uint256[17]", "bytes"]);
      const proof = tree.getProof([key.issHash, key.kid, key.n, key.e]);

      const aud = "test-client-id";
      const oidcData = {
        oidcDigest: ethers.hexlify(randomBytes(32)),
        iss: ethers.toUtf8Bytes(issuer),
        aud: ethers.toUtf8Bytes(aud),
      };

      const encodedData = ethers.AbiCoder.defaultAbiCoder().encode(
        ["tuple(bytes32 oidcDigest, bytes iss, bytes aud)"],
        [oidcData],
      );

      await oidcValidator.connect(ownerWallet).addValidationKey(encodedData);

      const signature = {
        zkProof: {
          pA: [ethers.hexlify(randomBytes(32)), ethers.hexlify(randomBytes(32))],
          pB: [
            [ethers.hexlify(randomBytes(32)), ethers.hexlify(randomBytes(32))],
            [ethers.hexlify(randomBytes(32)), ethers.hexlify(randomBytes(32))],
          ],
          pC: [ethers.hexlify(randomBytes(32)), ethers.hexlify(randomBytes(32))],
        },
        key: key,
        merkleProof: proof,
      };

      const encodedSignature = ethers.AbiCoder.defaultAbiCoder().encode(
        ["tuple(tuple(bytes32[2] pA, bytes32[2][2] pB, bytes32[2] pC) zkProof, tuple(bytes32 issHash, bytes32 kid, uint256[17] n, bytes e) key, bytes32[] merkleProof)"],
        [signature],
      );

      const data = webAuthValidator.interface.encodeFunctionData("validateSignature", [ethers.hexlify(randomBytes(32)), "0x"]);
      const transaction = {
        txType: 0n,
        from: BigInt(ownerWallet.address),
        to: BigInt(await webAuthValidator.getAddress()),
        gasLimit: 0n,
        gasPerPubdataByteLimit: 0n,
        maxFeePerGas: 0n,
        maxPriorityFeePerGas: 0n,
        paymaster: 0n,
        nonce: 0n,
        value: 0n,
        reserved: [0n, 0n, 0n, 0n],
        data,
        signature: "0x01",
        factoryDeps: [],
        paymasterInput: "0x",
        reservedDynamic: "0x",
      };

      await expect(
        oidcValidator.connect(ownerWallet).validateTransaction(
          ethers.hexlify(randomBytes(32)),
          encodedSignature,
          transaction,
        ),
      ).to.be.revertedWith("OidcRecoveryValidator: Unauthorized function call");
    });
  });

  describe("JWK Modulus", () => {
    it("should serialize JWK Modulus", async function () {
      const serialized = base64ToCircomBigInt(JWK_MODULUS_64);
      const expected = [
        "2585541717309049811235589644236878997",
        "2334175582383814190061792373180164921",
        "1284905435531671747360881595413676266",
        "1770317779261591924339990404106491201",
        "2538228099739988780003018058671502474",
        "738414494651562022581989730690621175",
        "1007768296435416935062553976399791089",
        "215756340224652444141957566226647577",
        "2631530606953591832080390031565656620",
        "1460212624751936629208657360897879627",
        "82259690604733637890237910425212428",
        "504216172224848588982836147323760475",
        "180434224065375267788699228107952769",
        "1320075548358615991039194601674281098",
        "2501293798923147803875127227049325623",
        "2509960498164270818089470707591578319",
        "4529187227630243827881885689073914",
      ];
      expect(serialized).to.deep.equal(expected);
    });
  });
});
