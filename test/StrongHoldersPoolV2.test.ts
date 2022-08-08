import chai from "chai";

import { ethers, network } from "hardhat";
import { BigNumber, Signer } from "ethers";
import { assert, expect } from "chai";
import { solidity } from "ethereum-waffle";
import { parseEther } from "ethers/lib/utils";

chai.use(solidity);

function getDateNow() {
    return Math.floor(Date.now()/1000);
}

async function setNextBlockTimestamp(timestamp: number) {
    await network.provider.send("evm_setNextBlockTimestamp", [timestamp])
    await network.provider.send("evm_mine")
}

async function createSnapshot() {
    return await network.provider.request({
        method: "evm_snapshot",
    });
}

async function restoreSnapshot(snapshotId: any) {
    const reverted = await network.provider.request({
        method: "evm_revert",
        params: [snapshotId],
    });
}

async function expectRevert(condition: any, message: string) {
    expect(condition).to.revertedWith(message);
}

describe("StrongHolderPool", function () {
    let accounts: Signer[];

    let OWNER_SIGNER: any;
    let BUYER_SIGNER: any;
    let TRESUARY_SIGNER: any;

    let OWNER: any;
    let BUYER: any;
    let TRESUARY: any;

    let shp: any;
    let token: any;
    let helper: any;

    const TOTAL_LOCKED_TOKENS: BigNumber = ethers.utils.parseUnits(
        String((5_000_000 - 50_000) + (8_000_000 - 80_000) + (12_000_000 - 120_000)),
        "ether"
    );

    const totalRewards: Array<BigNumber> = [
        ethers.utils.parseUnits(String(5_000_000 - 50_000), "ether"),
        ethers.utils.parseUnits(String(8_000_000 - 80_000), "ether"),
        ethers.utils.parseUnits(String(12_000_000 - 120_000), "ether"),
    ]

    before("config", async () => {
        accounts = await ethers.getSigners();

        OWNER_SIGNER = accounts[0];
        BUYER_SIGNER = accounts[1];
        TRESUARY_SIGNER = accounts[2];

        OWNER = await OWNER_SIGNER.getAddress();
        BUYER = await BUYER_SIGNER.getAddress();
        TRESUARY = await TRESUARY_SIGNER.getAddress();

        const Helper = await ethers.getContractFactory("Helper")

        helper = await Helper.deploy();
    })

    let rewards: Array<Array<any>> = []
    let unlocks: any = []
    let users: any = []
    let initBalances: Array<BigNumber> = []

    let snapshotId: any;
    beforeEach(async () => {
        snapshotId = await createSnapshot()
        console.log(`Snapshot: ${snapshotId}`)

        const ERC20Mock = await ethers.getContractFactory("ERC20Mock")
        const StrongHoldersPoolV2 = await ethers.getContractFactory("StrongHoldersPoolV2")

        token = await ERC20Mock.deploy("TEST", "TEST");
        await token.deployed()

        shp = await StrongHoldersPoolV2.deploy();
        await shp.deployed()
        console.log(`SHP deployed to ${shp.address}`)

        rewards = [];
        unlocks = [];
        users = [];
        initBalances = [];

        rewards[0] = [
            parseEther('14850'),
            parseEther('19800'),
            parseEther('24750'),
            parseEther('34650'),
            parseEther('44550'),
            parseEther('49500'),
            parseEther('59400'),
            parseEther('69300'),
            parseEther('74250'),
            parseEther('103950'),
        ]

        rewards[1] = [
            parseEther('23760'),
            parseEther('31680'),
            parseEther('39600'),
            parseEther('55440'),
            parseEther('71280'),
            parseEther('79200'),
            parseEther('95040'),
            parseEther('110880'),
            parseEther('118800'),
            parseEther('166320'),
        ]

        rewards[2] = [
            parseEther('35640'),
            parseEther('47520'),
            parseEther('59400'),
            parseEther('83160'),
            parseEther('106920'),
            parseEther('118800'),
            parseEther('142560'),
            parseEther('166320'),
            parseEther('178200'),
            parseEther('249480'),
        ]

        initBalances[0] = totalRewards[0].div(BigNumber.from(10))
        initBalances[1] = totalRewards[1].div(BigNumber.from(10))
        initBalances[2] = totalRewards[2].div(BigNumber.from(10))

        let dataNow = getDateNow() + 100

        let i = 0;
        while (i < 10) {
            let account = accounts[i].getAddress()
            users.push(account)
            dataNow += 60 * 60 * 24 * 31;
            unlocks.push(dataNow)
            i++;
        }

        await shp.initialize(
            token.address,
            initBalances[0],
            unlocks,
            rewards[0],
            users
        )

        await token.mint(shp.address, totalRewards[0])
    })

    afterEach(async () => {
        await restoreSnapshot(snapshotId)
    })

    it("#leave", async () => {
        let poolId = 0;

        await expectRevert(shp.connect(accounts[1]).leave(poolId), "SHP: pool is locked");

        const unlocks = await shp.getUnlocks()
        let nextClaim = unlocks[poolId];

        assert.isFalse(await shp.isPoolUnlocked(poolId), "Pool is unlocked?")

        await setNextBlockTimestamp(Number(nextClaim))

        for (let i = 0; i < 10; i++) {
            if (i === poolId) {
                assert.isTrue(await shp.isPoolUnlocked(poolId), "Pool is locked?")
            } else {
                assert.isFalse(await shp.isPoolUnlocked(i), "Pool is unlocked?")
            }
        }

        for (let i = 0; i < 10; i++) {
            let account = await accounts[i].getAddress()
            console.log(await shp.calculateReward(poolId, account))
            await shp.connect(accounts[i]).leave(poolId)
            if (i === 10 - 1) {
                await expectRevert(shp.connect(accounts[i]).leave(poolId), "SHP: pool is closed");
            } else {
                await expectRevert(shp.connect(accounts[i]).leave(poolId), "SHP: reward accepted");
            }
            console.log(await token.balanceOf(account))
            assert.equal(String(await token.balanceOf(account)), String(rewards[0][i]), "Balance")
        }
    })

    it("#leave (AFTER END_TIME)", async () => {
        let poolId = 0;

        await expectRevert(shp.connect(accounts[1]).leave(poolId), "SHP: pool is locked");

        let nextClaim = await shp.distributionEnd(poolId);

        await setNextBlockTimestamp(Number(nextClaim))

        // console.log(BigNumber.from(initBalances[0]).div(BigNumber.from('10')))

        for (let i = 0; i < 10; i++) {
            let account = await accounts[i].getAddress()
            console.log(`Iteration ${i}`)
            console.log(`Recipient ${account}`)
            console.log(await token.balanceOf(account))
            console.log(await shp.calculateReward(poolId, account))
            await shp.connect(accounts[i]).leave(poolId)
            if (i === 10 - 1) {
                await expectRevert(shp.connect(accounts[i]).leave(poolId), "SHP: pool is closed");
            } else {
                await expectRevert(shp.connect(accounts[i]).leave(poolId), "SHP: reward accepted");
            }
            console.log(await token.balanceOf(account))
            // assert.equal(String(await token.balanceOf(account)), String(BigNumber.from(totalRewards[0]).div(BigNumber.from('10'))), `Balance ${i}`)
        }


        console.log(`Left balance: `)
        console.log(await token.balanceOf(shp.address))

        assert.equal(String(await token.balanceOf(shp.address)), String(BigNumber.from(totalRewards[0]).sub(BigNumber.from(initBalances[0]))), "Balance of the pool")
    })

    it("#leave (ALL POOLS | BEFORE END_TIME)", async () => {
        const unlocks = await shp.getUnlocks()

        // unlock last pool
        let poolId = unlocks.length-1
        console.log(poolId)
        let nextClaim = unlocks[poolId];

        await setNextBlockTimestamp(Number(nextClaim))

        assert.isTrue(await shp.isPoolUnlocked(poolId), "Pool is locked?")

        for (let u = 0; u < 10; u++) {
            for (let i = 0; i < 10; i++) {
                await shp.connect(accounts[i]).leave(u)
                if (i === 10 - 1) {
                    await expectRevert(shp.connect(accounts[0]).leave(u), "SHP: pool is closed");
                } else {
                    await expectRevert(shp.connect(accounts[i]).leave(u), "SHP: reward accepted");
                }
                // let account = await accounts[i].getAddress()
                //assert.equal(String(await token.balanceOf(account)), String(rewards[0][i]), "Balance")
            }
        }

        assert.equal(String(await token.balanceOf(shp.address)), String(0), "Balance of the pool")
    })

});
