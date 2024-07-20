// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {console} from "../lib/forge-std/src/console.sol";

/**
 * @title DSCEngine
 * @author maptool
 *
 * The system is designed to be as minimal as possible, and have the tokens mantain a 1 token == $1 peg.
 * This stablecoin has the properties:
 * - Exogenous collateral
 * - Dollar pegged
 * - Algorithmically stable
 *
 * It is similar to DAI if DAI had no governance, no fees, and was only backed by wETH and wBTC.
 *
 * Our DSC system should allways be "avoercollateralized". At no point, should the value of all collateral <= than the value of all the DSC.
 *
 * @notice This contract is the core of the DSC system. It handles all the logic for mining and redeeming DSC, as well as depositing and withdrawing collateral
 * @notice This contract is very loosely based on the MakerDAO DSS (DAI) system
 */

contract DSCEngine is ReentrancyGuard {
    
    
    
    ////////////////////
    /// Errors        //
    ////////////////////
    error DSCEngine__MoreThanZero();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLenght();
    error DSCEngine__NotAllowedToken();
    error DSCEngine__TransferFailed();
    error DSCEngine__BreaksHealthFactor(uint256 healthFactorValue);
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorOK();
    error DSCEngine__HealthFactorNotImproved();
    error DSCEngine__DscOrCollateralIsZero();

    
    
    
    //////////////////////
    /// State variables //
    //////////////////////
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% liquidation ratio
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10;

    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount))
        private s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_DSCMinted;
    address[] private s_collateralTokens;
    mapping(address tokenAddress => uint256 tokenPrice) private s_tokenPrices;

    DecentralizedStableCoin private immutable i_dsc;

    
    
    
    
    
    /////////////////
    /// Events     //
    /////////////////

    event CollateralDeposited(
        address indexed user,
        address indexed token,
        uint256 indexed amount
    );
    event CollateralRedeemed(
        address indexed redeemedFrom,
        address indexed redeemedTo,
        address token,
        uint256 amount
    );

    event DscMinted (address indexed user, uint256 indexed amount);

    
    
    
    
    ////////////////////
    /// Modifiers    ///
    ////////////////////
    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__MoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__NotAllowedToken();
        }
        _;
    }






    /////////////////////////
    /// External Functions //
    /////////////////////////

    constructor(
        address[] memory tokenAddresses,
        address[] memory priceFeedAddresses,
        address dscAddress
    ) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLenght();
        }

        // USD price feeds: ETH/USD, BTC/USD, etc
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
            AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[tokenAddresses[i]]);
            (, int256 price, , , ) = priceFeed.latestRoundData();
            s_tokenPrices[tokenAddresses[i]] = uint256(price);

        }
        i_dsc = DecentralizedStableCoin(dscAddress);
        
        

        
    }






    /**
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param amountCollateral The amount of collateral to deposit
     * @param amountDscToMint The amount of decentralized stablecoin to mint
     * @notice this function will deposit your collateral and mint the DSC in one transaction
     */

    function despositCollateralAndMintDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDscToMint);
        

    }







    /**
     * @notice follows CEI
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param amountCollateral the amount of collateral to deposit
     */
    function depositCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    )
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][
            tokenCollateralAddress
        ] += amountCollateral;
        emit CollateralDeposited(
            msg.sender,
            tokenCollateralAddress,
            amountCollateral
        );

        bool success = IERC20(tokenCollateralAddress).transferFrom(
            msg.sender,
            address(this),
            amountCollateral
        );
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }








    function redeemCollateralForDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToBurn
    ) external {
        burnDsc(amountDscToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
    }

    
    
    
    
    
    
    
    
    // In order to redeen collateral:
    // 1. Health factor must be over 1 AFTER collateral pulled
    function redeemCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    ) public moreThanZero(amountCollateral) nonReentrant {
        _redeemCollateral(msg.sender, msg.sender, tokenCollateralAddress, amountCollateral);

        //_revertIfHealthFactorIsBroken(msg.sender);
    }

    
    
    
    
    
    
    
    
    /**
     * @notice follows CEI
     * @param amountDscToMint The amount of decentralized stablecoin to mint
     * @notice they must have more collateral value than the minimum threshold
     */
    function mintDsc(
        uint256 amountDscToMint
    ) public moreThanZero(amountDscToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountDscToMint;
        emit DscMinted(msg.sender, amountDscToMint);
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
        
        
        
    }



    
    
    
    
    
    
    
    
    function burnDsc(uint256 amount) public moreThanZero(amount) {
        _burnDsc(amount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender); // I don't think this would ever hit...
    }

    
    
    
    
    
    
    
    
    
    
    /**
     * 
     * @param collateral The ERC20 collateral address to liquidate from user
     * @param user The user who has broken the health factor. Their health factor should be below MIN_HEALTH_FACTOR
     * @param debtToCover THe amount of DSC you want to burn to improve the users health factor.
     * @notice You can partially liquidate a user
     * @notice You will get a liquidation bonus for taking the users funds.
     * @notice This function working assumes the protocol will be roughly 200% overcollaterized in order for this to work.
     * @notice A known bug would be if the protocol were 100% or less collaterazides, then we wouldn't be able to incentive the liquidators
     * For example if the price of collateral plummeted before anyone could be liquidated.
     * Follows CEI: Checks, effects, interactions
     */

    function liquidate(address collateral, address user, uint256 debtToCover) external moreThanZero(debtToCover) {
        // Need to check health factor of the user
        uint256 startingUserHealthFactor = _healthFactor(user);
        console.log("Health factor: ", startingUserHealthFactor);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOK();
        }

        // We want to burn their DSC debt and take their collateral
        // BAD USER: $140 ETH / 100 DSC
        // debtToCover = $100
        // $100 DSC = ??? ETH
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral, debtToCover);
        
        // Give them a 10% bonus
        // So we are giving the liquidator 110 WETH for 100 DSC
        // We should implement a feature to liquidate in the event the protocol is insolvent
        // And sweep extra amounts into treasury
        // 0.05 * 0.1 = 0.005 --> Liquidator is getting 0.055
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateral = tokenAmountFromDebtCovered + bonusCollateral;
        _redeemCollateral(user, msg.sender, collateral, totalCollateral);
        _burnDsc(debtToCover, user, msg.sender);

        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    
    }

    
    
    
    
    
    
    

    ///////////////////////////////////
    /// Private & Internal view Functions //
    ///////////////////////////////////

    
    function _redeemCollateral(address from, address to, address tokenCollateralAddress, uint256 amountCollateral) private {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(
            from,
            to,
            tokenCollateralAddress,
            amountCollateral
            
        );

        bool success = IERC20(tokenCollateralAddress).transfer(to,amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    
    
    
    
    
    
    
    /**
     * @dev low-level internal function, do not call unless the function calling it is checking fpr health factor being broken
     */

    function _burnDsc(uint256 amountDscToBurn, address onBehalfOf, address dscFrom) private {
        s_DSCMinted[onBehalfOf] -= amountDscToBurn;
        bool success = i_dsc.transferFrom(dscFrom, address(this), amountDscToBurn);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amountDscToBurn);
    }

    
    
    
    
    
    /**
     *
     * returns how close the liquidation a user is
     * If a user goes below 1, they can get liquidated
     */

    function _healthFactor(address user) internal view returns (uint256) {
        // Total DSC minted
        // Total collateral value
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
       
        
        // Another option, I convert the Dsc minted tokens into USD to make the calculations. This option is not good, because I thought the DSC amount minted
        // it was ether (actually we put ether but simulates USD) so in this option i convert the amount Minted Tokens to USD using teh functions but I realized that not.
        /*
        if (totalDscMinted == 0) return type(uint256).max;
        address tokenAddress = getTokenAddressFromUser(user);
        uint256 tokenPrice = s_tokenPrices[tokenAddress];                
        uint256 dscMintedinUsd = tokenPrice* totalDscMinted;
        console.log("Dsc minted in USD: ", dscMintedinUsd);
        console.log("token price: ", tokenPrice);
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd *
            LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        console.log("Collateral threshold: ", collateralAdjustedForThreshold);
        // 150 ETH / 100 DSC
        // 150 * 50 = 7500 / 100 = (75 / 100) < 1 (BAD)

        // 1000 ETH / 100 DSC
        // 1000 * 50 = 50000 / 100 = (500 / 100) > 1 (GOOD)
        
        
        return (collateralAdjustedForThreshold * PRECISION) / dscMintedinUsd;*/
        
        
    }




    function _calculateHealthFactor(uint256 totalDscMinted, uint256 collateralValueInUsd) internal pure returns(uint256) {
        if (totalDscMinted == 0) return type(uint256).max;
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }




    function _getAccountInformation(
        address user
    )
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        totalDscMinted = s_DSCMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }

    
    
    
    
    
    
    function _revertIfHealthFactorIsBroken(address user) internal view {
        // Check health factor (Do they have enough Collateral?)
        // Revert if they don't
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    
    
    
    
    
    
    ///////////////////////////////////
    /// External & Public view Functions //
    ///////////////////////////////////


    function calculateHealthFactor(uint256 totalDscMinted, uint256 collateralValueInUsd) external pure returns(uint256) {
        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }



    function getAccountCollateralValue(
        address user
    ) public view returns (uint256 totalCollateralValueInUsd) {
        // Loop through each collateral token, get the amount they have deposited and map it to the price to get the USD value (probably separate function)
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            console.log("token: ", token);
            console.log("amount: ", amount);
            console.log("user: ", user);
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
    }

    
    
    
    
    function getUsdValue(
        address token,
        uint256 amount
    ) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_priceFeeds[token]
        );
        (, int256 price, , , ) = priceFeed.latestRoundData();
        // 1 ETH = $1000
        // Value returned by ChainLink will be 1000 * 1e8
        return
            ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION; // (((1000 * 1e8) * 1e10) * 1000 * 1e18) / 1e18 = 1000e18
    }


    
    
    
    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256){
        // 1 ETH == $2000 --> 1000$ worth of ETH == 1000 / 2000 = 0.5 ETH
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return (usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }



    function getAccountInformation(address user) external view returns (uint256 totalDscMinted, uint256 collateralValueInUsd) {
        (totalDscMinted, collateralValueInUsd) = _getAccountInformation(user);
    }



    function getCollateralDeposited(address user, address token) external view returns(uint256){
        return s_collateralDeposited[user][token];
    }

    function getDscMinted(address user) external view returns (uint256){
        return s_DSCMinted[user];
    }

    
    function getHealthfactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    } 

    // This function is temporal cause I needed to put it in the health factor to convert usd into ETH, this works in the case that one user 
    // can only deposit in one collateral token
    function getTokenAddressFromUser(address user) public view returns (address){
        address collateralAddress;
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            if (amount != 0) {
                collateralAddress = token;
            }
        }
        return collateralAddress;
    }


    function getAditionalFeedPrecision() public pure returns(uint256) {
        return ADDITIONAL_FEED_PRECISION;
    }

    function getPrecision() public pure returns(uint256) {
        return PRECISION;
    }

    function getLiquidationBonus() public pure returns(uint256) {
        return LIQUIDATION_BONUS;
    }
}
