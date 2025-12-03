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
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";


/**
 * @title RebaseToken
 * @author João Lyra
 * @notice this is a cross-chain rebase token that incentivizes users to deposit into a vault
 * @notice the interest rate in the smart contract can only decrease
 * @notice each user will have their own interest rate that is the global interest rate at the time of the deposit
 */
contract RebaseToken is ERC20, Ownable, AccessControl {

    error RebaseToken__InterestRateCanOnlyDecrease(uint256 currentInterestRate, uint256 newInterestRate);

    uint256 private constant PRECISION_FACTOR = 1e18;
    bytes32 private constant MINT_AND_BURN_ROLE = keccak256("MINT_AND_BURN_ROLE");
    uint256 s_interestRate = 5e10;
    mapping(address => uint256) private s_userInterestRate;
    mapping(address => uint256) private s_userLastUpdatedTimestamp;

    event InterestRateSet(uint256 newInterestRate);

    constructor() ERC20("RebaseToken", "RBT") Ownable(msg.sender) {}
    
    function grantMintAndBurnRole(address _to) external onlyOwner {
        _grantRole(MINT_AND_BURN_ROLE, _to);
    }

    /*
     * @notice set the Interest Rate in the contract
     * @param _newInterestRate the new interest rate to be set
     * @dev the interest rate can only decrease
     */
    function setInterestRate (uint256 _newInterestRate) external onlyOwner {
        // Set the interest rate
        if (_newInterestRate < s_interestRate) {
            revert RebaseToken__InterestRateCanOnlyDecrease(s_interestRate, _newInterestRate);
        }
        s_interestRate = _newInterestRate;
        emit InterestRateSet(_newInterestRate);
    }

    /** 
     * @notice get the principle balance of a user (the amount of tokens that have actually been minted to the user, not     including any interest that has accrued since the last time the user interacted with the protocol)
     * @param _user the user to get the principle balance for
     * @return the principle balance of the user
     */
    function principleBalanceOf(address _user) external view returns (uint256) {
        return super.balanceOf(_user);
    }

    /**
     * @notice Mint the user tokens when they deposit into the vault
     * @param _to the address to mint the tokens to
     * @param _amount the amount of tokens to mint
     */
    function mint(address _to, uint256 _amount) external onlyRole(MINT_AND_BURN_ROLE){
        _mintAccruedInterest(_to);
        s_userInterestRate[_to] = s_interestRate;
        _mint(_to, _amount);
    }

    /**
     * @notice Burn the user tokens when they withdraw from the vault
     * @param _from the address to burn the tokens from
     * @param _amount the amount of tokens to burn
     */
    function burn(address _from, uint256 _amount) external onlyRole(MINT_AND_BURN_ROLE){
        if (_amount == type(uint256).max) { // mitagação de dust usada por protocolos como o Aave. Buscar entender
            _amount = balanceOf(_from);
        }
        _mintAccruedInterest(_from);
        _burn(_from, _amount);
    }

    /**
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

    /** 
     * @notice Transfer tokens from one user to another
     * @param _recipient the address to transfer the tokens to
     * @param _amount the amount of tokens to transfer 
     * @return true if the transfer was successful
     */
    function transfer(address _recipient, uint256 _amount) public override returns (bool) {
        _mintAccruedInterest(msg.sender);
        _mintAccruedInterest(_recipient);
        if (_amount == type(uint256).max) {
            _amount = balanceOf(msg.sender);
        }
        if (balanceOf(_recipient) == 0) {
            s_userInterestRate[_recipient] = s_userInterestRate[msg.sender];
        }
        return super.transfer(_recipient, _amount);
    }

    /**
     * @notice Transfer tokens from one user to another
     * @param _sender the address to transfer the tokens from
     * @param _recipient the address to transfer the tokens to
     * @param _amount the amount of tokens to transfer 
     * @return true if the transfer was successful
     */
    function transferFrom(address _sender, address _recipient, uint256 _amount) public override returns (bool) {
        _mintAccruedInterest(_sender);
        _mintAccruedInterest(_recipient);
        if (_amount == type(uint256).max) {
            _amount = balanceOf(_sender);
        }
        if (balanceOf(_recipient) == 0) {
            s_userInterestRate[_recipient] = s_userInterestRate[_sender];
        }
        return super.transferFrom(_sender, _recipient, _amount);
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
        uint256 timeElapsed = block.timestamp - s_userLastUpdatedTimestamp[_user];
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
    
        // calculate the number of tokens that need to be minted to the user -> (2) - (1)
        uint256 balanceIncrease = currentBalance - previousPrincipleBalance;
    
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

    /*
     * @notice Get the interest rate that is currently set for the contract. Any future depositers will receive this interest rate
     * @return the interest rate
     */
    function getInterestRate() external view returns (uint256) {
        return s_interestRate;
    }
}