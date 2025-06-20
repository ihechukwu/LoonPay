const { ethers, upgrades, network } = require("hardhat");
const { networkConfig } = require("../helper-hardhat-config");
require("dotenv").config();
async function main() {
  const USDC_ADDRESS = networkConfig[network.config.chainId]["USDC_ADDRESS"];

  const [deployer] = await ethers.getSigners();
  const trustedBackend = deployer.address;
  const LoonPay = await ethers.getContractFactory("LoonPay");

  const loonpay = await upgrades.deployProxy(
    LoonPay,
    [USDC_ADDRESS, trustedBackend],
    { initializer: "initialize" }
  );
  await loonpay.waitForDeployment();

  console.log("LoonPay deployed to", await loonpay.getAddress());
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
