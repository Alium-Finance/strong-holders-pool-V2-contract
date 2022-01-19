import chai from "chai";

import {ethers, network} from "hardhat";
import { BigNumber, BigNumberish, Signer } from "ethers";
import { assert, expect } from "chai";
import { solidity } from "ethereum-waffle";

const { constants } = ethers;
const { AddressZero } = constants;

chai.use(solidity);

function getDateNow() {
    return Math.floor(Date.now()/1000);
}

async function increaseTime(forSeconds: number) {
    await network.provider.send("evm_increaseTime", [forSeconds])
    await network.provider.send("evm_mine")
}

async function setNextBlockTimestamp(timestamp: number) {
    await network.provider.send("evm_setNextBlockTimestamp", [timestamp])
    await network.provider.send("evm_mine")
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

        const ERC20Mock = await ethers.getContractFactory("ERC20Mock")
        const StrongHoldersPoolV2 = await ethers.getContractFactory("StrongHoldersPoolV2")
        const Helper = await ethers.getContractFactory("Helper")

        token = await ERC20Mock.deploy("TEST", "TEST");
        helper = await Helper.deploy();

        const users: any = []
        const unlocks: any = []

        let dataNow = getDateNow() + 100

        let i = 0;
        while (i < 10) {
            users.push(await accounts[i + 1].getAddress())
            dataNow += 100;
            unlocks.push(dataNow)
            i++;
        }

        shp = await StrongHoldersPoolV2.deploy(
            token.address,
            unlocks
        );

        const rewards: Array<Array<any>> = []

        for (let i = 0; i < 3; i++) {
            rewards.push([])
            let y = 0;
            while (y < 10) {
                console.log(`Reward pool: ${i}`)
                rewards[i].push(BigNumber.from(totalRewards[i]).div(BigNumber.from(10)))
                console.log(rewards[i].toString())
                y++;
            }

            // set pools
            await shp.setPool(
                rewards[i],
                users
            )
        }

    })

    describe("General", () => {
        it("#initialize", async () => {
            await token.mint(shp.address, TOTAL_LOCKED_TOKENS)
            await shp.initialize()
        })

        it("#leave", async () => {
            let poolId = 0;
            let countedReward = await shp.countReward(poolId)

            assert.equal(Number(countedReward), 0, "why not zero?")

            expect(shp.connect(accounts[1]).leave(poolId)).to.revertedWith('SHP: distribution impossible');

            let nextClaim = await shp.nextClaim();
            console.log(Number(nextClaim))
            await setNextBlockTimestamp(Number(nextClaim))

            countedReward = await shp.countReward(poolId)
            let expectedReward = (await shp.getReward(poolId, 0))

            assert.equal(countedReward.toString(), expectedReward.toString(), "Not expected reward")

            await shp.connect(accounts[1]).leave(poolId)

            let poolInfo_0 = await shp.generalPoolInfo(0)
            assert.notEqual(poolInfo_0.initialBalance.toString(), poolInfo_0.balance.toString(), "Initial balance changed")

            // revert if zero reward
            expect(shp.connect(accounts[1]).leave(poolId)).to.revertedWith('Nothing withdraw');

            assert.equal((await token.balanceOf(await accounts[1].getAddress())).toString(), countedReward.toString(), "Claimer wrong balance")

            await setNextBlockTimestamp(Number(await shp.DISTRIBUTION_END()) + 100)

            await shp.connect(accounts[1]).leave(poolId)

            poolInfo_0 = await shp.generalPoolInfo(0)
            assert.equal(Number(poolInfo_0.balance), 0, "Pool balance not zero")

            expect(shp.connect(accounts[1]).leave(poolId)).to.revertedWith('SHP: pool closed');
        })

    })
});