import { assert, expect } from "chai";
import { ethers, parseEther, randomBytes } from "ethers";
import { Wallet, ZeroAddress } from "ethers";
import { it } from "mocha";
import { SmartAccount, utils } from "zksync-ethers";

import type { SsoAccount, TestExecutionHook, TestValidationHook } from "../typechain-types";
import { SsoAccount__factory, TestExecutionHook__factory, TestValidationHook__factory } from "../typechain-types";
import { create2 } from "./utils";
import { ContractFixtures, getProvider } from "./utils";

const ssoAccountAbi = SsoAccount__factory.createInterface();

describe("Hook tests", function () {
  const fixtures = new ContractFixtures();
  const provider = getProvider();
  let proxyAccountAddress: string;
  let ssoAccount: SsoAccount;
  let executionHook: TestExecutionHook;
  let validationHook: TestValidationHook;
  const abi = new ethers.AbiCoder();
  let smartAccount: SmartAccount;

  async function aaTxTemplate() {
    return {
      type: 113,
      from: proxyAccountAddress,
      data: "0x",
      value: 0,
      chainId: (await provider.getNetwork()).chainId,
      nonce: await provider.getTransactionCount(proxyAccountAddress),
      gasPrice: await provider.getGasPrice(),
      customData: { gasPerPubdata: utils.DEFAULT_GAS_PER_PUBDATA_LIMIT },
      gasLimit: 500_000n,
    };
  }

  it("should deploy proxy account and hooks", async () => {
    const accountImplContract = await fixtures.getAccountImplContract();
    assert(accountImplContract != null, "No account impl deployed");
    const aaFactoryContract = await fixtures.getAaFactory();

    const randomSalt = randomBytes(32);
    const deployTx = await aaFactoryContract.deployProxySsoAccount(
      randomSalt,
      [],
      [fixtures.wallet.address],
    );
    const deployTxReceipt = await deployTx.wait();
    proxyAccountAddress = deployTxReceipt!.contractAddress!;
    ssoAccount = SsoAccount__factory.connect(proxyAccountAddress, fixtures.wallet);
    smartAccount = new SmartAccount({
      address: proxyAccountAddress,
      secret: fixtures.wallet.privateKey,
    }, provider);

    const validationHookContract = await create2("TestValidationHook", fixtures.wallet, randomSalt);
    validationHook = TestValidationHook__factory.connect(await validationHookContract.getAddress(), fixtures.wallet);

    const executionHookContract = await create2("TestExecutionHook", fixtures.wallet, randomSalt);
    executionHook = TestExecutionHook__factory.connect(await executionHookContract.getAddress(), fixtures.wallet);

    const fundTx = await fixtures.wallet.sendTransaction({ value: parseEther("0.2"), to: proxyAccountAddress });
    await fundTx.wait();
  });

  describe("Validation hook tests", function () {
    it("should revert on install", async () => {
      const aaTx = {
        ...await aaTxTemplate(),
        to: proxyAccountAddress,
        data: ssoAccountAbi.encodeFunctionData("addHook", [await validationHook.getAddress(), true, abi.encode(["bool"], [true])]),
      };

      const signedTx = await smartAccount.signTransaction(aaTx);
      await expect(provider.broadcastTransaction(signedTx)).to.be.reverted;
    });

    it("should install hook", async () => {
      const aaTx = {
        ...await aaTxTemplate(),
        to: proxyAccountAddress,
        data: ssoAccountAbi.encodeFunctionData("addHook", [await validationHook.getAddress(), true, abi.encode(["bool"], [false])]),
      };

      const signedTx = await smartAccount.signTransaction(aaTx);
      await expect(provider.broadcastTransaction(signedTx))
        .to.emit(validationHook, "ValidationHookInstalled")
        .and.to.emit(ssoAccount, "HookAdded");
      expect(await ssoAccount.isHook(await validationHook.getAddress())).to.be.true;
    });

    it("should fail installing existing hook", async () => {
      const aaTx = {
        ...await aaTxTemplate(),
        to: proxyAccountAddress,
        data: ssoAccountAbi.encodeFunctionData("addHook", [await validationHook.getAddress(), true, abi.encode(["bool"], [false])]),
      };

      const signedTx = await smartAccount.signTransaction(aaTx);
      await expect(provider.broadcastTransaction(signedTx)).to.be.reverted;
    });

    it("should revert while sending a transaction", async () => {
      const aaTx = {
        ...await aaTxTemplate(),
        to: Wallet.createRandom().address,
      };

      const signedTx = await smartAccount.signTransaction(aaTx);
      await expect(provider.broadcastTransaction(signedTx)).to.be.reverted;
    });

    it("should send transaction and emit event", async () => {
      const aaTx = {
        ...await aaTxTemplate(),
        to: Wallet.createRandom().address,
        data: "0x1234",
      };

      const signedTx = await smartAccount.signTransaction(aaTx);
      const tx = await provider.broadcastTransaction(signedTx);
      await expect(tx).to.emit(validationHook, "ValidationHookTriggered");
      expect(await validationHook.lastTarget(proxyAccountAddress)).to.equal(tx.to);
    });

    it("should revert on uninstall", async () => {
      const aaTx = {
        ...await aaTxTemplate(),
        to: proxyAccountAddress,
        data: ssoAccountAbi.encodeFunctionData("removeHook", [await validationHook.getAddress(), true, abi.encode(["bool"], [true])]),
      };

      const signedTx = await smartAccount.signTransaction(aaTx);
      await expect(provider.broadcastTransaction(signedTx)).to.be.reverted;
    });

    it("should uninstall hook", async () => {
      const aaTx = {
        ...await aaTxTemplate(),
        to: proxyAccountAddress,
        data: ssoAccountAbi.encodeFunctionData("removeHook", [await validationHook.getAddress(), true, abi.encode(["bool"], [false])]),
      };

      const signedTx = await smartAccount.signTransaction(aaTx);
      await expect(provider.broadcastTransaction(signedTx))
        .to.emit(validationHook, "ValidationHookUninstalled")
        .and.to.emit(ssoAccount, "HookRemoved");
      expect(await ssoAccount.isHook(await validationHook.getAddress())).to.be.false;
    });

    it("should fail uninstalling already uninstalled hook", async () => {
      const aaTx = {
        ...await aaTxTemplate(),
        to: proxyAccountAddress,
        data: ssoAccountAbi.encodeFunctionData("removeHook", [await validationHook.getAddress(), true, abi.encode(["bool"], [false])]),
      };

      const signedTx = await smartAccount.signTransaction(aaTx);
      await expect(provider.broadcastTransaction(signedTx)).to.be.reverted;
    });
  });

  describe("Execution hook tests", function () {
    it("should revert on install", async () => {
      const aaTx = {
        ...await aaTxTemplate(),
        to: proxyAccountAddress,
        data: ssoAccountAbi.encodeFunctionData("addHook", [await executionHook.getAddress(), false, abi.encode(["bool"], [true])]),
      };

      const signedTx = await smartAccount.signTransaction(aaTx);
      await expect(provider.broadcastTransaction(signedTx)).to.be.reverted;
    });

    it("should install hook", async () => {
      const aaTx = {
        ...await aaTxTemplate(),
        to: proxyAccountAddress,
        data: ssoAccountAbi.encodeFunctionData("addHook", [await executionHook.getAddress(), false, abi.encode(["bool"], [false])]),
      };

      const signedTx = await smartAccount.signTransaction(aaTx);
      await expect(provider.broadcastTransaction(signedTx))
        .to.emit(executionHook, "ExecutionHookInstalled")
        .and.to.emit(ssoAccount, "HookAdded");
      expect(await ssoAccount.isHook(await executionHook.getAddress())).to.be.true;
    });

    it("should revert while sending a transaction", async () => {
      // pre execution reverts
      let aaTx = {
        ...await aaTxTemplate(),
        to: ZeroAddress,
      };

      let signedTx = await smartAccount.signTransaction(aaTx);
      await expect(provider.broadcastTransaction(signedTx)).to.be.reverted;

      // post execution reverts
      aaTx = {
        ...await aaTxTemplate(),
        to: proxyAccountAddress,
      };

      signedTx = await smartAccount.signTransaction(aaTx);
      await expect(provider.broadcastTransaction(signedTx)).to.be.reverted;
    });

    it("should send transaction and emit event", async () => {
      const aaTx = {
        ...await aaTxTemplate(),
        to: Wallet.createRandom().address,
      };

      const signedTx = await smartAccount.signTransaction(aaTx);
      const tx = await provider.broadcastTransaction(signedTx);
      await expect(tx)
        .to.emit(executionHook, "PreExecution")
        .and.to.emit(executionHook, "PostExecution");
      expect(await executionHook.lastTarget(proxyAccountAddress)).to.equal(tx.to);
    });

    it("should revert on uninstall", async () => {
      const aaTx = {
        ...await aaTxTemplate(),
        to: proxyAccountAddress,
        data: ssoAccountAbi.encodeFunctionData("removeHook", [await executionHook.getAddress(), false, abi.encode(["bool"], [true])]),
      };

      const signedTx = await smartAccount.signTransaction(aaTx);
      await expect(provider.broadcastTransaction(signedTx)).to.be.reverted;
    });

    it("should unlink hook", async () => {
      const aaTx = {
        ...await aaTxTemplate(),
        to: proxyAccountAddress,
        data: ssoAccountAbi.encodeFunctionData("unlinkHook", [await executionHook.getAddress(), false, abi.encode(["bool"], [false])]),
      };

      const signedTx = await smartAccount.signTransaction(aaTx);
      await expect(provider.broadcastTransaction(signedTx))
        .and.to.emit(ssoAccount, "HookRemoved");
      expect(await ssoAccount.isHook(await executionHook.getAddress())).to.be.false;
    });

    it("should fail unlinking already unlinked hook", async () => {
      const aaTx = {
        ...await aaTxTemplate(),
        to: proxyAccountAddress,
        data: ssoAccountAbi.encodeFunctionData("unlinkHook", [await executionHook.getAddress(), false, abi.encode(["bool"], [false])]),
      };

      const signedTx = await smartAccount.signTransaction(aaTx);
      await expect(provider.broadcastTransaction(signedTx)).to.be.reverted;
    });
  });
});
