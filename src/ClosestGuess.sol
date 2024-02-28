// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
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

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {VRFCoordinatorV2Interface} from "lib/chainlink/contracts/src/v0.8/vrf/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "lib/chainlink/contracts/src/v0.8/vrf/VRFConsumerBaseV2.sol";
import {AutomationCompatibleInterface} from "lib/chainlink/contracts/src/v0.8/automation/interfaces/AutomationCompatibleInterface.sol";

/**@title ClosestGuess
 * @author limited scope
 * @notice This contract is for creating a guessing game that awards the nearest guess
 * @dev This implements the Chainlink VRF Version 2
 */
contract Raffle is VRFConsumerBaseV2, AutomationCompatibleInterface {
    /* Errors */
    error Raffle__UpkeepNotNeeded(
        uint256 currentBalance,
        uint256 numPlayers,
        uint256 raffleState
    );
    error Raffle__TransferFailed();
    error Raffle__SendMoreToEnterRaffle();
    error Raffle__RaffleNotOpen();

    /* Type declarations */
    enum RaffleState {
        OPEN,
        CALCULATING
    }
    /* State variables */
    // Chainlink VRF Variables
    VRFCoordinatorV2Interface private immutable i_vrfCoordinator;
    uint64 private immutable i_subscriptionId;
    bytes32 private immutable i_gasLane;
    uint32 private immutable i_callbackGasLimit;
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;

    // Lottery Variables
    uint256 private immutable i_interval;
    uint256 private immutable i_entranceFee;
    uint256 private s_lastTimeStamp;
    address private s_recentWinner;
    address payable[] private s_players;
    RaffleState private s_raffleState;
    uint256 public divisor;
    // uint256 public s_playerGuesses;
    mapping(address => uint256) s_playerGuesses;
    /* Events */
    event RequestedRaffleWinner(uint256 indexed requestId);
    // event RaffleEnter(address indexed player);
    event WinnerPicked(address indexed player);
    event RaffleEnter(address indexed player, uint256 guessedNumber);

    struct RequestStatus {
        uint256 paid; // amount paid in link
        bool fulfilled; // whether the request has been successfully fulfilled
        uint256[] randomWords;
    }
    mapping(uint256 => RequestStatus)
        public s_requests; /* requestId --> requestStatus */

    // past requests Id.
    uint256[] public requestIds;
    uint256 public lastRequestId;

    /* Functions */
    constructor(
        uint64 subscriptionId,
        bytes32 gasLane, // keyHash
        uint256 interval,
        uint256 entranceFee,
        uint32 callbackGasLimit,
        address vrfCoordinatorV2
    ) VRFConsumerBaseV2(vrfCoordinatorV2) {
        i_vrfCoordinator = VRFCoordinatorV2Interface(vrfCoordinatorV2);
        i_gasLane = gasLane;
        i_interval = interval;
        i_subscriptionId = subscriptionId;
        i_entranceFee = entranceFee;
        s_raffleState = RaffleState.OPEN;
        s_lastTimeStamp = block.timestamp;
        i_callbackGasLimit = callbackGasLimit;
        uint256 balance = address(this).balance;
        if (balance > 0) {
            payable(msg.sender).transfer(balance);
        }
    }

    function enterRaffle(uint256 guessedNumber) public payable {
        // Ensure enough value is sent as entrance fee
        require(msg.value >= i_entranceFee, "Insufficient value sent");

        // Ensure the raffle is open
        require(s_raffleState == RaffleState.OPEN, "Raffle is not open");

        // Add the sender to the list of players
        s_players.push(payable(msg.sender));

        // Store the guessed number for the player
        s_playerGuesses[msg.sender] = guessedNumber;

        // Emit an event to indicate that the player entered the raffle
        emit RaffleEnter(msg.sender, guessedNumber);
    }

    /**
     * @dev This is the function that the Chainlink Keeper nodes call
     * they look for `upkeepNeeded` to return True.
     * the following should be true for this to return true:
     * 1. The time interval has passed between raffle runs.
     * 2. The lottery is open.
     * 3. The contract has ETH.
     * 4. Implicity, your subscription is funded with LINK.
     */
    function checkUpkeep(
        bytes memory /* checkData */
    )
        public
        view
        override
        returns (bool upkeepNeeded, bytes memory /* performData */)
    {
        bool isOpen = RaffleState.OPEN == s_raffleState;
        bool timePassed = ((block.timestamp - s_lastTimeStamp) > i_interval);
        bool hasPlayers = s_players.length > 0;
        bool hasBalance = address(this).balance > 0;
        upkeepNeeded = (timePassed && isOpen && hasBalance && hasPlayers);
        return (upkeepNeeded, "0x0"); // can we comment this out?
    }

    /**
     * @dev Once `checkUpkeep` is returning `true`, this function is called
     * and it kicks off a Chainlink VRF call to get a random winner.
     */
    function performUpkeep(bytes calldata /* performData */) external override {
        (bool upkeepNeeded, ) = checkUpkeep("");
        // require(upkeepNeeded, "Upkeep not needed");
        if (!upkeepNeeded) {
            revert Raffle__UpkeepNotNeeded(
                address(this).balance,
                s_players.length,
                uint256(s_raffleState)
            );
        }
        s_raffleState = RaffleState.CALCULATING;
        uint256 requestId = i_vrfCoordinator.requestRandomWords(
            i_gasLane,
            i_subscriptionId,
            REQUEST_CONFIRMATIONS,
            i_callbackGasLimit,
            NUM_WORDS
        );
        // Quiz... is this redundant?
        emit RequestedRaffleWinner(requestId);
    }

    /**
     * @dev This is the function that Chainlink VRF node
     * calls to send the money to the random winner.
     */

    function fulfillRandomWords(
        uint256 requestId,
        uint256[] memory randomWords
    ) internal override {
        require(s_players.length > 0, "No players in the raffle");

        // Initialize variables to track the closest player and their difference
        uint256 closestDifference = type(uint256).max; // Max value of uint256
        address payable closestPlayer;

        // Iterate through each player to find the closest one
        for (uint256 i = 0; i < s_players.length; i++) {
            // Calculate the absolute difference between the player's guess and the random number
            uint256 difference;
            if (randomWords[0] > s_playerGuesses[s_players[i]]) {
                difference = randomWords[0] - s_playerGuesses[s_players[i]];
            } else {
                difference = s_playerGuesses[s_players[i]] - randomWords[0];
            }

            // Check if this player's difference is smaller than the current closest difference
            if (difference < closestDifference) {
                closestDifference = difference;
                closestPlayer = s_players[i];
            }
        }

        // Set the closest player as the winner
        address payable recentWinner = closestPlayer;

        // Update state variables
        s_recentWinner = recentWinner;
        s_players = new address payable[](0);
        s_raffleState = RaffleState.OPEN;
        s_lastTimeStamp = block.timestamp;

        // Emit winner picked event
        emit WinnerPicked(recentWinner);

        // Transfer contract balance to the winner
        (bool success, ) = recentWinner.call{value: address(this).balance}("");
        require(success, "Transfer failed");
    }

    /** Getter Functions */

    function getRaffleState() public view returns (RaffleState) {
        return s_raffleState;
    }

    function getNumWords() public pure returns (uint256) {
        return NUM_WORDS;
    }

    function getRequestConfirmations() public pure returns (uint256) {
        return REQUEST_CONFIRMATIONS;
    }

    function getRecentWinner() public view returns (address) {
        return s_recentWinner;
    }

    function getPlayer(uint256 index) public view returns (address) {
        return s_players[index];
    }

    function getLastTimeStamp() public view returns (uint256) {
        return s_lastTimeStamp;
    }

    function getInterval() public view returns (uint256) {
        return i_interval;
    }

    function getEntranceFee() public view returns (uint256) {
        return i_entranceFee;
    }

    function getNumberOfPlayers() public view returns (uint256) {
        return s_players.length;
    }
}
