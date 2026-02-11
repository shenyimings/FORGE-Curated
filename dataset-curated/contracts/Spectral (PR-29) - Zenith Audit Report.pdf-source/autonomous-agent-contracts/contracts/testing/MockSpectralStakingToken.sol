// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../interfaces/ISpectralStaking.sol";

contract SpectralStakingToken is ERC20 {
    ISpectralStaking public stakingContract;

    constructor() ERC20("SpectralStakingToken", "SPECx") {
        stakingContract = ISpectralStaking(msg.sender);
    }

    modifier onlyStakingContract() {
        require(msg.sender == address(stakingContract), "Only staking contract");
        _;
    }

    function mint(address to, uint256 amount) external onlyStakingContract {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyStakingContract {
        _burn(from, amount);
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        address owner = _msgSender();
        // both addresses should be users saved in the mappings of the staking Contract
        // This needs to be called before the transfer
        if (owner != address(stakingContract) && to != address(stakingContract) && owner != address(0) && to != address(0))
        {
            // transferCalibration is a function in the staking contract that will update both users balances in the staking contract
            // to ensure continuity since balanceOf does not retain history
            stakingContract.transferCalibration(owner, to, amount);
        }
        _transfer(owner, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        address spender = _msgSender();
        _spendAllowance(from, spender, amount);
        // both addresses should be users saved in the mappings of the staking Contract
        // This needs to be called before the transfer
        if (from != address(stakingContract) && to != address(stakingContract) && from != address(0) && to != address(0))
        {
            // transferCalibration is a function in the staking contract that will update both users balances in the staking contract
            // to ensure continuity since balanceOf does not retain history
            stakingContract.transferCalibration(from, to, amount);
        }
        _transfer(from, to, amount);
        return true;
    }

    function balanceOf(address account) public override view returns (uint256) {
        return super.balanceOf(account);
    }
}