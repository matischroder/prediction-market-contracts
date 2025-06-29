import { ethers } from "hardhat";
import { parseEther } from "ethers";
import * as fs from "fs";
import * as path from "path";

// Leer direcciones desde deployed-addresses.json
function loadDeployedAddresses() {
    const addressesPath = path.join(__dirname, "../deployed-addresses.json");

    if (!fs.existsSync(addressesPath)) {
        throw new Error("❌ deployed-addresses.json not found. Please deploy contracts first.");
    }

    const addresses = JSON.parse(fs.readFileSync(addressesPath, "utf8"));
    return addresses;
}

async function main() {
    console.log("💰 Starting factory funding...");

    // Load deployed addresses
    console.log("📖 Loading deployed contract addresses...");
    const deployedAddresses = loadDeployedAddresses();

    // Get signer
    const [deployer] = await ethers.getSigners();
    console.log("📝 Funding from account:", deployer.address);

    // Contract addresses from deployed-addresses.json
    const MARKET_FACTORY = deployedAddresses.contracts.marketFactory;
    const LINK_TOKEN = deployedAddresses.chainlink.LINK_TOKEN;

    console.log(`🌐 Network: ${deployedAddresses.network} (Chain ID: ${deployedAddresses.chainId})`);
    console.log("🏭 MarketFactory address:", MARKET_FACTORY);
    console.log("🔗 LINK token address:", LINK_TOKEN);

    if (!MARKET_FACTORY || !LINK_TOKEN) {
        throw new Error("❌ Contract addresses not found in deployed-addresses.json");
    }

    // Funding amounts
    const ETH_AMOUNT = parseEther("0.1"); // 0.1 ETH
    const LINK_AMOUNT = parseEther("2"); // 2 LINK tokens

    try {
        // Get contracts
        const marketFactory = await ethers.getContractAt("MarketFactory", MARKET_FACTORY);
        const linkToken = await ethers.getContractAt("IERC20", LINK_TOKEN);

        // Check deployer balances
        const deployerEthBalance = await ethers.provider.getBalance(deployer.address);
        const deployerLinkBalance = await linkToken.balanceOf(deployer.address);

        console.log("\n📊 Current balances:");
        console.log("ETH balance:", ethers.formatEther(deployerEthBalance), "ETH");
        console.log("LINK balance:", ethers.formatEther(deployerLinkBalance), "LINK");

        // Check if we have enough balance
        if (deployerEthBalance < ETH_AMOUNT) {
            throw new Error(`Insufficient ETH balance. Need ${ethers.formatEther(ETH_AMOUNT)} ETH`);
        }

        if (deployerLinkBalance < LINK_AMOUNT) {
            throw new Error(`Insufficient LINK balance. Need ${ethers.formatEther(LINK_AMOUNT)} LINK`);
        }

        // Check current factory balances
        const factoryEthBalance = await marketFactory.ethBalance();
        const factoryLinkBalance = await marketFactory.linkBalance();

        console.log("\n🏭 Current factory balances:");
        console.log("ETH balance:", ethers.formatEther(factoryEthBalance), "ETH");
        console.log("LINK balance:", ethers.formatEther(factoryLinkBalance), "LINK");

        // Deposit ETH to factory
        console.log("\n💸 Depositing ETH to factory...");
        const ethTx = await marketFactory.depositETH({ value: ETH_AMOUNT });
        console.log("⏳ Transaction hash:", ethTx.hash);
        await ethTx.wait();
        console.log("✅ ETH deposited successfully!");

        // Approve LINK for factory
        console.log("\n🔓 Approving LINK for factory...");
        const approveTx = await linkToken.approve(MARKET_FACTORY, LINK_AMOUNT);
        console.log("⏳ Approval transaction hash:", approveTx.hash);
        await approveTx.wait();
        console.log("✅ LINK approved!");

        // Deposit LINK to factory
        console.log("\n🔗 Depositing LINK to factory...");
        const linkTx = await marketFactory.depositLINK(LINK_AMOUNT);
        console.log("⏳ Transaction hash:", linkTx.hash);
        await linkTx.wait();
        console.log("✅ LINK deposited successfully!");

        // Check final factory balances
        const finalFactoryEthBalance = await marketFactory.ethBalance();
        const finalFactoryLinkBalance = await marketFactory.linkBalance();

        console.log("\n🎉 Final factory balances:");
        console.log("ETH balance:", ethers.formatEther(finalFactoryEthBalance), "ETH");
        console.log("LINK balance:", ethers.formatEther(finalFactoryLinkBalance), "LINK");

        console.log("\n✅ Factory funding completed successfully!");
        console.log("🚀 The factory is now ready to create and fund markets!");
    } catch (error: any) {
        console.error("❌ Funding failed:", error.message);

        if (error.message.includes("Insufficient")) {
            console.log("\n💡 Tips to get tokens:");
            console.log("📍 For Sepolia ETH: https://sepoliafaucet.com/");
            console.log("📍 For Sepolia LINK: https://faucets.chain.link/sepolia");
        }

        process.exit(1);
    }
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });
