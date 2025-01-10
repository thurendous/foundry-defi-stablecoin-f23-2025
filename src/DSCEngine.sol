// SPDX-License-Identifier: MIT

// This is considered an Exogenous, Decentralized, Anchored (pegged), Crypto Collateralized low volitility coin

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

pragma solidity 0.8.24;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";

/**
 * @title DSCEngine
 * @author 0x0115
 * @notice This contract is for creating a decentralized stablecoin
 * 
 * The system is designed to be as minimal as possible, and have the tokens maintain a 1:1 peg with the US dollar.
 * The stablecoin has the properties: 
 * - Exogenous Collateral: wETH & wBTC
 * - Dollar Pegged
 * - Algorithmically Stable
 * 
 * It is similar to DAI if DAI had no governance, no fees, and was only backed by wETH & wBTC.
 * Our DSC system should be always "overcollateralized". This means that the total value of all collateral must be greater than the total value of all DSC.
 *
 * @notice This contract is the core of the DSC system. It handles all the logic for minting redeeming DSC. As well as depositing and withdrawing collateral.
 */
contract DSCEngine is Ownable {
  DecentralizedStableCoin public immutable i_dsc;
  address[] public s_collateralTokens;

  constructor(address _dscAddress, address[] memory _collateralTokens) Ownable(msg.sender) {
    i_dsc = DecentralizedStableCoin(_dscAddress);
    s_collateralTokens = _collateralTokens;
  }

  function getCollateralBalance(address _tokenAddress) public view returns (uint256) {
    return IERC20(_tokenAddress).balanceOf(address(this));
  }

  /**
   * @notice Deposit Collateral and Mint DSC
   * @param _tokenCollateralAddress The address of the collateral token
   * @param _amountCollateral The amount of collateral to deposit
   */
  function depositCollateralAndMintDSC(address _tokenCollateralAddress, uint256 _amountCollateral) external {}

  function redeemCollateralForDSC() external {}

  // e.g. an example of undercollateralized situation: 
  // Threshhold to let's say 150%
  // $100 ETH Collateral -> $74
  // $50 DSC Minted
  // Undercollateralized
  // I'll pay back the $50 DSC -> Get all your collateral 
  // $74
  // -$50 DSC
  // $24


  function burnDsc() external {}

  function liquidate() external {}

  function getHealthFactor() public view returns (uint256) {
    return 0;
  }
}
