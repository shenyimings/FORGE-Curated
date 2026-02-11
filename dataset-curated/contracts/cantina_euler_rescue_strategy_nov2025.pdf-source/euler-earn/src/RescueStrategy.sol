// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.26;

import {IERC20} from "openzeppelin-contracts/interfaces/IERC20.sol";
import {IERC4626} from "openzeppelin-contracts/interfaces/IERC4626.sol";
import {EVCUtil} from "ethereum-vault-connector/utils/EVCUtil.sol";
import {IEVC} from "ethereum-vault-connector/interfaces/IEthereumVaultConnector.sol";
import {IEulerEarn} from "./interfaces/IEulerEarn.sol";
import {SafeERC20Permit2Lib} from "./libraries/SafeERC20Permit2Lib.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {IBorrowing, IRiskManager} from "../lib/euler-vault-kit/src/EVault/IEVault.sol";

/* 
    Rescue procedure:
    - Euler installs a perspective in the earn factory which allows adding custom strategies
    - RescueStrategy contracts are deployed for each earn vault to rescue. 
      Immutable params:
        o Rescue EOA: is only allowed to call the rescue function directly or through a multisig (tx.origin is checked).
          It should be a throw-away EOA just for the purpose of rescue, because of tx.origin use.
        o funds receiver: will receive rescued assets and left over shares (see below)
        o earn vault: the strategy can only work with the specified vault. If another vault tries to enable it, it will revert on `submitCap`
    - Euler registers the strategies in the perspective
    - Curator installs the strategy with unlimited cap (submit/acceptCap)
    - Curator sets the new strategy as the only one in supply queue and moves it to the front of withdraw queue
        o at this stage the regular users can't deposit or withdraw from earn
    - Rescue EOA calls one of the `rescueX` funcitons (for Euler or Morpho flash loan sources), specifying the asset amount to flashloan
        o flash loan is used to create earn vault shares, it just passes through earn vault back to the rescue strategy where it is repaid
        o the shares are used to withdraw as much as possible from the underlying strategies to the funds receiver
        o remaining shares are returned to the funds receiver
        o the rescue function can be called multiple times
        o the rescue EOA can also withdraw shares at any time, as long as it is tx.origin 
          (so can also initiate withdrawal if funds receiver is a multisig)
*/

interface IFlashLoan {
    function flashLoan(uint256, bytes memory) external;
    function flashLoan(address, uint256, bytes memory) external;
}

contract RescueStrategy {
	address immutable public rescueAccount;
	address immutable public earnVault;
	IERC20 immutable internal _asset;
	address immutable public fundsReceiver;

	modifier onlyRescueAccount() {
		require(tx.origin == rescueAccount, "vault operations are paused");
		_;
	}

    modifier onlyAllowedEarnVault() {
        require(msg.sender == earnVault, "wrong vault");
        _;
    }

	constructor(address _rescueAccount, address _earnVault, address _fundsReceiver) {
		rescueAccount = _rescueAccount;
		earnVault = _earnVault;
        fundsReceiver = _fundsReceiver;
		_asset = IERC20(IEulerEarn(earnVault).asset());
		SafeERC20Permit2Lib.forceApproveMaxWithPermit2(
			_asset,
			rescueAccount,
			address(0)
		);
	}

    function asset() external view returns(address) {
        return address(_asset);
    }

    // will revert user deposits
	function maxDeposit(address) onlyAllowedEarnVault onlyRescueAccount external view returns (uint256) {
		return type(uint256).max;
	}

    // will revert user withdrawals
	function maxWithdraw(address) onlyAllowedEarnVault onlyRescueAccount external view returns (uint256) {
		return 0;
	}

	function previewRedeem(uint256) onlyAllowedEarnVault external view returns (uint256) {
		return 0;
	}

    // this reverts acceptCaps to prevent reusing the whitelisted strategy on other vaults
	function balanceOf(address) onlyAllowedEarnVault external view returns (uint256) {
		return 0;
	}

	function deposit(uint256 amount, address) onlyAllowedEarnVault onlyRescueAccount external returns (uint256) {
		SafeERC20Permit2Lib.safeTransferFromWithPermit2(
			_asset,
			msg.sender,
			address(this),
			amount, 
			IEulerEarn(earnVault).permit2Address()
		);

        return amount;
	}

    // alternative sources of flashloan
    function rescueEuler(uint256 loanAmount, address flashLoanVault) onlyRescueAccount external {
        bytes memory data = abi.encode(loanAmount, flashLoanVault);
		IFlashLoan(flashLoanVault).flashLoan(loanAmount, data);
	}

    // alternative sources of flashloan
    function rescueEulerBatch(uint256 loanAmount, address flashLoanVault) onlyRescueAccount external {
        address evc = EVCUtil(earnVault).EVC();

        SafeERC20.forceApprove(_asset, flashLoanVault, loanAmount);

        IEVC.BatchItem[] memory batchItems = new IEVC.BatchItem[](5);
        batchItems[0] = IEVC.BatchItem({
            targetContract: evc,
            onBehalfOfAccount: address(0),
            value: 0,
            data: abi.encodeCall(IEVC.enableController, (address(this), flashLoanVault))
        });
        batchItems[1] = IEVC.BatchItem({
            targetContract: flashLoanVault,
            onBehalfOfAccount: address(this),
            value: 0,
            data: abi.encodeCall(IBorrowing.borrow, (loanAmount, address(this)))
        });
        batchItems[2] = IEVC.BatchItem({
            targetContract: address(this),
            onBehalfOfAccount: address(this),
            value: 0,
            data: abi.encodeCall(this.onBatchLoan, (loanAmount))
        });
        batchItems[3] = IEVC.BatchItem({
            targetContract: flashLoanVault,
            onBehalfOfAccount: address(this),
            value: 0,
            data: abi.encodeCall(IBorrowing.repay, (loanAmount, address(this)))
        });
        batchItems[4] = IEVC.BatchItem({
            targetContract: flashLoanVault,
            onBehalfOfAccount: address(this),
            value: 0,
            data: abi.encodeCall(IRiskManager.disableController, ())
        });

        IEVC(evc).batch(batchItems);
	}

    // alternative sources of flashloan
    function rescueMorpho(uint256 loanAmount, address morpho) onlyRescueAccount external {
		IFlashLoan(morpho).flashLoan(address(_asset), loanAmount, "");
	}

	function onBatchLoan(uint256 loanAmount) external {
		_processFlashLoan(loanAmount);
	}

	function onFlashLoan(bytes memory data) external {
        (uint256 loanAmount, address flashLoanSource) = abi.decode(data, (uint256, address));

		_processFlashLoan(loanAmount);

        // repay the flashloan
		SafeERC20.safeTransfer(
			_asset,
			flashLoanSource,
			loanAmount
		);
	}

	function onMorphoFlashLoan(uint256 amount, bytes memory) external {
		_processFlashLoan(amount);

        SafeERC20.forceApprove(_asset, msg.sender, amount);
	}

    // The contract is not supposed to hold any value, but in case of any issues rescue account can exec arbitrary call
	function call(address target, bytes memory payload) onlyRescueAccount external {
		(bool success,) = target.call(payload);
		require(success, "call failed");
	}

	fallback() external {
		revert("vault operations are paused");
	}

    function _processFlashLoan(uint256 loanAmount) internal {
		SafeERC20Permit2Lib.forceApproveMaxWithPermit2(
			_asset,
			earnVault,
			address(0)
		);

		// deposit to earn, create shares. Assets will come back here if the strategy is first in supply queue
		IERC4626(earnVault).deposit(loanAmount, address(this));

        // withdraw as much as possible to the receiver
        IERC4626(earnVault).withdraw(IERC4626(earnVault).maxWithdraw(address(this)), fundsReceiver, address(this));

        // send the remaining shares to the receiver
        IERC4626(earnVault).transfer(fundsReceiver, IERC4626(earnVault).balanceOf(address(this)));
    }
}
