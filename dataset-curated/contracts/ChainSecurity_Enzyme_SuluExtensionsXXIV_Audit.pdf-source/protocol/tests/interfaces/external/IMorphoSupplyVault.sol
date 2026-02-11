// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.6.0 <0.9.0;

import {IMorphoMorpho} from "./IMorphoMorpho.sol";

interface IMorphoSupplyVault {
    function morpho() external view returns (IMorphoMorpho morpho_);

    function poolToken() external view returns (address poolToken_);
}
