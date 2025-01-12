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
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

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
 * @notice This contract is VERY loosely based on the MakerDAO DSS (DAI) system.
 */
contract DSCEngine is Ownable, ReentrancyGuard {
    //////////////////
    //// ERRORS //////
    //////////////////
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenNotAllowed();
    error DSCEngine__MismatchLength();
    error DSCEngine__TransferFailed();
    error DSCEngine__HealthFactorIsBroken(uint256 healthFactor);
    error DSCEngine__MintFailed();
    //////////////////
    //// EVENTS //////
    //////////////////
    event CollateralDeposited(address indexed user, address indexed tokenCollateralAddress, uint256 amountCollateral);

    ///////////////////////////
    //// STATE VARIABLES //////
    ///////////////////////////
    DecentralizedStableCoin private immutable i_dsc;
    address[] private s_collateralTokens;
    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposits;
    mapping(address user => uint256 amountDscMinted) private s_dscMinted;

    uint256 private constant ADDITION_FEED_PRECISION = 1e10;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% overcollateralized
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;


    /////////////////////
    //// MODIFIERS //////
    /////////////////////
    modifier moreThanZero(uint256 _amount) {
        if (_amount == 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address _tokenCollateralAddress) {
        if (getPriceFeed(_tokenCollateralAddress) == address(0)) {
            revert DSCEngine__TokenNotAllowed();
        }
        _;
    }

    ///////////////////
    //// FUNCTIONS ////
    ///////////////////
    constructor(address _dscAddress, address[] memory _collateralTokens, address[] memory _priceFeedAddresses) Ownable(msg.sender) {
        if (_collateralTokens.length != _priceFeedAddresses.length) {
            revert DSCEngine__MismatchLength();
        }
        i_dsc = DecentralizedStableCoin(_dscAddress);
        s_collateralTokens = _collateralTokens;
        for (uint256 i; i < _collateralTokens.length;) {
            s_priceFeeds[_collateralTokens[i]] = _priceFeedAddresses[i];
            unchecked {
                ++i;
            }
        }
    }

    function getCollateralBalance(address _tokenAddress) public view returns (uint256) {
        return IERC20(_tokenAddress).balanceOf(address(this));
    }

    ////////////////////////////
    //// EXTERNAL FUNCTIONS ////
    ////////////////////////////
    /**
     * @notice Deposit Collateral and Mint DSC
     * @param _tokenCollateralAddress The address of the collateral token
     * @param _amountCollateral The amount of collateral to deposit
     */
    function depositCollateralAndMintDSC(address _tokenCollateralAddress, uint256 _amountCollateral) external {}

    /**
     * @notice Deposit Collateral
     * @param _tokenCollateralAddress The address of the collateral token
     * @param _amountCollateral The amount of collateral to deposit
     * @dev following CEI (Checks, Effects, Interactions)
     */
    function depositCollateral(address _tokenCollateralAddress, uint256 _amountCollateral)
        external
        moreThanZero(_amountCollateral)
        isAllowedToken(_tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposits[msg.sender][_tokenCollateralAddress] += _amountCollateral;
        emit CollateralDeposited(msg.sender, _tokenCollateralAddress, _amountCollateral);

        bool success = IERC20(_tokenCollateralAddress).transferFrom(msg.sender, address(this), _amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

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

    // 1. check the collateral value is greater than the DSC amount. Price feeds, values, etc.
    // 2. mint the DSC
    /**
     * @notice Mint DSC
     * @param _amountDscToMint The amount of Decentralized Stablecoin to mint
     * @notice they must have more collateral than the minimal threshold
     */
    function mintDsc(uint256 _amountDscToMint) external moreThanZero(_amountDscToMint) nonReentrant {
        s_dscMinted[msg.sender] += _amountDscToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, _amountDscToMint);
        if (!minted) revert DSCEngine__MintFailed();
    }

    function burnDsc() external {}

    function liquidate() external {}


    function getHealthFactor(address _user) public view returns (uint256) {
        return _healthFactor(_user);
    }

    function getDecentralizedStableCoin() public view returns (address) {
        return address(i_dsc);
    }

    function getPriceFeed(address _tokenAddress) public view returns (address) {
        return s_priceFeeds[_tokenAddress];
    }

    ////////////////////////////////////////
    //// PRIVATE & INTERNAL FUNCTIONS //////
    ////////////////////////////////////////
    /** 
     * Returns how close to liquidation a user is
     * If the user goes below 1, then they can be liquidated
     */
    function _healthFactor(address _user) internal view returns (uint256) {
        // total DSC minted
        // total collateral value
        // 1e18 / total DSC minted * total collateral value
        (uint256 totalDscMinted, uint256 totalCollateralValueInUsd) = _getAccountInformation(_user);
        // return (totalCollateralValueInUsd / totalDscMinted); // 150 / 100 is the minimum
        return _calculateHealthFactor(totalDscMinted, totalCollateralValueInUsd);
        // $150 ETH / $100 DSC = 1.5
        // $150 * 50 / 100 = 75
        // 75 / 100 = 0.75 < 1
        // 
        // here it means that the collateral value adjusted is the half of the underlying collateral's value. 
        // so the adjusted collateral value is $75
        // so the health factor is 0.66666666 now = $75 / $100
    }

    function _calculateHealthFactor( 
        uint256 totalDscMinted,
        uint256 collateralValueInUsd
    ) internal pure returns (uint256) {
        if (totalDscMinted == 0) return type(uint256).max;
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }

    function _getAccountInformation(address _user) internal view returns (uint256, uint256) {
        uint256 totalDscMinted = s_dscMinted[_user];
        uint256 totalCollateralValue = getAccountCollateralValue(_user);
        return (totalDscMinted, totalCollateralValue);
    }

    function _revertIfHealthFactorIsBroken(address _user) internal view {
        // 1. check health factor (do they have enough collateral to cover their DSC?)
        // 2. revert if they don't have enough collateral
        uint256 userHealthFactor = _healthFactor(_user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorIsBroken(userHealthFactor);
        }
    }

    //////////////////////////////////////////
    //// PUBLIC & External VIEW FUNCTIONS ////
    //////////////////////////////////////////
    function getAccountCollateralValue(address _user) public view returns (uint256) {
        // loop through each collateral token, get the amount they have deposited, and map it to the price, to get the USD value.
        uint256 totalCollateralValueInUsd;
        for (uint256 i; i < s_collateralTokens.length;) {
            address tokenCollateralAddress = s_collateralTokens[i];
            uint256 amountCollateral = s_collateralDeposits[_user][tokenCollateralAddress];
            totalCollateralValueInUsd += getUsdValueOfCollateral(tokenCollateralAddress, amountCollateral);
            unchecked {
                ++i;
            }
        }
        return totalCollateralValueInUsd;
    }

    function getUsdValueOfCollateral(address _tokenCollateralAddress, uint256 _amountCollateral) public view returns (uint256) {
        // get the price of the collateral
        // get the price of the token in USD
        // return the price of the token in USD * the amount of the token
        address priceFeedAddress = getPriceFeed(_tokenCollateralAddress);
        AggregatorV3Interface priceFeed = AggregatorV3Interface(priceFeedAddress);
        (, int256 price, , , ) = priceFeed.latestRoundData();
        // 1ETH = $1000
        // 1000 * 1000000000000000000 / 1e18 = 1000000000000000000000
        return (uint256(price) * ADDITION_FEED_PRECISION) * _amountCollateral / 1e18;
    }

    function getCollateralTokens() public view returns (address[] memory) {
        return s_collateralTokens;
    }
}
