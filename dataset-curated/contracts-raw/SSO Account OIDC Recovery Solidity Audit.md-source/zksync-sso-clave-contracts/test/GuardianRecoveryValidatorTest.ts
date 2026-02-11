import * as helpers from "@nomicfoundation/hardhat-network-helpers";
import { expect } from "chai";
import { randomBytes } from "crypto";
import { ethers, HDNodeWallet, keccak256 } from "ethers";
import { Address, parseEther, toHex } from "viem";
import { Provider, SmartAccount, utils, Wallet } from "zksync-ethers";

import { AAFactory, GuardianRecoveryValidator, GuardianRecoveryValidator__factory, SsoAccount, SsoAccount__factory, WebAuthValidator } from "../typechain-types";
import { encodeKeyFromBytes, generateES256R1Key, getRawPublicKeyFromCrpyto } from "./PasskeyModule";
import { cacheBeforeEach, ContractFixtures, getProvider } from "./utils";

describe("GuardianRecoveryValidator", function () {
  const fixtures = new ContractFixtures();
  const abiCoder = new ethers.AbiCoder();
  const provider = getProvider();
  const keyDomain = "origin-domain";
  let guardiansValidatorAddr: Address;
  let factory: AAFactory;
  let ssoAccountInstance: SsoAccount;
  let newGuardianConnectedSsoAccount: SmartAccount;
  let ownerConnectedSsoAccount: SmartAccount;
  let guardianWallet: Wallet;
  let ownerWallet: Wallet;
  let externalUserWallet: Wallet;
  let webauthn: WebAuthValidator;
  let guardianValidator: GuardianRecoveryValidator;
  let hashedOriginDomain: `0x${string}`;

  cacheBeforeEach(async () => {
    guardianWallet = new Wallet(Wallet.createRandom().privateKey, provider);
    ownerWallet = new Wallet(Wallet.createRandom().privateKey, provider);
    externalUserWallet = new Wallet(Wallet.createRandom().privateKey, provider);

    const accountId = `0x${Buffer.from(ethers.toUtf8Bytes("recovery-key-test-id" + randomBytes(32).toString())).toString("hex")}` as `0x${string}`;
    const generatedKey = await generatePassKey(accountId, keyDomain);
    const randomSalt = randomBytes(32);
    hashedOriginDomain = generatedKey.hashedOriginDomain;

    guardianValidator = (await fixtures.getGuardianRecoveryValidator()).connect(ownerWallet);
    webauthn = (await fixtures.getWebAuthnVerifierContract());
    guardiansValidatorAddr = await guardianValidator.getAddress() as Address;
    factory = await fixtures.getAaFactory();
    const initialValidators = [
      ethers.AbiCoder.defaultAbiCoder().encode(["address", "bytes"], [await webauthn.getAddress(), generatedKey.generatedKey]),
      ethers.AbiCoder.defaultAbiCoder().encode(["address", "bytes"], [await guardianValidator.getAddress(), ethers.AbiCoder.defaultAbiCoder().encode(
        ["address[]"],
        [[]],
      )]),
    ];
    const tx = await factory.deployProxySsoAccount(
      randomSalt,
      initialValidators,
      [ownerWallet],
    );
    const receipt = await tx.wait();
    const accountCreatedLog = receipt?.logs.map((x) => {
      const parsedLog = factory.interface.parseLog(x);

      if (parsedLog?.signature === "AccountCreated(address,bytes32)") {
        return parsedLog;
      }
    }).filter((x) => !!x)[0];
    ssoAccountInstance = SsoAccount__factory.connect(accountCreatedLog!.args[0]?.toLowerCase(), fixtures.wallet);
    const ssoAccountInstanceAddress = await ssoAccountInstance.getAddress();
    await (await fixtures.wallet.sendTransaction({ value: parseEther("0.2"), to: ssoAccountInstanceAddress })).wait(); ;
    await (await fixtures.wallet.sendTransaction({ value: parseEther("0.2"), to: guardianWallet.address })).wait();
    newGuardianConnectedSsoAccount = new SmartAccount({
      payloadSigner: async (hash) => {
        const data = abiCoder.encode(
          ["bytes", "address", "bytes"],
          [
            guardianWallet.signingKey.sign(hash).serialized,
            guardiansValidatorAddr,
            abiCoder.encode(
              [],
              [],
            ),
          ],
        );
        return data;
      },
      address: await ssoAccountInstance.getAddress(),
      secret: guardianWallet.privateKey,
    }, provider);
    ownerConnectedSsoAccount = new SmartAccount({
      address: await ssoAccountInstance.getAddress(),
      secret: ownerWallet.privateKey,
    }, provider);
  });

  const randomWallet = async (): Promise<[HDNodeWallet, GuardianRecoveryValidator]> => {
    const wallet = Wallet.createRandom(getProvider());
    const connected = GuardianRecoveryValidator__factory.connect(guardiansValidatorAddr, wallet);
    await fixtures.wallet.sendTransaction({ value: parseEther("0.2"), to: wallet.address });

    return [wallet, connected];
  };

  describe("proposeValidationKey", () => {
    it("can propose a guardian", async function () {
      const [user1, user1ConnectedValidator] = await randomWallet();
      const [guardian] = await randomWallet();

      const tx = await user1ConnectedValidator.proposeValidationKey(hashedOriginDomain, guardian.address);
      await tx.wait();

      const res = await user1ConnectedValidator.guardiansFor(hashedOriginDomain, user1.address);
      expect(res.length).to.equal(1);
      expect(res[0].addr).to.equal(guardian.address);
      expect(res[0].isReady).to.equal(false);
      expect(tx).to.emit(user1ConnectedValidator, "GuardianProposed");
    });
  });

  describe("addValidationKey", () => {
    function callAddValidationKey(contract: GuardianRecoveryValidator, hashedOriginDomain: `0x${string}`, account: string): Promise<ethers.ContractTransactionResponse> {
      return contract.addValidationKey(hashedOriginDomain, account, { gasLimit: "80000000" });
    }

    it("fails when tries to confirm a guardian that was not proposed.", async function () {
      const [user1] = await randomWallet();
      // eslint-disable-next-line @typescript-eslint/no-unused-vars
      const [_, guardianConnection] = await randomWallet();

      await expect(callAddValidationKey(guardianConnection, hashedOriginDomain, user1.address))
        .to.reverted;
    });

    it("fails when tries to confirm a was proposed for a different account.", async function () {
      // eslint-disable-next-line @typescript-eslint/no-unused-vars
      const [_, user1Connection] = await randomWallet();
      const [user2] = await randomWallet();
      const [guardian, guardianConnection] = await randomWallet();

      const tx1 = await user1Connection.proposeValidationKey(hashedOriginDomain, guardian.address);
      await tx1.wait();

      await expect(callAddValidationKey(guardianConnection, hashedOriginDomain, user2.address))
        .to.reverted;
    });

    it("works to confirm a proposed account.", async function () {
      const [user1, user1Connected] = await randomWallet();
      const [guardian, guardianConnected] = await randomWallet();

      await user1Connected.proposeValidationKey(hashedOriginDomain, guardian.address);

      const tx = await callAddValidationKey(guardianConnected, hashedOriginDomain, user1.address);

      const res = await user1Connected.guardiansFor(hashedOriginDomain, user1.address);
      expect(res.length).to.equal(1);
      expect(res[0].addr).to.equal(guardian.address);
      expect(res[0].isReady).to.equal(true);
      expect(tx).to.emit(user1Connected, "GuardianAdded");
    });
  });

  describe("removeValidationKey", () => {
    let guardian: ethers.Signer;
    let user1: ethers.Signer;

    cacheBeforeEach(async () => {
      const [guardianWallet, guardianConnected] = await randomWallet();
      guardian = guardianWallet;
      const [user1Wallet, user1Connected] = await randomWallet();
      user1 = user1Wallet;
      await user1Connected.proposeValidationKey(hashedOriginDomain, guardian.getAddress());
      await guardianConnected.addValidationKey(hashedOriginDomain, user1.getAddress());
    });

    const sut = async (guardianToRemove: string) => {
      return guardianValidator.connect(user1).removeValidationKey(hashedOriginDomain, guardianToRemove);
    };

    it("fails when tries to remove non existing guardian.", async function () {
      const [randomGeneratedWallet] = await randomWallet();

      await expect(sut(await randomGeneratedWallet.getAddress()))
        .to.be.revertedWithCustomError(guardianValidator, "GuardianNotFound");
    });

    it("works to remove existing guardian.", async function () {
      const tx = await sut(await guardian.getAddress());

      expect(tx).to.emit(guardianValidator, "GuardianRemoved");
      const guardians = await guardianValidator.guardiansFor(hashedOriginDomain, user1.getAddress());
      expect(guardians.length).to.equal(0);
      const guardedAccounts = await guardianValidator.guardianOf(hashedOriginDomain, guardian.getAddress());
      expect(guardedAccounts.length).to.equal(0);
    });
  });

  describe("onUninstall", () => {
    let user1: ethers.Signer;
    let guardian: ethers.Signer;
    let guardian2: ethers.Signer;
    cacheBeforeEach(async () => {
      const [guardianWallet, guardianConnected] = await randomWallet();
      const [guardian2Wallet, guardian2Connected] = await randomWallet();
      guardian = guardianWallet;
      guardian2 = guardian2Wallet;
      const [user1Wallet, user1Connected] = await randomWallet();
      user1 = user1Wallet;
      await user1Connected.proposeValidationKey(hashedOriginDomain, guardian.getAddress());
      await user1Connected.proposeValidationKey(hashedOriginDomain, guardian2.getAddress());
      await guardianConnected.addValidationKey(hashedOriginDomain, user1.getAddress());
      await guardian2Connected.addValidationKey(hashedOriginDomain, user1.getAddress());
    });

    const sut = async () => {
      return guardianValidator.connect(user1).onUninstall(ethers.AbiCoder.defaultAbiCoder().encode(["bytes32[]"], [[hashedOriginDomain]]));
    };

    it("Removes existing guardians.", async function () {
      const tx = await sut();

      const res = await guardianValidator.guardiansFor(hashedOriginDomain, user1.getAddress());
      expect(res.length).to.equal(0);
      expect(tx).to.emit(guardianValidator, "GuardianRemoved");

      const guardian1GuardedAccounts = await guardianValidator.guardianOf(hashedOriginDomain, user1.getAddress());
      expect(guardian1GuardedAccounts.length).to.equal(0);
      const guardian2GuardedAccounts = await guardianValidator.guardianOf(hashedOriginDomain, user1.getAddress());
      expect(guardian2GuardedAccounts.length).to.equal(0);
    });
  });

  describe("When attached to SsoAccount", () => {
    describe("When initiating new guardian addition operation", () => {
      it("it adds guardian as non ready one.", async function () {
        const [newGuardianWallet] = await randomWallet();
        const functionData = guardianValidator.interface.encodeFunctionData(
          "proposeValidationKey",
          [hashedOriginDomain, newGuardianWallet.address],
        );
        const txToSign = {
          ...(await aaTxTemplate(await ssoAccountInstance.getAddress(), provider)),
          type: 1,
          to: guardiansValidatorAddr,
          data: functionData,
        };
        txToSign.gasLimit = await provider.estimateGas(txToSign);
        const txData = await ownerConnectedSsoAccount.signTransaction(txToSign);
        const tx = await provider.broadcastTransaction(txData);
        await tx.wait();

        const [newGuardian] = (await guardianValidator.guardiansFor(hashedOriginDomain, newGuardianConnectedSsoAccount.address)).slice(-1);
        expect(newGuardian.addr).to.eq(newGuardianWallet.address);
        expect(newGuardian.isReady).to.eq(false);
      });
    });
    describe("When approving existing guardian addition operation", () => {
      cacheBeforeEach(async () => {
        const functionData = guardianValidator.interface.encodeFunctionData(
          "proposeValidationKey",
          [hashedOriginDomain, guardianWallet.address],
        );
        const txToSign = {
          ...(await aaTxTemplate(await ssoAccountInstance.getAddress(), provider)),
          to: guardiansValidatorAddr,
          data: functionData,
        };
        txToSign.gasLimit = await provider.estimateGas(txToSign);
        const txData = await ownerConnectedSsoAccount.signTransaction(txToSign);
        const tx = await provider.broadcastTransaction(txData);
        await tx.wait();
      });
      const sut = async () => {
        return guardianValidator.connect(guardianWallet)
          .addValidationKey(hashedOriginDomain, newGuardianConnectedSsoAccount.address);
      };
      it("it makes guardian active one.", async function () {
        await sut();

        const [newGuardian] = (await guardianValidator.guardiansFor(hashedOriginDomain, newGuardianConnectedSsoAccount.address)).slice(-1);
        expect(newGuardian.addr).to.eq(guardianWallet.address);
        expect(newGuardian.isReady).to.eq(true);
      });
    });
    describe("When having active guardian", () => {
      cacheBeforeEach(async () => {
        const functionData = guardianValidator.interface.encodeFunctionData(
          "proposeValidationKey",
          [hashedOriginDomain, guardianWallet.address],
        );
        const txToSign = {
          ...(await aaTxTemplate(await ssoAccountInstance.getAddress(), provider)),
          to: guardiansValidatorAddr,
          data: functionData,
        };
        txToSign.gasLimit = await provider.estimateGas(txToSign);
        const txData = await ownerConnectedSsoAccount.signTransaction(txToSign);
        const tx = await provider.broadcastTransaction(txData);
        await tx.wait();
        await guardianValidator.connect(guardianWallet).addValidationKey(hashedOriginDomain, newGuardianConnectedSsoAccount.address);
      });

      describe("And initiating recovery process", () => {
        let newKeyArgs: Awaited<ReturnType<typeof generatePassKey>>["args"];
        let hashDomain: Awaited<ReturnType<typeof generatePassKey>>["hashedOriginDomain"];
        let refTimestamp: number;
        let accountId: `0x${string}`;

        cacheBeforeEach(async () => {
          accountId = `0x${Buffer.from(ethers.toUtf8Bytes(`id-${randomBytes(32).toString()}`)).toString("hex")}`;
          const key = await generatePassKey(accountId, keyDomain);
          newKeyArgs = key.args;
          hashDomain = key.hashedOriginDomain;
          refTimestamp = (await provider.getBlock("latest")).timestamp;
        });
        const sut = async (signer: ethers.Signer = guardianWallet) => {
          const tx = await guardianValidator.connect(signer).initRecovery(
            ssoAccountInstance.getAddress(), ethers.keccak256(accountId), newKeyArgs[1], hashDomain,
          );
          return tx;
        };
        it("it creates new recovery process.", async function () {
          await sut();

          const pendingRecoveryData = (await guardianValidator.getPendingRecoveryData(
            hashDomain,
            newGuardianConnectedSsoAccount.address,
          ));
          expect(pendingRecoveryData.rawPublicKey[0]).to.eq(toHex(newKeyArgs[1][0]));
          expect(pendingRecoveryData.rawPublicKey[1]).to.eq(toHex(newKeyArgs[1][1]));
          expect(Math.abs(Number(pendingRecoveryData.timestamp) - refTimestamp)).to.lt(10);
        });
        it("it prohibits non guardian from starting recovery process", async function () {
          await expect(sut(externalUserWallet)).to.be.reverted;
        });
      });

      describe("And has active recovery process and trying to execute", () => {
        let newKeyArgs: Awaited<ReturnType<typeof generatePassKey>>["args"];
        let accountId: `0x${string}`;

        cacheBeforeEach(async () => {
          accountId = `0x${Buffer.from(ethers.toUtf8Bytes(`id-${randomBytes(32).toString()}`)).toString("hex")}`;
          const key = await generatePassKey(accountId, keyDomain);
          newKeyArgs = key.args;

          const hashDomain = key.hashedOriginDomain;
          const hashedAccountId = ethers.keccak256(newKeyArgs[0]);

          await guardianValidator.connect(guardianWallet)
            .initRecovery(newGuardianConnectedSsoAccount.address, hashedAccountId, newKeyArgs[1], hashDomain);
        });
        const sut = async (keyToAddArgs: Awaited<ReturnType<typeof generatePassKey>>["args"], ssoAccount: SmartAccount = newGuardianConnectedSsoAccount) => {
          const functionData = webauthn.interface.encodeFunctionData(
            "addValidationKey",
            [...keyToAddArgs],
          );
          const txToSign = {
            ...(await aaTxTemplate(await ssoAccountInstance.getAddress(), provider)),
            to: await webauthn.getAddress(),
            data: functionData,
          };
          txToSign.gasLimit = await provider.estimateGas(txToSign);
          return await ssoAccount.sendTransaction(txToSign);
        };
        describe("but not enough time has passed", () => {
          it("it should not accept transaction.", async function () {
            await helpers.time.increase(12 * 60 * 60);
            await expect(sut(newKeyArgs)).to.be.reverted;
          });
        });
        describe("but passing wrong new key", () => {
          it("it should revert.", async function () {
            const wrongKey = await generatePassKey(accountId, keyDomain);
            await helpers.time.increase(1 * 24 * 60 * 60 + 60);
            const transactionResponsePromise = sut(wrongKey.args);
            await expect(transactionResponsePromise).to.be.reverted;
          });
        });
        describe("and passing correct new key", () => {
          it("it should clean up pending request.", async function () {
            await helpers.time.increase(2 * 24 * 60 * 60);
            await sut(newKeyArgs);

            const pendingRecoveryData = (await guardianValidator.getPendingRecoveryData(
              hashedOriginDomain,
              newGuardianConnectedSsoAccount.address,
            ));
            expect(pendingRecoveryData.rawPublicKey[0]).to.eq("0x0000000000000000000000000000000000000000000000000000000000000000");
            expect(pendingRecoveryData.rawPublicKey[1]).to.eq("0x0000000000000000000000000000000000000000000000000000000000000000");
            expect(pendingRecoveryData.timestamp).to.eq(0);
          });
        });
      });
    });
  });
});

export async function generatePassKey(accountId: `0x${string}`, keyDomain: string) {
  const hashedOriginDomain = keccak256(toHex(keyDomain)) as `0x${string}`;
  const generatedR1Key = await generateES256R1Key();
  const [generatedX, generatedY] = await getRawPublicKeyFromCrpyto(generatedR1Key);
  const generatedKey = encodeKeyFromBytes(accountId, [generatedX, generatedY], keyDomain);
  return {
    generatedKey,
    hashedOriginDomain,
    args: [accountId, [generatedX, generatedY], keyDomain] as [`0x${string}`, [Uint8Array, Uint8Array], string],
  };
}

async function aaTxTemplate(proxyAccountAddress: string, provider: Provider) {
  return {
    type: 113,
    from: proxyAccountAddress,
    data: "0x",
    value: 0,
    chainId: (await provider.getNetwork()).chainId,
    nonce: await provider.getTransactionCount(proxyAccountAddress),
    gasPrice: await provider.getGasPrice(),
    customData: {
      gasPerPubdata: utils.DEFAULT_GAS_PER_PUBDATA_LIMIT,
      customSignature: undefined,
    },
    gasLimit: 0n,
  };
}
