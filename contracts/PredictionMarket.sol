// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/vrf/VRFConsumerBaseV2.sol";
import "./interfaces/IPredictionMarket.sol";

contract PredictionMarket is IPredictionMarket, Ownable, VRFConsumerBaseV2 {
    IERC20 public immutable bettingToken;
    AggregatorV3Interface public immutable priceFeed;
    VRFCoordinatorV2Interface public immutable vrfCoordinator;
    
    string public question;
    uint256 public resolutionTime;
    uint256 public totalYesBets;
    uint256 public totalNoBets;
    bool public isResolved;
    bool public outcome;
    
    // VRF Configuration
    bytes32 public immutable keyHash;
    uint64 public immutable subscriptionId;
    uint32 public constant CALLBACK_GAS_LIMIT = 100000;
    uint16 public constant REQUEST_CONFIRMATIONS = 3;
    
    mapping(address => uint256) public yesBets;
    mapping(address => uint256) public noBets;
    mapping(address => bool) public hasClaimed;
    
    address public bonusWinner;
    uint256 public bonusAmount;
    
    event BetPlaced(address indexed user, bool position, uint256 amount);
    event MarketResolved(bool outcome);
    event PrizeClaimed(address indexed user, uint256 amount);
    event BonusWinnerSelected(address indexed winner, uint256 amount);
    
    constructor(
        address _owner,
        address _bettingToken,
        address _priceFeed,
        address _vrfCoordinator,
        bytes32 _keyHash,
        uint64 _subscriptionId,
        string memory _question,
        uint256 _resolutionTime
    ) VRFConsumerBaseV2(_vrfCoordinator) {
        _transferOwnership(_owner);
        bettingToken = IERC20(_bettingToken);
        priceFeed = AggregatorV3Interface(_priceFeed);
        vrfCoordinator = VRFCoordinatorV2Interface(_vrfCoordinator);
        keyHash = _keyHash;
        subscriptionId = _subscriptionId;
        question = _question;
        resolutionTime = _resolutionTime;
    }
    
    function placeBet(bool position, uint256 amount) external override {
        require(block.timestamp < resolutionTime, "Market closed");
        require(!isResolved, "Market already resolved");
        require(amount > 0, "Amount must be greater than 0");
        
        bettingToken.transferFrom(msg.sender, address(this), amount);
        
        if (position) {
            yesBets[msg.sender] += amount;
            totalYesBets += amount;
        } else {
            noBets[msg.sender] += amount;
            totalNoBets += amount;
        }
        
        emit BetPlaced(msg.sender, position, amount);
    }
    
    function resolveMarket() external override onlyOwner {
        require(block.timestamp >= resolutionTime, "Too early to resolve");
        require(!isResolved, "Already resolved");
        
        // Get price from Chainlink feed to determine outcome
        (, int256 price, , , ) = priceFeed.latestRoundData();
        
        // Simple example: if price > 50000 (for ETH/USD), outcome is true
        outcome = price > 50000 * 10**8; // Adjust threshold as needed
        isResolved = true;
        
        // Calculate bonus amount (1% of total pool)
        bonusAmount = (totalYesBets + totalNoBets) / 100;
        
        // Request random number for bonus winner
        if (bonusAmount > 0) {
            vrfCoordinator.requestRandomWords(
                keyHash,
                subscriptionId,
                REQUEST_CONFIRMATIONS,
                CALLBACK_GAS_LIMIT,
                1
            );
        }
        
        emit MarketResolved(outcome);
    }
    
    function fulfillRandomWords(uint256, uint256[] memory randomWords) internal override {
        if (bonusAmount == 0) return;
        
        // Get list of winning bettors
        uint256 totalWinningBets = outcome ? totalYesBets : totalNoBets;
        if (totalWinningBets == 0) return;
        
        // Simple random selection (in production, would need more sophisticated approach)
        uint256 randomIndex = randomWords[0] % totalWinningBets;
        
        // For simplicity, we'll award bonus to contract owner
        // In production, implement proper winner selection
        bonusWinner = owner();
        
        emit BonusWinnerSelected(bonusWinner, bonusAmount);
    }
    
    function claimPrize() external override {
        require(isResolved, "Market not resolved");
        require(!hasClaimed[msg.sender], "Already claimed");
        
        uint256 userBet = outcome ? yesBets[msg.sender] : noBets[msg.sender];
        require(userBet > 0, "No winning bet");
        
        uint256 totalWinningBets = outcome ? totalYesBets : totalNoBets;
        uint256 totalPool = totalYesBets + totalNoBets;
        
        // Calculate prize share
        uint256 prize = (userBet * totalPool) / totalWinningBets;
        
        // Add bonus if user is the bonus winner
        if (msg.sender == bonusWinner && bonusAmount > 0) {
            prize += bonusAmount;
            bonusAmount = 0; // Prevent double claiming
        }
        
        hasClaimed[msg.sender] = true;
        bettingToken.transfer(msg.sender, prize);
        
        emit PrizeClaimed(msg.sender, prize);
    }
    
    function getCurrentOdds() external view override returns (uint256 yesOdds, uint256 noOdds) {
        uint256 totalPool = totalYesBets + totalNoBets;
        if (totalPool == 0) {
            return (5000, 5000); // 50/50 if no bets
        }
        
        yesOdds = (totalNoBets * 10000) / totalPool;
        noOdds = (totalYesBets * 10000) / totalPool;
    }
    
    function getMarketInfo() external view returns (
        string memory _question,
        uint256 _resolutionTime,
        uint256 _totalYesBets,
        uint256 _totalNoBets,
        bool _isResolved,
        bool _outcome
    ) {
        return (question, resolutionTime, totalYesBets, totalNoBets, isResolved, outcome);
    }
}
