// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {SafePct} from "../../utils/library/SafePct.sol";
import {AssetManagerState} from "./data/AssetManagerState.sol";
import {IAssetManagerEvents} from "../../userInterfaces/IAssetManagerEvents.sol";
import {CollateralType} from "../../userInterfaces/data/CollateralType.sol";
import {CollateralTypeInt} from "./data/CollateralTypeInt.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Conversion} from "./Conversion.sol";


library CollateralTypes {
    using SafeCast for uint256;

    error InvalidCollateralRatios();
    error CannotAddDeprecatedToken();
    error TokenAlreadyExists();
    error TokenZero();
    error PriceNotInitialized();
    error UnknownToken();
    error NotAVaultCollateral();
    error NotAPoolCollateralAtZero();
    error AtLeastTwoCollateralsRequired();

    function initialize(
        CollateralType.Data[] memory _data
    )
        internal
    {
        require(_data.length >= 2, AtLeastTwoCollateralsRequired());
        // initial pool collateral token
        require(_data[0].collateralClass == CollateralType.Class.POOL, NotAPoolCollateralAtZero());
        _add(_data[0]);
        _setPoolCollateralTypeIndex(0);
        // initial vault collateral tokens
        for (uint256 i = 1; i < _data.length; i++) {
            require(_data[i].collateralClass == CollateralType.Class.VAULT, NotAVaultCollateral());
            _add(_data[i]);
        }
    }

    function add(
        CollateralType.Data memory _data
    )
        internal
    {
        require(_data.collateralClass == CollateralType.Class.VAULT, NotAVaultCollateral());
        _add(_data);
    }

    function setPoolWNatCollateralType(
        CollateralType.Data memory _data
    )
        internal
    {
        uint256 index = _add(_data);
        _setPoolCollateralTypeIndex(index);
    }

    function getInfo(
        CollateralType.Class _collateralClass,
        IERC20 _token
    )
        internal view
        returns (CollateralType.Data memory)
    {
        CollateralTypeInt.Data storage token = CollateralTypes.get(_collateralClass, _token);
        return _getInfo(token);
    }

    function getAllInfos()
        internal view
        returns (CollateralType.Data[] memory _result)
    {
        AssetManagerState.State storage state = AssetManagerState.get();
        uint256 length = state.collateralTokens.length;
        _result = new CollateralType.Data[](length);
        for (uint256 i = 0; i < length; i++) {
            _result[i] = _getInfo(state.collateralTokens[i]);
        }
    }

    function get(
        CollateralType.Class _collateralClass,
        IERC20 _token
    )
        internal view
        returns (CollateralTypeInt.Data storage)
    {
        AssetManagerState.State storage state = AssetManagerState.get();
        uint256 index = state.collateralTokenIndex[_tokenKey(_collateralClass, _token)];
        require(index > 0, UnknownToken());
        return state.collateralTokens[index - 1];
    }

    function getIndex(
        CollateralType.Class _collateralClass,
        IERC20 _token
    )
        internal view
        returns (uint256)
    {
        AssetManagerState.State storage state = AssetManagerState.get();
        uint256 index = state.collateralTokenIndex[_tokenKey(_collateralClass, _token)];
        require(index > 0, UnknownToken());
        return index - 1;
    }

    function exists(
        CollateralType.Class _collateralClass,
        IERC20 _token
    )
        internal view
        returns (bool)
    {
        AssetManagerState.State storage state = AssetManagerState.get();
        uint256 index = state.collateralTokenIndex[_tokenKey(_collateralClass, _token)];
        return index > 0;
    }

    function _add(CollateralType.Data memory _data) private returns (uint256) {
        AssetManagerState.State storage state = AssetManagerState.get();
        // validation of collateralClass is done before call to _add
        require(address(_data.token) != address(0), TokenZero());
        bytes32 tokenKey = _tokenKey(_data.collateralClass, _data.token);
        require(state.collateralTokenIndex[tokenKey] == 0, TokenAlreadyExists());
        require(_data.validUntil == 0, CannotAddDeprecatedToken());
        // validate collateral ratios
        bool ratiosValid =
            SafePct.MAX_BIPS < _data.minCollateralRatioBIPS &&
            _data.minCollateralRatioBIPS <= _data.safetyMinCollateralRatioBIPS;
        require(ratiosValid, InvalidCollateralRatios());
        // check that prices are initialized in FTSO price reader
        (uint256 assetPrice,,) = Conversion.readFtsoPrice(_data.assetFtsoSymbol, false);
        require(assetPrice != 0, PriceNotInitialized());
        if (!_data.directPricePair) {
            (uint256 tokenPrice,,) = Conversion.readFtsoPrice(_data.tokenFtsoSymbol, false);
            require(tokenPrice != 0, PriceNotInitialized());
        }
        // add token
        uint256 newTokenIndex = state.collateralTokens.length;
        state.collateralTokens.push(CollateralTypeInt.Data({
            token: _data.token,
            collateralClass: _data.collateralClass,
            decimals: _data.decimals.toUint8(),
            __validUntil: 0, // no longer used
            directPricePair: _data.directPricePair,
            assetFtsoSymbol: _data.assetFtsoSymbol,
            tokenFtsoSymbol: _data.tokenFtsoSymbol,
            minCollateralRatioBIPS: _data.minCollateralRatioBIPS.toUint32(),
            __ccbMinCollateralRatioBIPS: 0, // no longer used
            safetyMinCollateralRatioBIPS: _data.safetyMinCollateralRatioBIPS.toUint32()
        }));
        state.collateralTokenIndex[tokenKey] = newTokenIndex + 1;   // 0 means empty
        emit IAssetManagerEvents.CollateralTypeAdded(uint8(_data.collateralClass), address(_data.token),
            _data.decimals, _data.directPricePair, _data.assetFtsoSymbol, _data.tokenFtsoSymbol,
            _data.minCollateralRatioBIPS, _data.safetyMinCollateralRatioBIPS);
        return newTokenIndex;
    }

    function _setPoolCollateralTypeIndex(uint256 _index) private {
        AssetManagerState.State storage state = AssetManagerState.get();
        CollateralTypeInt.Data storage token = state.collateralTokens[_index];
        assert(token.collateralClass == CollateralType.Class.POOL);
        state.poolCollateralIndex = _index.toUint16();
    }

    function _getInfo(CollateralTypeInt.Data storage token)
        private view
        returns (CollateralType.Data memory)
    {
        return CollateralType.Data({
            token: token.token,
            collateralClass: token.collateralClass,
            decimals: token.decimals,
            validUntil: token.__validUntil,
            directPricePair: token.directPricePair,
            assetFtsoSymbol: token.assetFtsoSymbol,
            tokenFtsoSymbol: token.tokenFtsoSymbol,
            minCollateralRatioBIPS: token.minCollateralRatioBIPS,
            safetyMinCollateralRatioBIPS: token.safetyMinCollateralRatioBIPS
        });
    }

    function _tokenKey(
        CollateralType.Class _collateralClass,
        IERC20 _token
    )
        private pure
        returns (bytes32)
    {
        return bytes32((uint256(_collateralClass) << 160) | uint256(uint160(address(_token))));
    }
}