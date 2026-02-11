// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../burner/AVAXBurner.sol";
import {ILBRouter} from "../burner/interfaces/ILBRouter.sol";

contract MaliciousTokenReentrancyAvax is ERC20 {
    Burner public burner;
    
    constructor(address _burner) ERC20("MaliciousToken", "MAL") {
        burner = Burner(payable(_burner));
        _mint(msg.sender, 1000000 * 10**18);
    }


    function transferFrom(address sender, address recipient, uint256 amount) public virtual override returns (bool) {
        // Attempt reentrancy attack when tokens are transferred from sender to incinerator
        if (recipient == address(burner)) {
            Burner.SwapParams memory params = Burner.SwapParams({
                tokenIn: address(this),
                amountIn: amount,
                amountOutMinimum: 0,
                path: ILBRouter.Path({
                    pairBinSteps: new uint256[](0),
                    versions: new ILBRouter.Version[](0),
                    tokenPath: new IERC20[](0)
                })
            });
            Burner.SwapParams[] memory paramsArray = new Burner.SwapParams[](1);
            paramsArray[0] = params;
            burner.swapExactInputMultiple(paramsArray, msg.sender, false, bytes(""), address(0));
        }
        return super.transferFrom(sender, recipient, amount);
    }


    function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
        // Attempt reentrancy attack when tokens are transferred to recipient
        if (recipient == address(burner)) {
            burner.rescueTokens(address(this), msg.sender, amount);
        }
        return super.transfer(recipient, amount);

    }
}