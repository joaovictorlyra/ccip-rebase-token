// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

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

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";


/*
 * @title RebaseToken
 * @author João Lyra
 * @notice this is a cross-chain rebase token that incentivizes users to deposit into a vault
 * @notice the interest rate in the smart contract can only decrease
 * @notice each user will have their own interest rate that is the global interest rate at the time of the deposit
 */
contract RebaseToken is ERC20 {

    error RebaseTokenInterestRateCanOnlyDecrease();

    uint256 private constant PRECISION_FACTOR = 1e18;
    uint256 s_interestRate = 5e10;
    mapping(address => uint256) private s_userInterestRate;
    mapping(address => uint256) private s_userLastUpdateTimeStamp;

    event InterestRateSet(uint256 newInterestRate);

    constructor() ERC20("RebaseToken", "RBT") {
        _mint(msg.sender, 1000 * 10 ** decimals());
    }

    /*
     * @notice set the Interest Rate in the contract
     * @param _newInterestRate the new interest rate to be set
     * @dev the interest rate can only decrease
     */
    function setInterestRate (uint256 _newInterestRate) external {
        // Set the interest rate
        if (_newInterestRate < s_interestRate) {
            revert RebaseToken__InterestRateCanOnlyDecrease(s_interestRate, _newInterestRate);
        }
        s_interestRate = _newInterestRate;
        emit InterestRateSet(_newInterestRate);
    }

    /*
     * @notice Mint the user tokens when they deposit into the vault
     * @param _to the address to mint the tokens to
     * @param _amount the amount of tokens to mint
     */
    function mint(address _to, uint256 _amount) external {
        _mintAccruedInterest(_to);
        s_userInterestRate[_to] = s_interestRate;
        _mint(_to, _amount);
    }

    /*
     * @notice Burn the user tokens when they withdraw from the vault
     * @param _from the address to burn the tokens from
     * @param _amount the amount of tokens to burn
     */
    function burn(address _from, uint256 _amount) external {
        if (_amount == type(uint256).max) { // mitagação de dust usada por protocolos como o Aave. Buscar entender
            _amount = balanceOf(_from);
        }
        _mintAccruedInterest(_from);
        _burn(_from, _amount);
    }

    /*
     * @notice calculate the balance for the user including the interest that has accumulated since the last update
     * (principle balance + some interest that has accrued)
     * @param _user the user to calculate the balance for
     * @return the balance of the user including the interest that has accumulated since the last update
     */
    function balanceOf(address _user) public view override returns (uint256) {
        // get the current principle balance of the user (the number of tokens that have actually been minted to the user)
        // multiply the principle balance by the interest that has accumulated since the last update
        return super.balanceOf(_user) * _calculateUserAccumalatedInterestSinceLastUpdate(_user) / PRECISION_FACTOR;
    }

    function _calculateUserAccumalatedInterestSinceLastUpdate(address _user) internal view returns (uint256 linearInterest) {
        // we need to calculate the interest that has accumulated since the last update
        // this is going to be linear growth with time
        // 1. calculate the time since the last update
        // 2. calculate the amount of linear growth
        // deposit 10 tokens
        // interest rate is 0.5 tokens per second
        // time elapsed is 2 seconds
        // 10 + (10 * 0.5 * 2) = 20 tokens
        uint256 timeElapsed = block.timestamp - s_userLastUpdateTimeStamp[_user];
        linearInterest = PRECISION_FACTOR + (s_userInterestRate[_user] * timeElapsed);

    }

    /**
    * @notice Mint the accrued interest to the user since the last time they interacted with the protocol (e.g. burn, mint, transfer)
    * @param _user The user to mint the accrued interest to
    */
    function _mintAccruedInterest(address _user) internal {
        // (1) find their current balance of rebase tokens that have been minted to the user -> principle balance
        uint256 previousPrincipleBalance = super.balanceOf(_user);
        // (2) calculate their current balance including any interest -> balanceOf
        uint256 currentBalance = balanceOf(_user);
    ​
        // calculate the number of tokens that need to be minted to the user -> (2) - (1)
        uint256 balanceIncrease = currentBalance - previousPrincipleBalance;
    ​
        // set the users last updated timestamp (Effect)
        s_userLastUpdatedTimestamp[_user] = block.timestamp;
        
        // Mint the accrued interest (Interaction)
        if (balanceIncrease > 0) { // Optimization: only mint if there's interest
            _mint(_user, balanceIncrease);
        }
    }

    /*
     * @notice Get the interest rate of a user
     * @param _user the user to get the interest rate for
     * @return the interest rate of the user
     */
    function getUserInterestRate(address _user) external view returns (uint256) {
        return s_userInterestRate[_user];
    }

}