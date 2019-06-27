pragma solidity >=0.5.1;

contract Shrubs {
    mapping(uint128 => bytes32) public nodes;
    
    uint64 public nextLeafToInsert = 0;
    
    uint8 constant public TREE_DEPTH = 64;
    uint64 constant public HISTORY_SIZE = 16;

    event Stored();
    event Deleted();
    event GasLeft(uint256 gas);
    event CleanupFor(uint64 frontierIndex);
    event WentBackwards();

    // tree levels are enumerated from the leaf level, and leafs are "level 0"
    constructor() public {
        
    }
    
    function getEmptyNodeHash(uint8 treeLevel) public pure returns (bytes32 emptyNodeHash) {
        bytes32 h = sha256(abi.encodePacked(bytes32(0)));
        for (uint8 i = 0; i < treeLevel; i++) {
            h = sha256(abi.encodePacked(h, h));
        }
        return h;
    }
    
    function getLeafHash(uint64 leaf) public view returns (bytes32 leafHash) {
        return nodes[uint128(leaf)];
    }
    
    function getNodeHash(uint8 treeLevel, uint64 nodeIndex) public view returns (bytes32 nodeHash) {
        return nodes[getNodeIndex(treeLevel, nodeIndex)];
    }
    
    function getNodeIndex(uint8 treeLevel, uint64 nodeIndex) public pure returns (uint128 index) {
        require(treeLevel < TREE_DEPTH, "nodes have levels in the range");
        return (uint128(treeLevel) << 64) + uint128(nodeIndex);
    }
    
    function getLeafIndex(uint64 leafNumber) public pure returns (uint128 index) {
        return uint128(leafNumber);
    }
    
    function dummyInsertLeaf() public {
        bytes32 h = sha256(abi.encodePacked("dummy", nextLeafToInsert));
        insertLeaf(h);
    }
    
    function insertLeaf(bytes32 leafHash) public {
        // emit GasLeft(gasleft());
        uint64 currentLeaf = nextLeafToInsert;
        nodes[getLeafIndex(currentLeaf)] = leafHash;
        emit Stored();
        nextLeafToInsert += 1;
        // emit GasLeft(gasleft());
        prepareWitnessForNextFrontier(currentLeaf, leafHash);
        // emit GasLeft(gasleft());
        clearOldWitness(currentLeaf);
        // emit GasLeft(gasleft());
    }
    
    function prepareWitnessForNextFrontier(uint64 insertedLeafIndex, bytes32 insertedHash) internal {
        uint64[TREE_DEPTH] memory nextFrontier = calculatePath(insertedLeafIndex + 1);
        uint64[TREE_DEPTH] memory insertedLeafPath = calculatePath(insertedLeafIndex);
        bytes32 h = insertedHash;
        for (uint256 i = 1; i < TREE_DEPTH; i++) {
            // get another child for this node
            uint128 witnessIndex = getNodeIndex(uint8(i-1), insertedLeafPath[i-1] ^ 1);
            bytes32 witness = nodes[witnessIndex];
            // value of another child may be empty
            if (witness == bytes32(0)) {
                // it can happed only if inserted child is left
                assert(insertedLeafPath[i-1] & 1 == 0);
                // node at the previous level is empty node or empty leaf, so
                // this node value can be recalculated
                break;
            }
            if (insertedLeafPath[i-1] & 1 == 0) {
                h = sha256(abi.encodePacked(h, witness));
            } else {
                h = sha256(abi.encodePacked(witness, h));
            }
            uint128 thisNodeIndex = getNodeIndex(uint8(i), insertedLeafPath[i]);
            // one should only write value into this node if it's a "shrub" for a next frontier
            // and that inserted node is a left child
            if (nextFrontier[i] - insertedLeafPath[i] == 1 && insertedLeafPath[i] & 1 == 0) {
                nodes[thisNodeIndex] = h;
                emit Stored();
            }
        }
    }

    function clearOldWitness(uint64 lastInserted) internal {
        if (lastInserted < HISTORY_SIZE) {
            return;
        }
        uint64 historicalFontierPointer = lastInserted - HISTORY_SIZE + 1;
        uint64[TREE_DEPTH] memory currentFrontier = calculatePath(lastInserted);
        // this is a last frontier to keep
        uint64[TREE_DEPTH] memory oldestHistoricalFrontier = calculatePath(historicalFontierPointer);
        emit CleanupFor(historicalFontierPointer - 1);
        for (uint256 i = 1; i < TREE_DEPTH; i++) {
            uint64 oldFrontierIndex = oldestHistoricalFrontier[i];
            if (oldFrontierIndex == currentFrontier[i]) {
                // point of merging with a current one
                // so stop cleaning cause shrubs for this frontier
                // are also shrubs for the newest one
                break;
            }
            if (oldFrontierIndex & 1 == 0) {
                // this frontier leaf is a left child for a next one,
                // so one on a left at the same level can be deleted
                // cause it's not necessary for recalculation of the parent
                if (oldFrontierIndex > 0) {
                    uint128 nodeIndex = getNodeIndex(uint8(i), oldFrontierIndex-1);
                    if (nodes[nodeIndex] != bytes32(0)) {
                        delete nodes[nodeIndex];
                        emit Deleted();
                    }
                }
                if (oldFrontierIndex > 1) {
                    uint128 nodeIndex = getNodeIndex(uint8(i), oldFrontierIndex-2);
                    if (nodes[nodeIndex] != bytes32(0)) {
                        delete nodes[nodeIndex];
                        emit Deleted();
                    }
                }
            } else {
                // this frontier leaf is a right child for for a next one,
                // so left one may be required for recalculation
                if (oldFrontierIndex > 1) {
                    uint128 nodeIndex = getNodeIndex(uint8(i), oldFrontierIndex-2);
                    if (nodes[nodeIndex] != bytes32(0)) {
                        delete nodes[nodeIndex];
                        emit Deleted();
                    }
                }
            }
        }
    }
    
    function calculatePath(uint64 frontierPointer) public pure returns (uint64[TREE_DEPTH] memory nodeIndexes) {
        nodeIndexes[0] = frontierPointer;
        uint64 path = frontierPointer;
        for (uint256 i = 1; i < TREE_DEPTH; i++) {
            path = path >> 1;
            nodeIndexes[i] = path;
        }
    }

    function haveShrubsForFrontierPointer(uint64 frontierPointer) public view returns (bool haveShrubs) {
        return frontierPointer >= nextLeafToInsert - HISTORY_SIZE;
    }
    
    // get frontier for anchoring for a particular state.
    // state is enumerated using "nextToInsert"
    function getFrontierByIndex(uint64 frontierIndex) public view returns (uint64[TREE_DEPTH] memory nodeIndexes, bytes32[TREE_DEPTH] memory nodeHashes) {
        assert(haveShrubsForFrontierPointer(frontierIndex));
        assert(frontierIndex < nextLeafToInsert);
        uint64 frontierPointer = frontierIndex;
        nodeIndexes[0] = frontierPointer;
        nodeHashes[0] = getLeafHash(frontierPointer);
        for (uint256 i = 1; i < TREE_DEPTH; i++) {
            uint64 previousPointer = frontierPointer;
            frontierPointer = frontierPointer >> 1;
            nodeIndexes[i] = frontierPointer;
            // TODO: MUST NOT pick into newer nodes
            bytes32 nodeHash = getNodeHash(uint8(i), frontierPointer);
            if (nodeHash == bytes32(0)) {
                // node is not stores, so it's recalculatable
                // if (i == 1) {
                //     bytes32 witness = getLeafHash(previousPointer);
                //     nodeHash = sha256(abi.encodePacked(nodeHashes[i-1], witness));
                // } else {
                //     bytes32 witness = getEmptyNodeHash(uint8(i-1));
                //     nodeHash = sha256(abi.encodePacked(nodeHashes[i-1], witness));
                // }
                // node value must be recalculated
                uint128 witnessIndex = getNodeIndex(uint8(i-1), previousPointer ^ 1);
                bytes32 witness = nodes[witnessIndex];
                if (previousPointer & 1 == 0) {
                    if (i == 1) {
                        witness = getLeafHash(previousPointer);
                    } else {
                        witness = getEmptyNodeHash(uint8(i-1));
                    }
                }
                // bytes32 witness = nodes[witnessIndex];
                // if (witness == bytes32(0)) {
                //     // previous level node should be left child
                //     assert(previousPointer & 1 == 0);
                //     witness = getEmptyNodeHash(uint8(i-1));
                // }
                if (previousPointer & 1 == 0) {
                    nodeHash = sha256(abi.encodePacked(nodeHashes[i-1], witness));
                } else {
                    nodeHash = sha256(abi.encodePacked(witness, nodeHashes[i-1]));
                }
            }
            nodeHashes[i] = nodeHash;
        }
    }
}