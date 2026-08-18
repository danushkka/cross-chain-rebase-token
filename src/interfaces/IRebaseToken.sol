// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

/**
 * @title IRebaseToken
 * @notice Interface for the RebaseToken contract.
 * Exposes mint, burn, and interest rate query functions
 * used by the Vault and RebaseTokenPool.
 */
interface IRebaseToken {
    /// @notice Mints tokens to an address with a specified interest rate
    function mint(address to, uint256 amount, uint256 userInterestRate) external;

    /// @notice Burns tokens from an address
    function burn(address from, uint256 amount) external;

    /// @notice Returns the current balance including accrued interest
    function balanceOf(address user) external view returns (uint256);

    /// @notice Returns the interest rate assigned to a specific user
    function getUserInterestRate(address user) external view returns (uint256);

    /// @notice Returns the current global interest rate
    function getInterestRate() external view returns (uint256);

    /// @notice Grants mint and burn role to an address
    function grantMintAndBurnRole(address _account) external;
}
