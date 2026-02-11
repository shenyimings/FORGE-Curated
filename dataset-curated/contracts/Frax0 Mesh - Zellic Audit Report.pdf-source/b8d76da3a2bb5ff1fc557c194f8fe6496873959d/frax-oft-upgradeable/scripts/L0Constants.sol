// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

/// @dev: required to be alphabetical to conform to https://book.getfoundry.sh/cheatcodes/parse-json
struct L0Config {
    string RPC;
    uint256 chainid;
    address delegate;
    address dvnHorizen;
    address dvnL0;
    uint256 eid;
    address endpoint;
    address receiveLib302;
    address sendLib302;
}

contract L0Constants {

    address[] public expectedProxyOfts;
    address[] public lineaProxyOfts;
    address[] public baseProxyOfts;
    address[] public zkEraProxyOfts;
    address[] public fraxtalLockboxes;
    address[] public ethLockboxes;
    address[] public connectedOfts;
    address[] public ethLockboxesLegacy;

    // Semi Pre-deterministic upgradeable addresses 
    address public proxyFrxUsdOft = 0x80Eede496655FB9047dd39d9f418d5483ED600df;
    address public proxySFrxUsdOft = 0x5Bff88cA1442c2496f7E475E9e7786383Bc070c0;
    address public proxyFrxEthOft = 0x43eDD7f3831b08FE70B7555ddD373C8bF65a9050;
    address public proxySFrxEthOft = 0x3Ec3849C33291a9eF4c5dB86De593EB4A37fDe45;
    address public proxyFraxOft = 0x64445f0aecC51E94aD52d8AC56b7190e764E561a;
    address public proxyFpiOft = 0x90581eCa9469D8D7F5D3B60f4715027aDFCf7927;

    address public baseFrxUsdOft = 0xe5020A6d073a794B6E7f05678707dE47986Fb0b6;
    address public baseSFrxUsdOft = 0x91A3f8a8d7a881fBDfcfEcd7A2Dc92a46DCfa14e;
    address public baseFrxEthOft = 0x7eb8d1E4E2D0C8b9bEDA7a97b305cF49F3eeE8dA;
    address public baseSFrxEthOft = 0x192e0C7Cc9B263D93fa6d472De47bBefe1Fb12bA;
    address public baseFraxOft = 0x0CEAC003B0d2479BebeC9f4b2EBAd0a803759bbf;
    address public baseFpiOft = 0xEEdd3A0DDDF977462A97C1F0eBb89C3fbe8D084B;

    address public lineaFrxUsdOft = 0xC7346783f5e645aa998B106Ef9E7f499528673D8;
    address public lineaSFrxUsdOft = 0x592a48c0FB9c7f8BF1701cB0136b90DEa2A5B7B6;
    address public lineaFrxEthOft = 0xB1aFD04774c02AE84692619448B08BA79F19b1ff;
    address public lineaSFrxEthOft = 0x383Eac7CcaA89684b8277cBabC25BCa8b13B7Aa2;
    address public lineaFraxOft = 0x5217Ab28ECE654Aab2C68efedb6A22739df6C3D5;
    address public lineaFpiOft = 0xDaF72Aa849d3C4FAA8A9c8c99f240Cf33dA02fc4;

    address public zkEraFrxUsdOft = 0xEa77c590Bb36c43ef7139cE649cFBCFD6163170d;
    address public zkEraSFrxUsdOft = 0x9F87fbb47C33Cd0614E43500b9511018116F79eE;
    address public zkEraFrxEthOft = 0xc7Ab797019156b543B7a3fBF5A99ECDab9eb4440;
    address public zkEraSFrxEthOft = 0xFD78FD3667DeF2F1097Ed221ec503AE477155394;
    address public zkEraFraxOft = 0xAf01aE13Fb67AD2bb2D76f29A83961069a5F245F;
    address public zkEraFpiOft = 0x580F2ee1476eDF4B1760bd68f6AaBaD57dec420E;

    address public fraxtalFrxUsdLockbox = 0x96A394058E2b84A89bac9667B19661Ed003cF5D4;
    address public fraxtalSFrxUsdLockbox = 0x88Aa7854D3b2dAA5e37E7Ce73A1F39669623a361;
    address public fraxtalFrxEthLockbox = 0x9aBFE1F8a999B0011ecD6116649AEe8D575F5604;
    address public fraxtalSFrxEthLockbox = 0x999dfAbe3b1cc2EF66eB032Eea42FeA329bBa168;
    address public fraxtalFraxLockbox = 0xd86fBBd0c8715d2C1f40e451e5C3514e65E7576A;
    address public fraxtalFpiLockbox = 0x75c38D46001b0F8108c4136216bd2694982C20FC;

    address public ethFrxUsdLockbox = 0x566a6442A5A6e9895B9dCA97cC7879D632c6e4B0;
    address public ethSFrxUsdLockbox = 0x7311CEA93ccf5f4F7b789eE31eBA5D9B9290E126;
    address public ethFrxEthLockbox = 0x1c1649A38f4A3c5A0c4a24070f688C525AB7D6E6;
    address public ethSFrxEthLockbox = 0xbBc424e58ED38dd911309611ae2d7A23014Bd960;
    address public ethFraxOft = 0x04ACaF8D2865c0714F79da09645C13FD2888977f;
    address public ethFraxLockbox; // Deprecated
    address public ethFpiLockbox = 0x9033BAD7aA130a2466060A2dA71fAe2219781B4b;

    address public ethFrxUsdLockboxLegacy = 0x909DBdE1eBE906Af95660033e478D59EFe831fED;
    address public ethSFraxLockboxLegacy = 0xe4796cCB6bB5DE2290C417Ac337F2b66CA2E770E;
    address public ethFrxEthLockboxLegacy = 0xF010a7c8877043681D59AD125EbF575633505942;
    address public ethSFrxEthLockboxLegacy = 0x1f55a02A049033E3419a8E2975cF3F572F4e6E9A;
    address public ethFraxLockboxLegacy = 0x23432452B720C80553458496D4D9d7C5003280d0;
    address public ethFpiLockboxLegacy = 0x6Eca253b102D41B6B69AC815B9CC6bD47eF1979d;

    // testnet addresses
    address[] public ethSepoliaLockboxes;
    address[] public arbitrumSepoliaOfts;
    address[] public fraxtalTestnetLockboxes;

    address public ethSepoliaFrxUsdLockbox = 0x29a5134D3B22F47AD52e0A22A63247363e9F35c2;

    address public arbitrumSepoliaFrxUsdOft = 0x0768C16445B41137F98Ab68CA545C0afD65A7513;

    address public fraxtalTestnetFrxUsdLockbox = 0x7C9DF6704Ec6E18c5E656A2db542c23ab73CB24d;

    constructor() {
        // array of semi-pre-determined upgradeable OFTs
        /// @dev: this array maintains the same token order as proxyOfts
        expectedProxyOfts.push(proxyFraxOft);
        expectedProxyOfts.push(proxySFrxUsdOft);
        expectedProxyOfts.push(proxySFrxEthOft);
        expectedProxyOfts.push(proxyFrxUsdOft);
        expectedProxyOfts.push(proxyFrxEthOft);
        expectedProxyOfts.push(proxyFpiOft);

        baseProxyOfts.push(baseFraxOft);
        baseProxyOfts.push(baseSFrxUsdOft);
        baseProxyOfts.push(baseSFrxEthOft);
        baseProxyOfts.push(baseFrxUsdOft);
        baseProxyOfts.push(baseFrxEthOft);
        baseProxyOfts.push(baseFpiOft);

        lineaProxyOfts.push(lineaFraxOft);
        lineaProxyOfts.push(lineaSFrxUsdOft);
        lineaProxyOfts.push(lineaSFrxEthOft);
        lineaProxyOfts.push(lineaFrxUsdOft);
        lineaProxyOfts.push(lineaFrxEthOft);
        lineaProxyOfts.push(lineaFpiOft);

         // array of base OFTs
        baseProxyOfts.push(baseFraxOft);
        baseProxyOfts.push(baseSFrxUsdOft);
        baseProxyOfts.push(baseSFrxEthOft);
        baseProxyOfts.push(baseFrxUsdOft);
        baseProxyOfts.push(baseFrxEthOft);
        baseProxyOfts.push(baseFpiOft);

        zkEraProxyOfts.push(zkEraFraxOft);
        zkEraProxyOfts.push(zkEraSFrxUsdOft);
        zkEraProxyOfts.push(zkEraSFrxEthOft);
        zkEraProxyOfts.push(zkEraFrxUsdOft);
        zkEraProxyOfts.push(zkEraFrxEthOft);
        zkEraProxyOfts.push(zkEraFpiOft);

        fraxtalLockboxes.push(fraxtalFraxLockbox);
        fraxtalLockboxes.push(fraxtalSFrxUsdLockbox);
        fraxtalLockboxes.push(fraxtalSFrxEthLockbox);
        fraxtalLockboxes.push(fraxtalFrxUsdLockbox);
        fraxtalLockboxes.push(fraxtalFrxEthLockbox);
        fraxtalLockboxes.push(fraxtalFpiLockbox);

        ethLockboxes.push(ethFraxOft);
        ethLockboxes.push(ethSFrxUsdLockbox);
        ethLockboxes.push(ethSFrxEthLockbox);
        ethLockboxes.push(ethFrxUsdLockbox);
        ethLockboxes.push(ethFrxEthLockbox);
        ethLockboxes.push(ethFpiLockbox);

        connectedOfts = new address[](expectedProxyOfts.length);

        ethLockboxesLegacy.push(ethFraxLockboxLegacy);
        ethLockboxesLegacy.push(ethSFraxLockboxLegacy);
        ethLockboxesLegacy.push(ethSFrxEthLockboxLegacy);
        ethLockboxesLegacy.push(ethFrxUsdLockboxLegacy);
        ethLockboxesLegacy.push(ethFrxEthLockboxLegacy);
        ethLockboxesLegacy.push(ethFpiLockboxLegacy);

        // testnet addresses
        ethSepoliaLockboxes.push(ethSepoliaFrxUsdLockbox);

        arbitrumSepoliaOfts.push(arbitrumSepoliaFrxUsdOft);

        fraxtalTestnetLockboxes.push(fraxtalTestnetFrxUsdLockbox);
    }
}