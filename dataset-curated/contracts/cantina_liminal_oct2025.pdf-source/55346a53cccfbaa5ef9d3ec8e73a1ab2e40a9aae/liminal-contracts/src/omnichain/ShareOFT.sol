// SPDX-License-Identifier: BUSL-1.1
// Terms: https://liminal.money/xtokens/license

pragma solidity 0.8.28;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {OFTUpgradeable} from "@layerzerolabs/oft-evm-upgradeable/contracts/oft/OFTUpgradeable.sol";

/**
 * @title ShareOFT
 * @notice ERC20 representation of the vault's share token on a spoke chain for cross-chain functionality
 * @dev This contract represents the vault's share tokens on spoke chains. It inherits from
 * LayerZero's OFT (Omnichain Fungible Token) to enable seamless cross-chain transfers of
 * vault shares between the hub chain and spoke chains. This contract is designed to work
 * with ERC4626-compliant vaults, enabling standardized cross-chain vault interactions.
 *
 * Share tokens represent ownership in the vault and can be redeemed for the underlying
 * asset on the hub chain. The OFT mechanism ensures that shares maintain their value and can be freely
 * moved across supported chains while preserving the vault's accounting integrity.
 */
contract ShareOFT is OFTUpgradeable {
    /**
     * @notice Constructs the Share OFT contract
     * @dev Initializes the OFT with LayerZero endpoint and sets up ownership
     * @param _lzEndpoint The address of the LayerZero endpoint on this chain
     */
    constructor(address _lzEndpoint) OFTUpgradeable(_lzEndpoint) {
        require(_lzEndpoint != address(0), "ShareOFT: zero address");
        _disableInitializers();
        // WARNING: Do NOT mint share tokens directly as this breaks the vault's share-to-asset ratio
        // Share tokens should only be minted by the vault contract during deposits to maintain
        // the correct relationship between shares and underlying assets
        // _mint(msg.sender, 1 ether); // ONLY uncomment for testing UI/integration, never in production
    }

    /**
     * @notice Initialize the ShareOFT contract
     * @dev Ownership is granted to deployer
     * @param _name Token name
     * @param _symbol Token symbol
     * @param _deployer Deployer address (receives ownership)
     */
    function initialize(string memory _name, string memory _symbol, address _deployer) public initializer {
        require(_deployer != address(0), "ShareOFT: zero deployer");
        require(bytes(_name).length > 0, "ShareOFT: name is empty");
        require(bytes(_symbol).length > 0, "ShareOFT: symbol is empty");

        __OFT_init(_name, _symbol, _deployer);
        _transferOwnership(_deployer);
    }
}
