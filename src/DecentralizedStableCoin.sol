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
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";


/**
 * @title DecentralizedStableCoin
 * @author 0x0115
 * Collateral: Exogenous (wETH & wBTC)
 * Minting: Algorithmic
 * Relative Stability: Anchored (pegged to USD)
 *
 * This is a contract meant to be governed by DSCEngine. This contract is just the ERC20 implementation of our stablecoin.
 */
contract DecentralizedStableCoin is ERC20Burnable, Ownable {
  error DecentralizedStableCoin__BurnAmountExceedsBalance();
  error DecentralizedStableCoin__BurnAmountMustBeGreaterThanZero();

  
  constructor()ERC20("DecentralizedStableCoin", "DSC") Ownable(msg.sender) {}

  function burn(uint256 _amount) public override onlyOwner {
    uint256 balance = balanceOf(msg.sender);
    if (balance < _amount) {
      revert DecentralizedStableCoin__BurnAmountExceedsBalance();
    }
    if (_amount == 0) {
      revert DecentralizedStableCoin__BurnAmountMustBeGreaterThanZero();
    }
    super.burn(_amount);
  }

  function mint(address _to, uint256 _amount) public onlyOwner {
    _mint(_to, _amount);
  }
}

