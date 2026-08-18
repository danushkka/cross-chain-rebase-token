// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title RebaseToken
 * @author daniko
 * @notice A cross-chain rebase token that incentivises users to hold the tokens
 * by gaining profit from the growth of their deposits via Interest Rate.
 * @notice The Interest Rate can only decrease, which rewards early adopters
 * @notice Each user will have their own Interest Rate in accordance with the Interest Rate at the time they deposited
 */
contract RebaseToken is ERC20, Ownable, AccessControl {
    ////////////////////////////////////
    ////////////// ERRORS //////////////
    ////////////////////////////////////

    error RebaseToken__InterestRateShouldAlwaysDecrease(uint256 newInterestRate, uint256 currentInterestRate);
    error RebaseToken__MustBeMoreThanZero();
    error RebaseToken__TransferFailed();

    ////////////////////////////////////
    ///////// STATE VARIABLES //////////
    ////////////////////////////////////

    /// @notice Scaling factor for fixed-point interest calculations
    uint256 private constant PRECISION = 1e18;

    /// @notice Role identifier for addresses permitted to mint and burn tokens
    bytes32 public constant MINT_AND_BURN_ROLE = keccak256("MINT_AND_BURN_ROLE");

    uint256 private s_interestRate = 3e9; // 0.000000003% per second, which is approximately 10% per year
    mapping(address => uint256) private s_userInterestRate;
    mapping(address => uint256) private s_userLastUpdatedTimestamp;

    ////////////////////////////////////
    ////////////// EVENTS //////////////
    ////////////////////////////////////

    event InterestRateUpdated(uint256 newInterestRate);

    ////////////////////////////////////
    //////////// MODIFIERS /////////////
    ////////////////////////////////////

    modifier moreThanZero(uint256 _amount) {
        _moreThanZero(_amount);
        _;
    }

    function _moreThanZero(uint256 _amount) internal pure {
        if (_amount == 0) {
            revert RebaseToken__MustBeMoreThanZero();
        }
    }
    ////////////////////////////////////
    //////////// FUNCTIONS /////////////
    ////////////////////////////////////

    constructor() ERC20("My Rebase Token", "myRBT") Ownable(msg.sender) {}

    ////////////////////////////////////
    /////// PUBLIC AND EXTERNAL ////////
    ////////////////////////////////////

    /**
     * @notice Grants the MINT_AND_BURN_ROLE to an address
     * @param _user The address to grant the role to
     */
    function grantMintAndBurnRole(address _user) external onlyOwner {
        _grantRole(MINT_AND_BURN_ROLE, _user);
    }

    /**
     * @notice Updates the Interest Rate
     * @param _newInterestRate The new Interest Rate to be set
     * @dev The new Interest Rate must be less than the current Interest Rate
     */
    function updateInterestRate(uint256 _newInterestRate) external onlyOwner {
        if (_newInterestRate >= s_interestRate) {
            revert RebaseToken__InterestRateShouldAlwaysDecrease(_newInterestRate, s_interestRate);
        }
        s_interestRate = _newInterestRate;
        emit InterestRateUpdated(_newInterestRate);
    }

    /**
     * @notice Mints tokens to a specified address and sets the user's Interest Rate
     * @param _to The address to mint tokens to
     * @param _amountToMint The amount of tokens to mint
     * @dev The user's Interest Rate is set to the current Interest Rate at the time of minting
     */
    function mint(address _to, uint256 _amountToMint, uint256 _userInterestRate)
        external
        onlyRole(MINT_AND_BURN_ROLE)
        moreThanZero(_amountToMint)
    {
        _mintAccruedInterest(_to);
        s_userInterestRate[_to] = _userInterestRate;
        _mint(_to, _amountToMint);
    }

    /**
     * @notice Burns tokens from a specified address and updates the user's Interest Rate
     * @param _from The address to burn tokens from
     * @param _amountToBurn The amount of tokens to burn
     * @dev The user's Interest Rate is updated to the current Interest Rate at the time of burning
     */
    function burn(address _from, uint256 _amountToBurn)
        external
        onlyRole(MINT_AND_BURN_ROLE)
        moreThanZero(_amountToBurn)
    {
        if (_amountToBurn == type(uint256).max) {
            _amountToBurn = balanceOf(_from);
        }
        _mintAccruedInterest(_from);
        _burn(_from, _amountToBurn);
    }

    /**
     * @notice Overrides the balanceOf function to include the accumulated interest
     * @param _user The address of the user to get the balance for
     * @return The balance of the user including the accumulated interest
     */
    function balanceOf(address _user) public view override returns (uint256) {
        return (super.balanceOf(_user) * _calculateAccumulatedInterestSinceLastUpdate(_user)) / PRECISION;
    }

    /**
     * @notice Overrides the transfer function to include interest calculations
     * @param _recipient The address of the recipient
     * @param _amountToTransfer The amount of tokens to transfer
     * @dev If the recipient has a balance of 0, their Interest Rate is set to the sender's Interest Rate
     * @return A boolean indicating whether the transfer was successful
     */
    function transfer(address _recipient, uint256 _amountToTransfer)
        public
        override
        moreThanZero(_amountToTransfer)
        returns (bool)
    {
        _mintAccruedInterest(msg.sender);
        _mintAccruedInterest(_recipient);
        if (balanceOf(_recipient) == 0) {
            s_userInterestRate[_recipient] = s_userInterestRate[msg.sender];
        }

        return super.transfer(_recipient, _amountToTransfer);
    }

    /**
     * @notice Overrides the transferFrom function to include interest calculations
     * @param _sender The address of the sender
     * @param _recipient The address of the recipient
     * @param _amountToTransfer The amount of tokens to transfer
     * @dev If the recipient has a balance of 0, their Interest Rate is set to the sender's Interest Rate
     * @return A boolean indicating whether the transfer was successful
     */
    function transferFrom(address _sender, address _recipient, uint256 _amountToTransfer)
        public
        override
        moreThanZero(_amountToTransfer)
        returns (bool)
    {
        _mintAccruedInterest(_sender);
        _mintAccruedInterest(_recipient);
        if (balanceOf(_recipient) == 0) {
            s_userInterestRate[_recipient] = s_userInterestRate[_sender];
        }

        return super.transferFrom(_sender, _recipient, _amountToTransfer);
    }

    ////////////////////////////////////
    /////// PRIVATE AND INTERNAL ///////
    ////////////////////////////////////

    /**
     * @notice Mints the accrued interest for a user since the last interaction with the protocol
     * @param _user The address of the user to mint Interest for
     */
    function _mintAccruedInterest(address _user) internal {
        uint256 interestToMint = balanceOf(_user) - super.balanceOf(_user);
        s_userLastUpdatedTimestamp[_user] = block.timestamp;

        if (interestToMint > 0) {
            _mint(_user, interestToMint);
        }
    }

    /**
     * @notice Calculates the accumulated interest for a user since the last update
     * @param _user The address of the user to calculate interest for
     * @return The accumulated interest for the user since the last update
     */
    function _calculateAccumulatedInterestSinceLastUpdate(address _user) internal view returns (uint256) {
        uint256 timeElapsed = block.timestamp - s_userLastUpdatedTimestamp[_user];

        return (PRECISION + (timeElapsed * s_userInterestRate[_user]));
    }

    ////////////////////////////////////
    ///////////// GETTERS //////////////
    ////////////////////////////////////

    /**
     * @notice Gets the global Interest Rate, which is the Interest Rate for new users
     * who interact with the protocol for the first time
     * @return The global Interest Rate
     */
    function getInterestRate() external view returns (uint256) {
        return s_interestRate;
    }

    /**
     * @notice Gets the principle balance of a user (the balance without interest)
     * @param _user The address of the user to get the principle balance of
     * @return The principle balance of the user
     */
    function getPrincipleBalanceOf(address _user) external view returns (uint256) {
        return super.balanceOf(_user);
    }

    /**
     * @notice Gets the accumulated Interest of a user since their last interaction (e.g mint, burn, deposit etc.)
     * @param _user The address of the user to get the accumulated Interest of
     * @return The accumulated Interest of the user
     */
    function getAccumulatedInterestSinceLastInteraction(address _user) external view returns (uint256) {
        return _calculateAccumulatedInterestSinceLastUpdate(_user);
    }

    /**
     * @notice Gets the current Interest Rate for a user
     * @param _user The address of the user to get the Interest Rate of
     * @return The current Interest Rate
     */
    function getUserInterestRate(address _user) external view returns (uint256) {
        return s_userInterestRate[_user];
    }
}
