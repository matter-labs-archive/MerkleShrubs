const Shrubs = artifacts.require("Shrubs");
const assert = require("assert");
const depth = 64;

contract("Shrubs", function(accounts) {
    it("should add few items", async function() {
        let totalStored = 0;
        let totalInserted = 0;
        const shrubs = await Shrubs.deployed();
        let historySize = await shrubs.HISTORY_SIZE();
        historySize = historySize.toNumber();
        for (let i = 0; i < historySize; i++) {
            let nextToInsert = await shrubs.nextLeafToInsert();
            nextToInsert = nextToInsert.toNumber();
            const gasEstimate = await shrubs.dummyInsertLeaf.estimateGas();
            console.log("Inserting leaf " + nextToInsert + " costs " + gasEstimate.toString(10));
            let result = await shrubs.dummyInsertLeaf();
            let deleted = 0;
            let stored = 0;
            for (log of result.logs) {
                if (log.event == "Stored") {
                    stored += 1;
                } else if (log.event == "Deleted") {
                    deleted += 1;
                }
            }
            totalStored += stored;
            totalInserted += 1;
            console.log("Stored " + stored + ", deleted " + deleted);
        }
        for (let i = 0; i < 100; i++) {
            let nextToInsert = await shrubs.nextLeafToInsert();
            nextToInsert = nextToInsert.toNumber();
            const gasEstimate = await shrubs.dummyInsertLeaf.estimateGas();
            console.log("Inserting leaf " + nextToInsert + " costs " + gasEstimate.toString(10));
            let result = await shrubs.dummyInsertLeaf();
            let deleted = 0;
            let stored = 0;
            for (log of result.logs) {
                if (log.event == "Stored") {
                    stored += 1;
                } else if (log.event == "Deleted") {
                    deleted += 1;
                }
            }
            totalStored += stored;
            totalInserted += 1;
            console.log("Stored " + stored + ", deleted " + deleted);
            // const currentFrontier = await shrubs.calculateFrontierPath(nextToInsert - 1);
            const historicalFrontier = await shrubs.calculateFrontierPath(nextToInsert - historySize);
            // const merkleShrubs = await shrubs.getShrubs();
            for (let j = 1; j < depth; j++) {
                const frontierIndex = historicalFrontier[j].toNumber();
                const shrubIndex = frontierIndex - 1;
                // const shrubIndexFromShrubs = merkleShrubs.nodeIndexes[j].toNumber();
                // assert(shrubIndex == shrubIndexFromShrubs);
                for (let k = 0; k < shrubIndex; k++) {
                    const hash = await shrubs.getNodeHash(j, k);
                    // assert.strictEqual(hash, "0x0000000000000000000000000000000000000000000000000000000000000000", "should have cleaned hash for level " + j + " node " + k);
                }
            }
        }
        console.log("Averate inserts including leaf itself =" + totalStored/totalInserted);
    });
});