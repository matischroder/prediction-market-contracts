// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IPredictionMarket {
    function placeBet(uint256 amount, bool isHigher) external;
    function claimPayout(uint256 betIndex) external;
    function claimBonusReward() external;
    function resolveMarket() external;
    function getCurrentPrice() external view returns (uint256);
    function canUserClaim(address user, uint256 betIndex) external view returns (bool);
    function canClaimBonus(address user) external view returns (bool);
    
    // Enhanced functionality
    function getMarketInfo() external view returns (
        string memory assetName,
        string memory baseAsset,
        uint256 targetPrice,
        uint256 resolutionTime,
        bool resolved,
        bool outcome,
        uint256 finalPrice,
        uint256 totalPool,
        uint256 totalHigherBets,
        uint256 totalLowerBets
    );
    
    function getUserBetCount(address user) external view returns (uint256);
    function getUserBet(address user, uint256 index) external view returns (
        uint256 amount,
        bool isHigher,
        bool claimed,
        uint256 payout
    );
    
    function getBetCount() external view returns (uint256);
    function getRandomWinner() external view returns (address);
    function isRandomWinnerSelected() external view returns (bool);
}
