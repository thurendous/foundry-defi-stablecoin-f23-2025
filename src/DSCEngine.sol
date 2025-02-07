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
    error DSCEngine__TokenNotAllowed(address tokenCollateralAddress);
    error DSCEngine__MismatchLength();
    error DSCEngine__TransferFailed();
    error DSCEngine__HealthFactorIsBroken(uint256 healthFactor);
    error DSCEngine__HealthFactorIsNotBroken(uint256 healthFactor);
    error DSCEngine__MintFailed();
    error DSCEngine__BurnFailed();
    error DSCEngine__HealthFactorNotImproved(uint256 healthFactor);
    //////////////////
    //// EVENTS //////
    //////////////////
    event CollateralDeposited(address indexed user, address indexed tokenCollateralAddress, uint256 amountCollateral);
    // event CollateralRedeemed(address indexed user, address indexed tokenCollateralAddress, uint256 amountCollateral);
    event CollateralRedeemed(address indexed redeemedFrom, address indexed redeemedTo, address indexed tokenCollateralAddress, uint256 amountCollateral);

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
    uint256 private constant PRECISION = 1e18;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant LIQUIDATION_BONUS = 10; // 10% bonus


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
            revert DSCEngine__TokenNotAllowed(_tokenCollateralAddress);
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

    function getCollateralBalanceOfUser(address _user, address _tokenAddress) public view returns (uint256) {
        return s_collateralDeposits[_user][_tokenAddress];
    }

    ////////////////////////////
    //// EXTERNAL FUNCTIONS ////
    ////////////////////////////
    /**
     * @notice Deposit Collateral and Mint DSC
     * @param _tokenCollateralAddress The address of the collateral token to deposit
     * @param _amountCollateral The amount of collateral to deposit
     * @param _amountDscToMint The amount of DSC to mint
     * @notice This function will deposit your collateral and mint DSC
     */
    function depositCollateralAndMintDSC(address _tokenCollateralAddress, uint256 _amountCollateral, uint256 _amountDscToMint) external {
        depositCollateral(_tokenCollateralAddress, _amountCollateral);
        mintDsc(_amountDscToMint);
    }

    /**
     * @notice Deposit Collateral
     * @param _tokenCollateralAddress The address of the collateral token
     * @param _amountCollateral The amount of collateral to deposit
     * @dev following CEI (Checks, Effects, Interactions)
     */
    function depositCollateral(address _tokenCollateralAddress, uint256 _amountCollateral)
        public
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

    /**
     * @notice Redeem Collateral for DSC
     * @param _tokenCollateralAddress The address of the collateral token
     * @param _amountCollateral The amount of collateral to redeem
     * @param _amountDscToBurn The amount of DSC to burn
     * @dev This function burns the DSC and redeems the underlying collateral in one transaction
     */
    function redeemCollateralForDSC(address _tokenCollateralAddress, uint256 _amountCollateral, uint256 _amountDscToBurn) external moreThanZero(_amountCollateral) nonReentrant {
        burnDsc(_amountDscToBurn);
        redeemCollateral(_tokenCollateralAddress, _amountCollateral);
    }

    /**
     * for the user himself to redeem collateral: 
     * 1. health factor must be over 1 AFTER collateral is redeemed
     * 2. the amount of collateral to redeem must be more than 0
     * DRY: Don't Repeat Yourself
     */
    // CEI: Checks, Effects, Interactions
    function redeemCollateral(address _tokenCollateralAddress, uint256 _amountCollateral) public moreThanZero(_amountCollateral) nonReentrant {
        // This already checks if the user has enough collateral to redeem
        // here it will revert if the amount is not enough
        _redeemCollateral(msg.sender, msg.sender, _tokenCollateralAddress, _amountCollateral);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

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
    function mintDsc(uint256 _amountDscToMint) public moreThanZero(_amountDscToMint) nonReentrant {
        s_dscMinted[msg.sender] += _amountDscToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, _amountDscToMint);
        if (!minted) revert DSCEngine__MintFailed();
    }

    // it is highly unlikely that the burning will break the health factor
    // but in case it does, we also check the health factor here
    function burnDsc(uint256 _amount) public moreThanZero(_amount) nonReentrant {
        _burnDsc(msg.sender, msg.sender, _amount);
        _revertIfHealthFactorIsBroken(msg.sender); // I don't think this would ever hit...And in case someone wants to burn DSC to reduce the liability, they can do it.
    }

    // $100 ETH backing $50 DSC
    // $20 ETH backing $50 DSC -> we can't let this happen
    // we need to liquidate the user's collateral to make sure the health factor is over 50%
    // if someone is almost collateralized, we can pay anyone to liquidate him
    // e.g. if someone is $75 backing %50, we can pay someone to liquidate him and get his collateral
    /**
     * @param _collateral The erc20 collateral address to liquidate from the user
     * @param _user The user who has broken the health factor. Their _healthFactor should be less than MIN_HEALTH_FACTOR
     * @param _debtToCover The amount of DSC to burn to cover the debt
     * @dev This function will liquidate the user's collateral and burn the DSC. You will get a liquidation bonus for your work.
     * @dev This function working assumes that the system is overcollateralized.
     * @dev This whole system works if the system is overcollateralized. If not, then the system breaks -> This is a known bug, which would be if the protocol were 100% or less collateralized, then we wouldn't be able to incentivize liquidators to liquidate the users who are underwater.
     * for example, if the price plummeted before anyone could liquidate the user, then the user would be underwater and the system would break.
     * follows CEI (Checks, Effects, Interactions)
     */
    function liquidate(address _collateral, address _user, uint256 _debtToCover) external moreThanZero(_debtToCover) nonReentrant {
        // need to check the health factor of the user
        uint256 startingUserHealthFactor = _healthFactor(_user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) revert DSCEngine__HealthFactorIsNotBroken(startingUserHealthFactor);

        // start liquidation now
        // We want to burn their DSC "debt"
        // and then take their collateral
        // underwater user: $140 ETH, $100 DSC
        // debtToCover = 100$
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(_collateral, _debtToCover);
        // And give them a 10% bonus
        // We should implement a feature to liquidate in the event the protocol is insolvent
        // And sweep extra amounts into a treasury
        // 0.003125 ETH + 10% bonus = 0.0034375 ETH
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralToTransfer = tokenAmountFromDebtCovered + bonusCollateral;
        _redeemCollateral(_user, msg.sender, _collateral, totalCollateralToTransfer);
        // msg.sender is liquidating the user using the _debtToCover DSC
        _burnDsc(_user, msg.sender, _debtToCover);

        uint256 endingUserHealthFactor = _healthFactor(_user);
        if (endingUserHealthFactor <= startingUserHealthFactor) revert DSCEngine__HealthFactorNotImproved(endingUserHealthFactor);
        // also checks that the health factor of msg.sender is broken or not
        // _revertIfHealthFactorIsBroken(msg.sender); // this is not needed, because the one whose health factor is broken can also liquidate other users.
    }

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
     * Low-level internal function to burn DSC
     * Do not call unless the function calling it is checking the health factor
     * @param _onBehalfOf The address of the user who responsible for the debt
     * @param _dscFrom The address of the user who is sending the DSC to pay off the debt
     * @param _amountDscToBurn The amount of DSC to burn
     */
    function _burnDsc(address _onBehalfOf, address _dscFrom, uint256 _amountDscToBurn) private {
        s_dscMinted[_onBehalfOf] -= _amountDscToBurn;
        bool success = i_dsc.transferFrom(_dscFrom, address(this), _amountDscToBurn);
        if (!success) revert DSCEngine__TransferFailed();
        i_dsc.burn(_amountDscToBurn);
    }

    function _redeemCollateral(address _from, address _to, address _tokenCollateralAddress, uint256 _amountCollateral) private {
        // This already checks if the user has enough collateral to redeem
        // here it will revert if the amount is not enough
        s_collateralDeposits[_from][_tokenCollateralAddress] -= _amountCollateral;
        emit CollateralRedeemed(_from, _to, _tokenCollateralAddress, _amountCollateral);
        bool success = IERC20(_tokenCollateralAddress).transfer(_to, _amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

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
        if (totalDscMinted == 0) return type(uint256).max; // by this, we avoided division by zero
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
    function calculateHealthFactor(uint256 totalDscMinted, uint256 collateralValueInUsd) external pure returns (uint256) {
        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }

    function getTokenAmountFromUsd(address _tokenCollateralAddress, uint256 usdAmountInWei) public view returns (uint256 tokenAmount) {
        address priceFeedAddress = getPriceFeed(_tokenCollateralAddress);
        AggregatorV3Interface priceFeed = AggregatorV3Interface(priceFeedAddress);
        (, int256 price, , , ) = priceFeed.latestRoundData();
        // ($10e18 * 1e18) / $2000
        // 10e18 * 1e18 / (3200e8 * 1e10)
        // = 10e36 / 3200e18 = 3.125e15
        // 0.003125 ETH
        tokenAmount = (usdAmountInWei * PRECISION) / (uint256(price) * ADDITION_FEED_PRECISION);
    }

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

    function getAccountInformation(address _user) public view returns (uint256 totalDscMinted, uint256 totalCollateralValueInUsd) {
        (totalDscMinted, totalCollateralValueInUsd) = _getAccountInformation(_user);
    }
}
