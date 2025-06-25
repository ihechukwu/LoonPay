const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");
const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");

describe("LoonPay contract", function () {
  async function deployLoonPayFixtures() {
    const [owner, backend, user1, user2] = await ethers.getSigners();

    // deploy mock
    const Mock = await ethers.getContractFactory("ERC20Mock");
    const usdc = await Mock.deploy("USDC", "USDC");
    await usdc.mint(owner.address, ethers.parseUnits("1000", 6));
    await usdc.mint(user1.address, ethers.parseUnits("1000", 6));

    //deploy LoonPay

    const LoonPay = await ethers.getContractFactory("LoonPay");
    const loonPay = await upgrades.deployProxy(
      LoonPay,
      [usdc.target, backend.address],
      { initializer: "initialize" }
    );

    return { owner, backend, user1, user2, loonPay, usdc };
  }

  describe("initialization", function () {
    it("shuld initialize correctly", async function () {
      const { loonPay, usdc } = await loadFixture(deployLoonPayFixtures);
      expect(await loonPay.usdc()).to.equal(usdc.target);
    });
    it("should set trusted backend correctly", async function () {
      const { loonPay, backend } = await loadFixture(deployLoonPayFixtures);
      expect(await loonPay.trustedBackend()).to.equal(backend.address);
    });
    it("should set owner correctly", async function () {
      const { loonPay, owner } = await loadFixture(deployLoonPayFixtures);
      expect(await loonPay.owner()).to.equal(owner.address);
    });
  });
  /* 
  describe("Pausable", function () {
    it("should allow only owner pause and unpause the contract", async function () {
      const { loonPay, owner } = await loadFixture(deployLoonPayFixtures);
      await loonPay.connect(owner).pause();
      expect(await loonPay.paused()).to.be.true;

      await loonPay.connect(owner).unpause();
      expect(await loonPay.paused()).to.be.false;
    });
    it("should not allow non-owner pause or unpause the contract", async function () {
      const { loonPay, user1 } = await loadFixture(deployLoonPayFixtures);
      expect(
        await loonPay.connect(user1).pause()
      ).to.be.revertedWithCustomError(loonPay, "OwnableUnauthorizedAccount");

      expect(
        await loonPay.connect(user1).unpause
      ).to.be.revertedWithCustomError(loonPay, "OwnableUnauthorizedAccount");
    });
  });
  */
  describe("Deposit", function () {
    it("should accept deposit", async function () {
      const { loonPay, user1, usdc } = await loadFixture(deployLoonPayFixtures);
      const amount = ethers.parseUnits("100", 6);

      await usdc.connect(user1).approve(loonPay.target, amount);
      await expect(loonPay.connect(user1).deposit(amount))
        .to.emit(loonPay, "Deposited")
        .withArgs(user1.address, loonPay.target, amount);

      expect(await usdc.balanceOf(loonPay.target)).to.equal(amount);
    });
  });
  describe("Redeem", function () {
    async function prepareRedeemFixture() {
      const fixture = await loadFixture(deployLoonPayFixtures);
      const { loonPay, usdc, owner, user1 } = fixture;

      // Fund contract
      const amount = ethers.parseUnits("1000", 6);
      await usdc.connect(owner).approve(loonPay.target, amount);
      await loonPay.connect(owner).deposit(amount);

      return { ...fixture, amount };
    }

    it("Should allow users to redeem with valid signature", async function () {
      const { loonPay, usdc, backend, user1, amount } = await loadFixture(
        prepareRedeemFixture
      );
      const initialContractBalance = await usdc.balanceOf(loonPay.target);
      const initialBalance = await usdc.balanceOf(user1.address);
      const redeemAmount = ethers.parseUnits("100", 6);
      const code = "TESTCODE123";

      // Create message and sign it
      const message = `Redeem ${redeemAmount} to ${user1.address.toLowerCase()}`;
      const messageHash = ethers.keccak256(ethers.toUtf8Bytes(message));
      const signature = await backend.signMessage(ethers.getBytes(messageHash));

      await expect(loonPay.connect(user1).redeem(code, redeemAmount, signature))
        .to.emit(loonPay, "Redeemed")
        .withArgs(user1.address, redeemAmount);

      expect(await usdc.balanceOf(user1.address)).to.equal(
        redeemAmount + initialBalance
      );
      expect(await usdc.balanceOf(loonPay.target)).to.equal(
        initialBalance - redeemAmount
      );
      expect(await loonPay.codeUsed(code)).to.be.true;
      expect(await loonPay.isRegistered(user1.address)).to.be.true;
    });
    it("prevents fake signature ", async function () {
      const { loonPay, user1, user2, usdc, owner } = await loadFixture(
        prepareRedeemFixture
      );
      const redeemAmount = ethers.parseUnits("100", 6);
      const code = "TESTCODE432";

      const message = `Redeem ${redeemAmount} to ${user1.address.toLowerCase()}`;
      const messageHash = ethers.keccak256(ethers.toUtf8Bytes(message));
      const fakeSignature = await user2.signMessage(
        ethers.getBytes(messageHash)
      );
      expect(
        await loonPay.connect(user1).redeem(code, redeemAmount, fakeSignature)
      ).to.be.revertedWithCustomError(loonPay, "Invalid backend signature");
    });
  });
  describe("Emergency withdraw", function () {
    it("should allow owner to withdraw usdc", async function () {
      const { usdc, loonPay, owner, user1 } = await loadFixture(
        deployLoonPayFixtures
      );
      const amount = ethers.parseUnits("500", 6);
      const withdrawAmount = ethers.parseUnits("100", 6);
      const initialBalance = await usdc.balanceOf(user1.address);
      await usdc.connect(owner).approve(loonPay.target, amount);
      await loonPay.connect(owner).deposit(amount);
      await loonPay
        .connect(owner)
        .emergencyWithdrawUSDC(user1.address, withdrawAmount);
      expect(await usdc.balanceOf(user1.address)).to.equal(
        initialBalance + withdrawAmount
      );
    });
    it("should allow owner to withdraw all usdc", async function () {
      const { loonPay, usdc, user1, owner } = await loadFixture(
        deployLoonPayFixtures
      );
      const initialBalance = await usdc.balanceOf(owner.address);
      // fund contract
      const amount = ethers.parseUnits("600", 6);
      await usdc.connect(owner).approve(loonPay.target, amount);
      await loonPay.connect(owner).deposit(amount);
      await loonPay.connect(owner).emergencyWithdrawAllUSDC();
      expect(await usdc.balanceOf(loonPay.target)).to.equal(0);
      expect(await usdc.balanceOf(owner)).to.equal(initialBalance + amount);
    });
  });
});
