import {network} from "hardhat";
import {expect} from "chai";

export function getDateNow() {
    return Math.floor(Date.now()/1000);
}

export async function setNextBlockTimestamp(timestamp: number) {
    await network.provider.send("evm_setNextBlockTimestamp", [timestamp])
    await network.provider.send("evm_mine")
}

export async function createSnapshot() {
    return await network.provider.request({
        method: "evm_snapshot",
    });
}

export async function restoreSnapshot(snapshotId: any) {
    const reverted = await network.provider.request({
        method: "evm_revert",
        params: [snapshotId],
    });
}

export async function expectRevert(condition: any, message: string) {
    expect(condition).to.revertedWith(message);
}
