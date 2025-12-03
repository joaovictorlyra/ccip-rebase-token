// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {IRebaseToken} from "./interfaces/IRebaseToken.sol";

contract Vault {
    // we need to pass the token address in the constructor
    // create a deposit function that mints tokens from the user equal to the amount of ETH the user deposited
    // create a redeem function that burns tokens from the user and sends the user ETH
    // create a way to add rewards to the vault

    IRebaseToken private immutable i_rebaseToken;

    event Deposit(address indexed user, uint256 amount);
    event Redeem(address indexed user, uint256 amount);

    error Vault__RedeemFailed();

    constructor(IRebaseToken _rebaseToken) {
        i_rebaseToken = _rebaseToken;
    }

    receive() external payable {}

    /**
     * @notice Deposits ETH and mints corresponding tokens to the sender
     */
    function deposit() external payable {
        // we need to use the amount of ETH sent to the contract to mint tokens to the user
        i_rebaseToken.mint(msg.sender, msg.value);
        emit Deposit(msg.sender, msg.value);
    }

    /**
     * @notice Redeems tokens for ETH by burning the tokens from the sender
     * @param _amount The amount of tokens to redeem
     */
    function redeem(uint256 _amount) external {
        // burn the user's tokens
        i_rebaseToken.burn(msg.sender, _amount);
        // send the user ETH
        // payable(msg.sender).transfer(_amount);
        (bool success, ) = payable(msg.sender).call{value: _amount}("");
        if (!success) {
            revert Vault__RedeemFailed();
        }
        emit Redeem(msg.sender, _amount);
    }

    /**
     * @notice Get the address of the RebaseToken contract
     * @return the address of the RebaseToken contract
     */
    function getRebaseTokenAddress() external view returns (address) {
        return address(i_rebaseToken);
    }
}