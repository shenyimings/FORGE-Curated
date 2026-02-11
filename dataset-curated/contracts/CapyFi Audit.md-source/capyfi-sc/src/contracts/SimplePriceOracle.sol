// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.10;

import './PriceOracle.sol';
import './CErc20.sol';
import './Ownable.sol';

contract SimplePriceOracle is PriceOracle, Ownable {
    mapping(address => uint) prices;
    mapping(address => bool) public authorizedAddresses;

    event PricePosted(
        address asset,
        uint previousPriceMantissa,
        uint requestedPriceMantissa,
        uint newPriceMantissa
    );

    modifier onlyAuthorized() {
        require(
            msg.sender == owner() || authorizedAddresses[msg.sender],
            'Only the owner or an authorized address can call this function'
        );
        _;
    }

    function addAuthorizedAddress(address _addr) public onlyOwner {
        authorizedAddresses[_addr] = true;
    }

    function removeAuthorizedAddress(address _addr) public onlyOwner {
        authorizedAddresses[_addr] = false;
    }

    function _getUnderlyingAddress(CToken cToken) private view returns (address) {
        address asset;
        if (compareStrings(cToken.symbol(), 'caLAC') || compareStrings(cToken.symbol(), 'caETH')) {
            asset = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
        } else {
            asset = address(CErc20(address(cToken)).underlying());
        }
        return asset;
    }

    function getUnderlyingPrice(CToken cToken) public view override returns (uint) {
        return prices[_getUnderlyingAddress(cToken)];
    }

    function setUnderlyingPrice(CToken cToken, uint underlyingPriceMantissa) public onlyAuthorized {
        address asset = _getUnderlyingAddress(cToken);
        emit PricePosted(asset, prices[asset], underlyingPriceMantissa, underlyingPriceMantissa);
        prices[asset] = underlyingPriceMantissa;
    }

    function setDirectPrice(address asset, uint price) public onlyAuthorized {
        emit PricePosted(asset, prices[asset], price, price);
        prices[asset] = price;
    }

    // v1 price oracle interface for use as backing of proxy
    function assetPrices(address asset) external view returns (uint) {
        return prices[asset];
    }

    function compareStrings(string memory a, string memory b) internal pure returns (bool) {
        return (keccak256(abi.encodePacked((a))) == keccak256(abi.encodePacked((b))));
    }
}