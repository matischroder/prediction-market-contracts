// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./PredictionMarket.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MarketFactory is Ownable {
    address[] public markets;
    
    // Configuration for new markets
    address public immutable bettingToken;
    address public immutable priceFeed;
    address public immutable vrfCoordinator;
    bytes32 public immutable keyHash;
    uint64 public immutable subscriptionId;
    
    event MarketCreated(
        address indexed market,
        address indexed creator,
        string question,
        uint256 resolutionTime
    );
    
    constructor(
        address _bettingToken,
        address _priceFeed,
        address _vrfCoordinator,
        bytes32 _keyHash,
        uint64 _subscriptionId
    ) {
        bettingToken = _bettingToken;
        priceFeed = _priceFeed;
        vrfCoordinator = _vrfCoordinator;
        keyHash = _keyHash;
        subscriptionId = _subscriptionId;
    }
    
    function createMarket(
        string memory question,
        uint256 resolutionTime
    ) external returns (address) {
        require(resolutionTime > block.timestamp, "Resolution time must be in the future");
        
        PredictionMarket market = new PredictionMarket(
            msg.sender, // market creator becomes owner
            bettingToken,
            priceFeed,
            vrfCoordinator,
            keyHash,
            subscriptionId,
            question,
            resolutionTime
        );
        
        markets.push(address(market));
        
        emit MarketCreated(address(market), msg.sender, question, resolutionTime);
        
        return address(market);
    }
    
    function getMarketsCount() external view returns (uint256) {
        return markets.length;
    }
    
    function getAllMarkets() external view returns (address[] memory) {
        return markets;
    }
    
    function getMarketsByRange(uint256 start, uint256 end) external view returns (address[] memory) {
        require(start <= end && end < markets.length, "Invalid range");
        
        address[] memory result = new address[](end - start + 1);
        for (uint256 i = start; i <= end; i++) {
            result[i - start] = markets[i];
        }
        
        return result;
    }
}
