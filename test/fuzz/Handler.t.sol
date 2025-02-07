// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin as DSC} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";


// Handler is gonna narrow down the way we call the functions.

// What are our invariants?
// 1. The total supply of DSC should be always less than the total collateral value.
// 2. Getter view functions should never revert. -> evergreen invariant
// 3. The system should always be overcollateralized.
// 4. The system should always be solvent.
// 5. The system should always be liquid.
// 6. The system should always be stable.

contract Handler is Test {
  DSC public dsc;
  DSCEngine public dsce;
  address public weth;
  address public wbtc;
  uint256 public amountCollateral;
  uint256 public amountDscToMint;
  uint256 public totalTimesCalledMintDsc;

  uint256 MAX_DEPOSITE_SIZE = type(uint96).max;

  constructor(DSCEngine _dsce, DSC _dsc) {
    dsce = _dsce;
    dsc = _dsc;
    address[] memory collateralTokens = dsce.getCollateralTokens();
    weth = collateralTokens[0];
    wbtc = collateralTokens[1];
  }

  // redeem collateral
    function redeemCollateral(uint256 _collateralSeed, uint256 _amountCollateral) public {
    ERC20Mock collateral = _getCollateralSeed(_collateralSeed);
    uint256 maxCollateralToRedeem = dsce.getCollateralBalanceOfUser(msg.sender, address(collateral));
    amountCollateral = bound(_amountCollateral, 0, maxCollateralToRedeem);
    vm.assume(amountCollateral != 0);
    dsce.redeemCollateral(address(collateral), amountCollateral);
  }

  function depositCollateral(uint256 _collateralSeed, uint256 _amountCollateral) public {
    ERC20Mock collateral = _getCollateralSeed(_collateralSeed);
    amountCollateral = bound(_amountCollateral, 1, MAX_DEPOSITE_SIZE);
    vm.startPrank(msg.sender);
    collateral.mint(msg.sender, _amountCollateral);
    collateral.approve(address(dsce), _amountCollateral);
    dsce.depositCollateral(address(collateral), amountCollateral);
    vm.stopPrank();
  }

  function mintDsc(uint256 _amountDscToMint) public {
    // if (usersWithCollateralDeposit.length == 0) {
    //   return;
    // }
    amountDscToMint = bound(_amountDscToMint, 1, MAX_DEPOSITE_SIZE);
    (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(msg.sender);

    int256 maxDscToMint = (int256(collateralValueInUsd) / 2) - int256(totalDscMinted);
    vm.assume(_amountDscToMint >= 0);
    amountDscToMint = bound(amountDscToMint, 0, uint256(maxDscToMint));
    
    vm.startPrank(msg.sender);
    dsce.mintDsc(_amountDscToMint);
    vm.stopPrank();
    totalTimesCalledMintDsc++;
  }

  function _getCollateralSeed(uint256 _collateralSeed) public view returns (ERC20Mock) {
    if (_collateralSeed % 2 == 0) {
      return ERC20Mock(weth);
    }
    return ERC20Mock(wbtc);
  }
}


