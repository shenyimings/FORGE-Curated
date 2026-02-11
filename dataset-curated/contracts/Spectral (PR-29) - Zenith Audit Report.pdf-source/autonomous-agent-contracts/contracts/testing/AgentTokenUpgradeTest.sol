// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "../interfaces/IAgentBalances.sol";
import "../interfaces/IAutonomousAgentDeployer.sol";

contract AgentTokenUpgradeTest is Initializable, ERC20Upgradeable, UUPSUpgradeable {
    using AddressUpgradeable for address;

    uint256 public taxPercentage;
    address public taxWallet;
    address public owner;
    IAgentBalances public agentBalances;

    uint8 version;
    // Some agents are already deployed and need upgrading using diamond pattern
    // IAutonomousAgentDeployer constant public deployer = IAutonomousAgentDeployer(address(0x977FDaA235D15346bFf4e3b3e457887DFf1bdcf3));
    // use this if testing or deploying new deployer
    IAutonomousAgentDeployer public deployer;

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
        deployer = IAutonomousAgentDeployer(msg.sender);
        _mint(msg.sender, initialSupply);
        version = 1;
    }


    // Override the transfer function to apply tax only if the recipient is a contract
    function transfer(address recipient, uint256 amount) public override returns (bool) {
        // Check if the recipient is agentBalances to prevent recursion
        if (recipient == address(agentBalances)) {
            return super.transfer(recipient, amount);
        }
        address distributor = address(deployer.distributor());
        if (address(deployer) != address(0) &&                               // deployer exists
        (recipient.isContract() || msg.sender.isContract()) &&                   // XOR: exactly one must be a contract
        !(recipient == address(deployer) || msg.sender == address(deployer)) &&  // neither sender nor recipient is deployer
        (distributor == address(0) || recipient != distributor))
        {
            uint256 taxAmount = (amount * taxPercentage) / 10000;
            uint256 amountAfterTax = amount - taxAmount;

            //send the tax to deployer to distribute
            super.transfer(address(deployer), taxAmount);
            deployer.accumulateSwapFees(taxAmount);

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

        address distributor = address(deployer.distributor());

        if (address(deployer) != address(0) &&                               // deployer exists
        (recipient.isContract() || sender.isContract()) &&                   // XOR: exactly one must be a contract
        !(recipient == address(deployer) || sender == address(deployer)) &&  // neither sender nor recipient is deployer
        (distributor == address(0) || recipient != distributor))
        {
            uint256 taxAmount = (amount * taxPercentage) / 10000;
            uint256 amountAfterTax = amount - taxAmount;

            //send the tax to deployer to distribute
            super.transferFrom(sender, address(deployer), taxAmount);
            deployer.accumulateSwapFees(taxAmount);

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

    // Times the percentage by 100 to allow for more decimal places
    function setTaxPercentage(uint256 _taxPercentage) external {
        require(_taxPercentage >= 100, "Tax percentage too small");
        require(_taxPercentage <= 10000, "Tax percentage cannot exceed 100%");
        require(msg.sender == owner, "Only the owner can set the tax percentage");
        taxPercentage = _taxPercentage;
        emit TaxChanged(_taxPercentage);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyUpgrader {
        require(newImplementation != address(0), "ADDRESS_IS_ZERO");
        ++version;
    }

    function removeAllowance(address approver, address spender) public onlyUpgrader {
        _approve(approver, spender, 0);
    }
}