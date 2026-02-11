// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {OFTUpgradeable} from "@layerzerolabs/oft-evm-upgradeable/contracts/oft/OFTUpgradeable.sol";

/**
 * @title AssetOFT
 * @notice ERC20 representation of the vault's asset token on a spoke chain for cross-chain functionality
 * @dev This contract represents the vault's underlying asset on spoke chains. It inherits from
 * LayerZero's OFT (Omnichain Fungible Token) to enable seamless cross-chain transfers of the
 * vault's asset tokens between the hub chain and spoke chains.
 *
 * The asset OFT acts as a bridgeable ERC20 representation of the vault's collateral asset, allowing
 * users to move their assets across supported chains while maintaining fungibility.
 */
contract AssetOFT is OFTUpgradeable {
    /**
     * @notice Constructs the Asset OFT contract
     * @dev Initializes the OFT with LayerZero endpoint and sets up ownership
     * @param _lzEndpoint The address of the LayerZero endpoint on this chain
     */
    constructor(address _lzEndpoint) OFTUpgradeable(_lzEndpoint) {
        require(_lzEndpoint != address(0), "AssetOFT: zero address");
        _disableInitializers();
        // NOTE: Uncomment the line below if you need to mint initial supply
        // This can be useful for testing or if the asset needs initial liquidity
        // _mint(msg.sender, 1000000 ether);
    }

    /**
     * @notice Initialize the AssetOFT contract
     * @dev Ownership is granted to deployer
     * @param _name Token name
     * @param _symbol Token symbol
     * @param _deployer Deployer address (receives ownership)
     */
    function initialize(string memory _name, string memory _symbol, address _deployer) public initializer {
        require(_deployer != address(0), "AssetOFT: zero deployer");
        require(bytes(_name).length > 0, "AssetOFT: name is empty");
        require(bytes(_symbol).length > 0, "AssetOFT: symbol is empty");
        __OFT_init(_name, _symbol, _deployer);
        _transferOwnership(_deployer);
    }
}
