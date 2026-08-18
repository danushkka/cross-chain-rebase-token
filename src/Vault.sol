// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {IRebaseToken} from "./interfaces/IRebaseToken.sol";

contract Vault {
    ////////////////////////////////////
    ////////////// ERRORS //////////////
    ////////////////////////////////////

    error Vault__RedeemFailed();

    ////////////////////////////////////
    ///////// STATE VARIABLES //////////
    ////////////////////////////////////

    IRebaseToken public immutable i_rebaseToken;

    ////////////////////////////////////
    ////////////// EVENTS //////////////
    ////////////////////////////////////

    event Deposit(address indexed user, uint256 amount);
    event Redeem(address indexed user, uint256 amount);

    ////////////////////////////////////
    //////////// FUNCTIONS /////////////
    ////////////////////////////////////

    constructor(IRebaseToken _rebaseToken) {
        i_rebaseToken = _rebaseToken;
    }

    /**
     * @notice Accepts plain ETH transfers. Does NOT mint rebase tokens.
     * @dev To receive rebase tokens, call deposit() instead.
     */
    receive() external payable {}

    /**
     * @notice Deposits ETH into the vault and mints rebase tokens in return
     */
    function deposit() external payable {
        uint256 userInterestRate = i_rebaseToken.getInterestRate();
        i_rebaseToken.mint(msg.sender, msg.value, userInterestRate);
        emit Deposit(msg.sender, msg.value);
    }

    /**
     * @notice Redeems rebase tokens for ETH
     * @param _amountToRedeem The amount of tokens to redeem
     */
    function redeem(uint256 _amountToRedeem) external {
        if (_amountToRedeem == type(uint256).max) {
            _amountToRedeem = i_rebaseToken.balanceOf(msg.sender);
        }

        i_rebaseToken.burn(msg.sender, _amountToRedeem);
        (bool success,) = msg.sender.call{value: _amountToRedeem}("");
        if (!success) {
            revert Vault__RedeemFailed();
        }

        emit Redeem(msg.sender, _amountToRedeem);
    }

    /**
     * @notice Gets the address of the Rebase token contract
     * @return The address of the Rebase token contract
     */
    function getRebaseToken() external view returns (address) {
        return address(i_rebaseToken);
    }
}
