// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "../interfaces/IAgentBalances.sol";

contract AgentTokenUpgradeTest is Initializable, ERC20Upgradeable, UUPSUpgradeable {
    using AddressUpgradeable for address;

    uint256 public taxPercentage;
    address public taxWallet;
    address public owner;
    IAgentBalances public agentBalances;

    uint8 version;
    event TaxChanged(uint256 taxPercentage);
    event TaxWalletchanged(address taxWallet);

    modifier onlyUpgrader() {
        require(owner == msg.sender, "CALLER_NOT_UPGRADER");
        _;
    }

    function initialize(
        string memory name, 
        string memory symbol, 
        uint256 initialSupply, 
        address _owner,
        address _agentBalances
    ) public initializer {
        require(_owner != address(0), "Invalid owner");
        __ERC20_init(name, symbol);
        __UUPSUpgradeable_init(); //initialize the UUPSUpgradeable
        owner = _owner;
        taxWallet = _owner; // default tax wallet
        taxPercentage = 100;
        agentBalances = IAgentBalances(_agentBalances);
        _mint(msg.sender, initialSupply);
        version = 1;
    }


    // Override the transfer function to apply tax only if the recipient is a contract
    function transfer(address recipient, uint256 amount) public override returns (bool) {
        // Check if the recipient is agentBalances to prevent recursion
        if (recipient == address(agentBalances)) {
            return super.transfer(recipient, amount);
        }
        if (recipient.isContract()) {
            uint256 taxAmount = (amount * taxPercentage) / 10000;
            uint256 amountAfterTax = amount - taxAmount;

            // Send half the tax to the taxWallet
            super.transfer(taxWallet, taxAmount/2);

            approve(address(agentBalances), taxAmount/2);
            agentBalances.deposit(msg.sender, address(this), address(this), taxAmount/2);

            // Transfer the remaining amount to the recipient
            return super.transfer(recipient, amountAfterTax);
        } else {
            // No tax if recipient is not a contract
            return super.transfer(recipient, amount);
        }
    }

    // Override the transferFrom function to apply tax only if the recipient is a contract
    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        if(sender == address(this))
        {
            _transfer(sender, recipient, amount);
            return true;
        }
        // Check if the recipient is agentBalances to prevent recursion
        if (recipient == address(agentBalances)) {
            return super.transferFrom(sender, recipient, amount);
        }
        if (recipient.isContract()) {
            uint256 taxAmount = (amount * taxPercentage) / 10000;
            uint256 amountAfterTax = amount - taxAmount;

            // Send half the tax to the taxWallet
            super.transferFrom(sender, taxWallet, taxAmount/2);
            //send half the tax to this agent contract to send it to agent balances
            super.transferFrom(sender, address(this), taxAmount/2);
            // Send half the tax to the agent
            approve(address(agentBalances), type(uint256).max);
            agentBalances.deposit(address(this), address(this), address(this), taxAmount/2);

            // Transfer the remaining amount to the recipient
            return super.transferFrom(sender, recipient, amountAfterTax);
        } else {
            // No tax if recipient is not a contract
            return super.transferFrom(sender, recipient, amount);
        }
    }

    function setTaxWallet(address _taxWallet) external {
        require(msg.sender == owner, "Only the owner can set the tax wallet");
        require(_taxWallet != address(0), "Invalid tax wallet address");
        taxWallet = _taxWallet;

        emit TaxWalletchanged(_taxWallet);
    }

    /////////////////////////////////////////////
    // This is wrong for Upgrade Testing only
    function setTaxPercentage(uint256 _taxPercentage) external {
        taxPercentage = 123456789;
        emit TaxChanged(_taxPercentage);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyUpgrader {
        require(newImplementation != address(0), "ADDRESS_IS_ZERO");
        ++version;
    }
}