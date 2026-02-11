import { expect } from "chai";
import { ethers } from "ethers";
import { Wallet } from "zksync-ethers";

import { OidcKeyRegistry, OidcKeyRegistry__factory } from "../typechain-types";
import { base64ToCircomBigInt, ContractFixtures, getProvider } from "./utils";

describe("OidcKeyRegistry", function () {
  let fixtures: ContractFixtures;
  let oidcKeyRegistry: OidcKeyRegistry;
  const JWK_MODULUS_64 = "y8TPCPz2Fp0OhBxsxu6d_7erT9f9XJ7mx7ZJPkkeZRxhdnKtg327D4IGYsC4fLAfpkC8qN58sZGkwRTNs-i7yaoD5_8nupq1tPYvnt38ddVghG9vws-2MvxfPQ9m2uxBEdRHmels8prEYGCH6oFKcuWVsNOt4l_OPoJRl4uiuiwd6trZik2GqDD_M6bn21_w6AD_jmbzN4mh8Od4vkA1Z9lKb3Qesksxdog-LWHsljN8ieiz1NhbG7M-GsIlzu-typJfud3tSJ1QHb-E_dEfoZ1iYK7pMcojb5ylMkaCj5QySRdJESq9ngqVRDjF4nX8DK5RQUS7AkrpHiwqyW0Csw";
  const JWK_MODULUS = base64ToCircomBigInt(JWK_MODULUS_64);

  this.beforeEach(async () => {
    fixtures = new ContractFixtures();
    oidcKeyRegistry = await fixtures.getOidcKeyRegistryContract();
  });

  it("should revert when fetching a non-existent key", async () => {
    const issuer = "https://example.com";
    const issHash = await oidcKeyRegistry.hashIssuer(issuer);
    const nonExistentKid = "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef";

    await expect(oidcKeyRegistry.getKey(issHash, nonExistentKid))
      .to.be.revertedWithCustomError(oidcKeyRegistry, "KeyNotFound")
      .withArgs(issHash, nonExistentKid);
  });

  it("should set one key", async () => {
    const issuer = "https://example.com";
    const issHash = await oidcKeyRegistry.hashIssuer(issuer);

    const key = {
      issHash,
      kid: "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef",
      n: JWK_MODULUS,
      e: "0x010001",
    };

    await expect(oidcKeyRegistry.addKey(key))
      .to.emit(oidcKeyRegistry, "KeyAdded")
      .withArgs(issHash, key.kid, key.n);

    const storedKey = await oidcKeyRegistry.getKey(issHash, key.kid);
    expect(storedKey.kid).to.equal(key.kid);
    const expectedN = key.n.map((n) => BigInt(n));
    expect(storedKey.n).to.deep.equal(expectedN);
    expect(storedKey.e).to.equal(key.e);
  });

  it("should set multiple keys", async () => {
    const issuer = "https://example.com";
    const issHash = await oidcKeyRegistry.hashIssuer(issuer);
    const newKeys = Array.from({ length: 8 }, (_, i) => ({
      issHash,
      kid: ethers.keccak256(ethers.toUtf8Bytes(`key${i + 1}`)),
      n: JWK_MODULUS,
      e: "0x010001",
    }));

    for (let i = 0; i < newKeys.length; i++) {
      await expect(oidcKeyRegistry.addKeys([newKeys[i]]))
        .to.emit(oidcKeyRegistry, "KeyAdded")
        .withArgs(issHash, newKeys[i].kid, newKeys[i].n);
    }

    for (let i = 0; i < 8; i++) {
      const storedKey = await oidcKeyRegistry.getKey(issHash, newKeys[i].kid);
      expect(storedKey.kid).to.equal(newKeys[i].kid);
    }
  });

  it("should revert when a non-owner tries to set a key", async () => {
    const issuer = "https://example.com";
    const issHash = await oidcKeyRegistry.hashIssuer(issuer);
    const key = {
      issHash,
      kid: "0x3333333333333333333333333333333333333333333333333333333333333333",
      n: JWK_MODULUS,
      e: "0x010001",
    };

    const nonOwner = Wallet.createRandom(getProvider());
    const nonOwnerRegistry = OidcKeyRegistry__factory.connect(await oidcKeyRegistry.getAddress(), nonOwner);

    await expect(nonOwnerRegistry.addKey(key)).to.be.revertedWith("Ownable: caller is not the owner");
  });

  it("should correctly implement circular key storage", async () => {
    const issuer = "https://example.com";
    const issHash = await oidcKeyRegistry.hashIssuer(issuer);

    const keys = Array.from({ length: 8 }, (_, i) => ({
      issHash,
      kid: ethers.keccak256(ethers.toUtf8Bytes(`key${i + 1}`)),
      n: JWK_MODULUS,
      e: "0x010001",
    }));

    await oidcKeyRegistry.addKeys(keys);

    // Check that the keys are stored correctly
    for (let i = 0; i < 8; i++) {
      const storedKey = await oidcKeyRegistry.getKey(issHash, keys[i].kid);
      expect(storedKey.kid).to.equal(keys[i].kid);
    }

    const moreKeys = Array.from({ length: 8 }, (_, i) => ({
      issHash,
      kid: ethers.keccak256(ethers.toUtf8Bytes(`key${i + 9}`)),
      n: JWK_MODULUS,
      e: "0x010001",
    }));

    await oidcKeyRegistry.addKeys(moreKeys);

    // Check that the new keys are stored correctly
    for (let i = 0; i < 8; i++) {
      const storedKey = await oidcKeyRegistry.getKey(issHash, moreKeys[i].kid);
      expect(storedKey.kid).to.equal(moreKeys[i].kid);
    }

    // Check that the old keys are not stored anymore
    for (let i = 0; i < 8; i++) {
      await expect(oidcKeyRegistry.getKey(issHash, keys[i].kid))
        .to.be.revertedWithCustomError(oidcKeyRegistry, "KeyNotFound")
        .withArgs(issHash, keys[i].kid);
    }
  });

  it("should correctly implement circular key storage with multiple issuers", async () => {
    const issuers = ["https://issuer1.com", "https://issuer2.com"];
    const keysPerIssuer = 4;

    for (const issuer of issuers) {
      const issHash = await oidcKeyRegistry.hashIssuer(issuer);
      const keys = Array.from({ length: keysPerIssuer }, (_, i) => ({
        issHash,
        kid: ethers.keccak256(ethers.toUtf8Bytes(`key${i + 1}-${issuer}`)),
        n: JWK_MODULUS,
        e: "0x010001",
      }));

      await oidcKeyRegistry.addKeys(keys);

      for (let i = 0; i < keysPerIssuer; i++) {
        const storedKey = await oidcKeyRegistry.getKey(issHash, keys[i].kid);
        expect(storedKey.kid).to.equal(keys[i].kid);
      }
    }

    const nonExistentKid = ethers.keccak256(ethers.toUtf8Bytes(`key1-${issuers[1]}`));
    const firstIssuerHash = await oidcKeyRegistry.hashIssuer(issuers[0]);
    await expect(oidcKeyRegistry.getKey(firstIssuerHash, nonExistentKid))
      .to.be.revertedWithCustomError(oidcKeyRegistry, "KeyNotFound")
      .withArgs(firstIssuerHash, nonExistentKid);
  });

  it("should revert when trying to add too many keys", async () => {
    const issuer = "https://example.com";
    const issHash = await oidcKeyRegistry.hashIssuer(issuer);

    const keys = Array.from({ length: 9 }, (_, i) => ({
      issHash,
      kid: ethers.keccak256(ethers.toUtf8Bytes(`key${i + 1}`)),
      n: JWK_MODULUS,
      e: "0x010001",
    }));

    await expect(oidcKeyRegistry.addKeys(keys))
      .to.be.revertedWithCustomError(oidcKeyRegistry, "KeyCountLimitExceeded")
      .withArgs(9);
  });

  it("should revert when adding two different issuers", async () => {
    const issuers = ["https://issuer1.com", "https://issuer2.com"];
    const keysPerIssuer = 4; // Adding the limit for 2 issuers
    const allKeys: { issHash: string; kid: string; n: string[]; e: string }[] = [];

    for (const issuer of issuers) {
      const issHash = await oidcKeyRegistry.hashIssuer(issuer);
      const keys = Array.from({ length: keysPerIssuer }, (_, i) => ({
        issHash,
        kid: ethers.keccak256(ethers.toUtf8Bytes(`key${i + 1}-${issuer}`)),
        n: JWK_MODULUS,
        e: "0x010001",
      }));
      allKeys.push(...keys);
    }

    await expect(oidcKeyRegistry.addKeys(allKeys))
      .to.be.revertedWithCustomError(oidcKeyRegistry, "IssuerHashMismatch")
      .withArgs(allKeys[0].issHash, allKeys[4].issHash);
  });

  it("should revert when adding a key with a zero exponent", async () => {
    const issuer = "https://example.com";
    const issHash = await oidcKeyRegistry.hashIssuer(issuer);
    const key = {
      issHash,
      kid: "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef",
      n: JWK_MODULUS,
      e: "0x000000",
    };

    await expect(oidcKeyRegistry.addKey(key))
      .to.be.revertedWithCustomError(oidcKeyRegistry, "ExponentCannotBeZero")
      .withArgs(0);
  });

  it("should revert when adding a key with a zero modulus", async () => {
    const issuer = "https://example.com";
    const issHash = await oidcKeyRegistry.hashIssuer(issuer);
    const key = {
      issHash,
      kid: "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef",
      n: base64ToCircomBigInt(""),
      e: "0x010001",
    };

    await expect(oidcKeyRegistry.addKey(key))
      .to.be.revertedWithCustomError(oidcKeyRegistry, "ModulusCannotBeZero")
      .withArgs(0);
  });

  it("should revert when adding a key with a zero kid", async () => {
    const issuer = "https://example.com";
    const issHash = await oidcKeyRegistry.hashIssuer(issuer);
    const key = {
      issHash,
      kid: "0x0000000000000000000000000000000000000000000000000000000000000000",
      n: JWK_MODULUS,
      e: "0x010001",
    };

    await expect(oidcKeyRegistry.addKey(key))
      .to.be.revertedWithCustomError(oidcKeyRegistry, "KeyIdCannotBeZero")
      .withArgs(0);
  });

  it("should revert when adding a key with a modulus chunk too large", async () => {
    const issuer = "https://example.com";
    const issHash = await oidcKeyRegistry.hashIssuer(issuer);
    const n = [...JWK_MODULUS];
    n[2] += 1 << 121;
    const key = {
      issHash,
      kid: "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef",
      n,
      e: "0x010001",
    };

    await expect(oidcKeyRegistry.addKey(key))
      .to.be.revertedWithCustomError(oidcKeyRegistry, "ModulusChunkTooLarge")
      .withArgs(0, 2, n[2]);
  });

  it("should remove a key", async () => {
    const issuer = "https://example.com";
    const issHash = await oidcKeyRegistry.hashIssuer(issuer);
    const kid = ethers.keccak256(ethers.toUtf8Bytes("key1"));
    const key = {
      issHash,
      kid,
      n: JWK_MODULUS,
      e: "0x010001",
    };

    await oidcKeyRegistry.addKey(key);
    await expect(oidcKeyRegistry.deleteKey(issHash, kid)).to.emit(oidcKeyRegistry, "KeyDeleted").withArgs(issHash, kid);

    await expect(oidcKeyRegistry.getKey(issHash, kid))
      .to.be.revertedWithCustomError(oidcKeyRegistry, "KeyNotFound")
      .withArgs(issHash, kid);
  });

  it("should revert when a non-owner tries to remove a key", async () => {
    const issuer = "https://example.com";
    const issHash = await oidcKeyRegistry.hashIssuer(issuer);
    const kid = ethers.keccak256(ethers.toUtf8Bytes("key1"));
    const key = {
      issHash,
      kid,
      n: JWK_MODULUS,
      e: "0x010001",
    };

    await oidcKeyRegistry.addKey(key);

    const nonOwner = Wallet.createRandom(getProvider());
    const nonOwnerRegistry = OidcKeyRegistry__factory.connect(await oidcKeyRegistry.getAddress(), nonOwner);

    await expect(nonOwnerRegistry.deleteKey(issHash, kid)).to.be.revertedWith("Ownable: caller is not the owner");
  });

  it("should revert when trying to remove a non-existent key", async () => {
    const issuer = "https://example.com";
    const issHash = await oidcKeyRegistry.hashIssuer(issuer);
    const nonExistentKid = ethers.keccak256(ethers.toUtf8Bytes("key1"));

    await expect(oidcKeyRegistry.deleteKey(issHash, nonExistentKid))
      .to.be.revertedWithCustomError(oidcKeyRegistry, "KeyNotFound")
      .withArgs(issHash, nonExistentKid);
  });

  it("should remove holes when removing keys", async () => {
    const iss = "https://example.com";
    const issHash = await oidcKeyRegistry.hashIssuer(iss);
    const keys = Array.from({ length: 8 }, (_, i) => ({
      issHash,
      kid: ethers.keccak256(ethers.toUtf8Bytes(`key${i + 1}`)),
      n: JWK_MODULUS,
      e: "0x010001",
    }));

    await oidcKeyRegistry.addKeys(keys);

    // Remove the first two keys
    for (let i = 0; i < 2; i++) {
      await expect(oidcKeyRegistry.deleteKey(issHash, keys[i].kid)).to.emit(oidcKeyRegistry, "KeyDeleted").withArgs(issHash, keys[i].kid);
    }

    // Check that the removed keys are not stored anymore
    for (let i = 0; i < 2; i++) {
      await expect(oidcKeyRegistry.getKey(issHash, keys[i].kid))
        .to.be.revertedWithCustomError(oidcKeyRegistry, "KeyNotFound")
        .withArgs(issHash, keys[i].kid);
    }

    // Check that the other keys are still stored
    for (let i = 2; i < 8; i++) {
      const storedKey = await oidcKeyRegistry.getKey(issHash, keys[i].kid);
      expect(storedKey.kid).to.equal(keys[i].kid);
    }

    // Add two new keys
    const newKeys = Array.from({ length: 2 }, (_, i) => ({
      issHash,
      kid: ethers.keccak256(ethers.toUtf8Bytes(`key${i + 9}`)),
      n: JWK_MODULUS,
      e: "0x010001",
    }));

    await oidcKeyRegistry.addKeys(newKeys);

    // Check that the new keys are stored correctly
    for (let i = 0; i < 2; i++) {
      const storedKey = await oidcKeyRegistry.getKey(issHash, newKeys[i].kid);
      expect(storedKey.kid).to.equal(newKeys[i].kid);
    }

    // Check that the other keys are still stored
    for (let i = 2; i < 8; i++) {
      const storedKey = await oidcKeyRegistry.getKey(issHash, keys[i].kid);
      expect(storedKey.kid).to.equal(keys[i].kid);
    }
  });
});
