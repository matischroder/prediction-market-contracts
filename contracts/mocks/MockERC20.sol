// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    uint8 private _decimals;

    // Faucet configuration
    uint256 public constant FAUCET_AMOUNT = 50 * 10 ** 6; // 50 USDC (6 decimals)
    mapping(address => uint256) public lastFaucetClaim;
    uint256 public constant FAUCET_COOLDOWN = 24 hours; // 24 hour cooldown

    event FaucetClaimed(address indexed user, uint256 amount);

    constructor(string memory name, string memory symbol, uint8 decimals_) ERC20(name, symbol) {
        _decimals = decimals_;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function claimFaucet() external {
        require(block.timestamp >= lastFaucetClaim[msg.sender] + FAUCET_COOLDOWN, "Faucet cooldown not expired");

        _mint(msg.sender, FAUCET_AMOUNT);
        lastFaucetClaim[msg.sender] = block.timestamp;

        emit FaucetClaimed(msg.sender, FAUCET_AMOUNT);
    }

    function canClaimFaucet(address user) external view returns (bool) {
        return block.timestamp >= lastFaucetClaim[user] + FAUCET_COOLDOWN;
    }

    function timeUntilNextClaim(address user) external view returns (uint256) {
        uint256 nextClaimTime = lastFaucetClaim[user] + FAUCET_COOLDOWN;
        if (block.timestamp >= nextClaimTime) {
            return 0;
        }
        return nextClaimTime - block.timestamp;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }
}
