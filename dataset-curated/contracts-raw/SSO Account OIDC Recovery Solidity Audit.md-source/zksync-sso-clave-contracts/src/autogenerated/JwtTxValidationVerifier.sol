// SPDX-License-Identifier: GPL-3.0
/*
    Copyright 2021 0KIMS association.

    This file is generated with [snarkJS](https://github.com/iden3/snarkjs).

    snarkJS is a free software: you can redistribute it and/or modify it
    under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    snarkJS is distributed in the hope that it will be useful, but WITHOUT
    ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
    or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public
    License for more details.

    You should have received a copy of the GNU General Public License
    along with snarkJS. If not, see <https://www.gnu.org/licenses/>.
*/

pragma solidity >=0.7.0 <0.9.0;

contract Groth16Verifier {
  // Scalar field size
  uint256 constant r = 21888242871839275222246405745257275088548364400416034343698204186575808495617;
  // Base field size
  uint256 constant q = 21888242871839275222246405745257275088696311157297823662689037894645226208583;

  // Verification Key data
  uint256 constant alphax = 16428432848801857252194528405604668803277877773566238944394625302971855135431;
  uint256 constant alphay = 16846502678714586896801519656441059708016666274385668027902869494772365009666;
  uint256 constant betax1 = 3182164110458002340215786955198810119980427837186618912744689678939861918171;
  uint256 constant betax2 = 16348171800823588416173124589066524623406261996681292662100840445103873053252;
  uint256 constant betay1 = 4920802715848186258981584729175884379674325733638798907835771393452862684714;
  uint256 constant betay2 = 19687132236965066906216944365591810874384658708175106803089633851114028275753;
  uint256 constant gammax1 = 11559732032986387107991004021392285783925812861821192530917403151452391805634;
  uint256 constant gammax2 = 10857046999023057135944570762232829481370756359578518086990519993285655852781;
  uint256 constant gammay1 = 4082367875863433681332203403145435568316851327593401208105741076214120093531;
  uint256 constant gammay2 = 8495653923123431417604973247489272438418190587263600148770280649306958101930;
  uint256 constant deltax1 = 16910491693153080086158527567465131445344250041031830191191473842298190388435;
  uint256 constant deltax2 = 3329530162562184920597388346389629691508876824994743052986236539666960426824;
  uint256 constant deltay1 = 9485206822488963103621492224139820793263482891666901675494690664373296388787;
  uint256 constant deltay2 = 3039978102919843682158038466625345284157816036791545947433653720702179722319;

  uint256 constant IC0x = 6093239204057318135600436973644089095602631057618989108476579285115782124223;
  uint256 constant IC0y = 11530774415286381806503670199171722425926693370207321715749302375072224915313;

  uint256 constant IC1x = 15279864132197551563107979869980355836491124764561940191220534782374530285608;
  uint256 constant IC1y = 15135342970492127668395411032251759914194674800502660259001274011154267976116;

  uint256 constant IC2x = 5004965141248393888219008288355380908071729016974638736664810848109093525839;
  uint256 constant IC2y = 7851197160622554056447294033162057070265745581139207692752800145605535000884;

  uint256 constant IC3x = 2398607899283903558446315737689532896691281922606595185553106049194303057395;
  uint256 constant IC3y = 6563246391602912797340734660907515283937587708547719302925148916522503034116;

  uint256 constant IC4x = 17704867663854716988735279264578116002494048322771546833844673981129196238611;
  uint256 constant IC4y = 3377776010783520965399198805131502764388606243579556030295660224451422284806;

  uint256 constant IC5x = 20872572144565561052472942773412411789070413498981533490603021174849747793709;
  uint256 constant IC5y = 2629365879406383680242580726579261787118247620662756456744593704281178080085;

  uint256 constant IC6x = 16307694842957463585158510842767685966590332753358398598513112418977906554057;
  uint256 constant IC6y = 3121587532262756567083989305365329081068143756781387967438542227967490523708;

  uint256 constant IC7x = 4611946905758627338589315410013407007186588865106558212655235412189246351271;
  uint256 constant IC7y = 13657570637982438894422673919044658544092685314519762540961069227821771044614;

  uint256 constant IC8x = 7666256288751744928002842088380192710195084374963258083732037693949756949918;
  uint256 constant IC8y = 8515745129258131782670140379951353192117630900896923642097940729853390732978;

  uint256 constant IC9x = 6835857798971949279037338392097906922704980327782413686353395113640643416786;
  uint256 constant IC9y = 15402206597314794218236431094478956449133029898576704137446082923442159703992;

  uint256 constant IC10x = 21779640990472641236170483741976658158531869032161563229584420300475966935423;
  uint256 constant IC10y = 3529300524829240543440753331686180063140076944750932554046104938325956059399;

  uint256 constant IC11x = 10173879770266009096701124401781395811990381723132416763973789490741288508604;
  uint256 constant IC11y = 13311117193822060316570400472630846917484149449161466223869437707789281341447;

  uint256 constant IC12x = 12298952484203395400735022982554921986398992520090253671929408420805828019585;
  uint256 constant IC12y = 6338131985049878954874559500530886746757410049041630175390918060068233857906;

  uint256 constant IC13x = 20356878148066118318675854367093071180674182827981195140877346459429116703696;
  uint256 constant IC13y = 12387272237034702834774175245349746996977026167255603120342704504457990529638;

  uint256 constant IC14x = 6700732654079082724538329851818836498153158134714515347135623294133895066593;
  uint256 constant IC14y = 8798259633706651421326778856870318597441098256309356585850745548577625379007;

  uint256 constant IC15x = 8404747761834771038602093065318682297150412247858178793451003564429894150171;
  uint256 constant IC15y = 13345636875656910983602309068854047727026866289703417150210299121236887540777;

  uint256 constant IC16x = 192060067381519942969754940836530666863181002399381635421944205289614315246;
  uint256 constant IC16y = 14787033373462956625052010824006604778427393486457693004216070358954224470666;

  uint256 constant IC17x = 5015208090492125024010845815720695340791811140792777587318639638615343560497;
  uint256 constant IC17y = 16968589574188695069901976269827633794370916334310978114259038891991171690333;

  uint256 constant IC18x = 3466356783684047744434803652123063286267827739344127263932055770591908150738;
  uint256 constant IC18y = 12372735196863339510994713969439262100976589205506076180247349200680219873143;

  uint256 constant IC19x = 1623607812788153773675188230084569522638728535567179913917445975761213295749;
  uint256 constant IC19y = 19630330025197465489410044588773428043747257162021302960943176364259705508513;

  uint256 constant IC20x = 7803322804137563049738649321545782384403931088712501094896733581000975083843;
  uint256 constant IC20y = 1818649619471646109526903539343172052504448981584400538766908082542984376382;

  // Memory data
  uint16 constant pVk = 0;
  uint16 constant pPairing = 128;

  uint16 constant pLastMem = 896;

  function verifyProof(
    uint[2] calldata _pA,
    uint[2][2] calldata _pB,
    uint[2] calldata _pC,
    uint[20] calldata _pubSignals
  ) public view returns (bool) {
    assembly {
      function checkField(v) {
        if iszero(lt(v, r)) {
          mstore(0, 0)
          return(0, 0x20)
        }
      }

      // G1 function to multiply a G1 value(x,y) to value in an address
      function g1_mulAccC(pR, x, y, s) {
        let success
        let mIn := mload(0x40)
        mstore(mIn, x)
        mstore(add(mIn, 32), y)
        mstore(add(mIn, 64), s)

        success := staticcall(sub(gas(), 2000), 7, mIn, 96, mIn, 64)

        if iszero(success) {
          mstore(0, 0)
          return(0, 0x20)
        }

        mstore(add(mIn, 64), mload(pR))
        mstore(add(mIn, 96), mload(add(pR, 32)))

        success := staticcall(sub(gas(), 2000), 6, mIn, 128, pR, 64)

        if iszero(success) {
          mstore(0, 0)
          return(0, 0x20)
        }
      }

      function checkPairing(pA, pB, pC, pubSignals, pMem) -> isOk {
        let _pPairing := add(pMem, pPairing)
        let _pVk := add(pMem, pVk)

        mstore(_pVk, IC0x)
        mstore(add(_pVk, 32), IC0y)

        // Compute the linear combination vk_x

        g1_mulAccC(_pVk, IC1x, IC1y, calldataload(add(pubSignals, 0)))

        g1_mulAccC(_pVk, IC2x, IC2y, calldataload(add(pubSignals, 32)))

        g1_mulAccC(_pVk, IC3x, IC3y, calldataload(add(pubSignals, 64)))

        g1_mulAccC(_pVk, IC4x, IC4y, calldataload(add(pubSignals, 96)))

        g1_mulAccC(_pVk, IC5x, IC5y, calldataload(add(pubSignals, 128)))

        g1_mulAccC(_pVk, IC6x, IC6y, calldataload(add(pubSignals, 160)))

        g1_mulAccC(_pVk, IC7x, IC7y, calldataload(add(pubSignals, 192)))

        g1_mulAccC(_pVk, IC8x, IC8y, calldataload(add(pubSignals, 224)))

        g1_mulAccC(_pVk, IC9x, IC9y, calldataload(add(pubSignals, 256)))

        g1_mulAccC(_pVk, IC10x, IC10y, calldataload(add(pubSignals, 288)))

        g1_mulAccC(_pVk, IC11x, IC11y, calldataload(add(pubSignals, 320)))

        g1_mulAccC(_pVk, IC12x, IC12y, calldataload(add(pubSignals, 352)))

        g1_mulAccC(_pVk, IC13x, IC13y, calldataload(add(pubSignals, 384)))

        g1_mulAccC(_pVk, IC14x, IC14y, calldataload(add(pubSignals, 416)))

        g1_mulAccC(_pVk, IC15x, IC15y, calldataload(add(pubSignals, 448)))

        g1_mulAccC(_pVk, IC16x, IC16y, calldataload(add(pubSignals, 480)))

        g1_mulAccC(_pVk, IC17x, IC17y, calldataload(add(pubSignals, 512)))

        g1_mulAccC(_pVk, IC18x, IC18y, calldataload(add(pubSignals, 544)))

        g1_mulAccC(_pVk, IC19x, IC19y, calldataload(add(pubSignals, 576)))

        g1_mulAccC(_pVk, IC20x, IC20y, calldataload(add(pubSignals, 608)))

        // -A
        mstore(_pPairing, calldataload(pA))
        mstore(add(_pPairing, 32), mod(sub(q, calldataload(add(pA, 32))), q))

        // B
        mstore(add(_pPairing, 64), calldataload(pB))
        mstore(add(_pPairing, 96), calldataload(add(pB, 32)))
        mstore(add(_pPairing, 128), calldataload(add(pB, 64)))
        mstore(add(_pPairing, 160), calldataload(add(pB, 96)))

        // alpha1
        mstore(add(_pPairing, 192), alphax)
        mstore(add(_pPairing, 224), alphay)

        // beta2
        mstore(add(_pPairing, 256), betax1)
        mstore(add(_pPairing, 288), betax2)
        mstore(add(_pPairing, 320), betay1)
        mstore(add(_pPairing, 352), betay2)

        // vk_x
        mstore(add(_pPairing, 384), mload(add(pMem, pVk)))
        mstore(add(_pPairing, 416), mload(add(pMem, add(pVk, 32))))

        // gamma2
        mstore(add(_pPairing, 448), gammax1)
        mstore(add(_pPairing, 480), gammax2)
        mstore(add(_pPairing, 512), gammay1)
        mstore(add(_pPairing, 544), gammay2)

        // C
        mstore(add(_pPairing, 576), calldataload(pC))
        mstore(add(_pPairing, 608), calldataload(add(pC, 32)))

        // delta2
        mstore(add(_pPairing, 640), deltax1)
        mstore(add(_pPairing, 672), deltax2)
        mstore(add(_pPairing, 704), deltay1)
        mstore(add(_pPairing, 736), deltay2)

        let success := staticcall(sub(gas(), 2000), 8, _pPairing, 768, _pPairing, 0x20)

        isOk := and(success, mload(_pPairing))
      }

      let pMem := mload(0x40)
      mstore(0x40, add(pMem, pLastMem))

      // Validate that all evaluations ∈ F

      checkField(calldataload(add(_pubSignals, 0)))

      checkField(calldataload(add(_pubSignals, 32)))

      checkField(calldataload(add(_pubSignals, 64)))

      checkField(calldataload(add(_pubSignals, 96)))

      checkField(calldataload(add(_pubSignals, 128)))

      checkField(calldataload(add(_pubSignals, 160)))

      checkField(calldataload(add(_pubSignals, 192)))

      checkField(calldataload(add(_pubSignals, 224)))

      checkField(calldataload(add(_pubSignals, 256)))

      checkField(calldataload(add(_pubSignals, 288)))

      checkField(calldataload(add(_pubSignals, 320)))

      checkField(calldataload(add(_pubSignals, 352)))

      checkField(calldataload(add(_pubSignals, 384)))

      checkField(calldataload(add(_pubSignals, 416)))

      checkField(calldataload(add(_pubSignals, 448)))

      checkField(calldataload(add(_pubSignals, 480)))

      checkField(calldataload(add(_pubSignals, 512)))

      checkField(calldataload(add(_pubSignals, 544)))

      checkField(calldataload(add(_pubSignals, 576)))

      checkField(calldataload(add(_pubSignals, 608)))

      // Validate all evaluations
      let isValid := checkPairing(_pA, _pB, _pC, _pubSignals, pMem)

      mstore(0, isValid)
      return(0, 0x20)
    }
  }
}
