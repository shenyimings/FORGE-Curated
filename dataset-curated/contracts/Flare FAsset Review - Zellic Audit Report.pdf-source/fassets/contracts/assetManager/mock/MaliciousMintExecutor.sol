// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IAssetManager} from "../../userInterfaces/IAssetManager.sol";
import {IFAsset} from "../../userInterfaces/IFAsset.sol";
import {IPayment} from "@flarenetwork/flare-periphery-contracts/flare/IFdcVerification.sol";



contract MaliciousMintExecutor {

    address immutable public diamond;
    address immutable public agentVault;
    address immutable public minter;
    address immutable public fasset;
    uint256 public liquidationStartedTs;
    uint256 public reserved;
    uint256 public minted;

    uint256 public poolCR;
    uint256 public vaultCR;


    constructor(address _diamond, address _agentVault, address _minter, address _fasset){
        diamond = _diamond;
        agentVault = _agentVault;
        minter = _minter;
        fasset = _fasset;
    }

    function mint(IPayment.Proof calldata _proof, uint256 _collateralReservationId) external{
        IAssetManager(diamond).executeMinting(_proof, _collateralReservationId);
    }


    fallback() external payable{
        proceed();
    }

    function proceed() internal{
        // store minted and reserved when executor is called
        minted = IAssetManager(diamond).getAgentInfo(agentVault).mintedUBA;
        reserved = IAssetManager(diamond).getAgentInfo(agentVault).reservedUBA;

        // store CR of agent when executor is called
        poolCR = IAssetManager(diamond).getAgentInfo(agentVault).poolCollateralRatioBIPS;
        vaultCR = IAssetManager(diamond).getAgentInfo(agentVault).vaultCollateralRatioBIPS;

        IFAsset(fasset).transferFrom(minter, address(this), IFAsset(fasset).balanceOf(minter));
        liquidationStartedTs = IAssetManager(diamond).startLiquidation(agentVault);
        IAssetManager(diamond).liquidate(agentVault, IFAsset(fasset).balanceOf(address(this)));
    }
}