pragma solidity >=0.5.1;

contract Shrubs {
    mapping(uint128 => bytes32) public nodes;
    
    uint64 public nextLeafToInsert = 0;
    
    uint8 constant public TREE_DEPTH = 64;
    uint64 constant public HISTORY_SIZE = 16;

    event Stored();
    event Deleted();
    
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
        uint64 currentLeaf = nextLeafToInsert;
        nodes[getLeafIndex(currentLeaf)] = leafHash;
        emit Stored();
        nextLeafToInsert += 1;
        calculateFrontierWitness(currentLeaf, leafHash);
        clearOldWitness(currentLeaf);
    }
    
    function calculateFrontierWitness(uint64 insertedLeafIndex, bytes32 insertedHash) internal {
        uint64[TREE_DEPTH] memory newFrontier = calculateFrontierPath(insertedLeafIndex + 1);
        uint64[TREE_DEPTH] memory insertedLeafPath = calculateFrontierPath(insertedLeafIndex);
        bytes32 h = insertedHash;
        for (uint256 i = 1; i < TREE_DEPTH; i++) {
            uint128 witnessIndex = getNodeIndex(uint8(i-1), insertedLeafPath[i-1]);
            bytes32 witness = nodes[witnessIndex];
            if (witness == bytes32(0)) {
                // node at the previous level is empty node or empty leaf, so 
                // this node valus can be recalculated
                break;
            }
            if (insertedLeafPath[i-1] & 1 == 0) {
                h = sha256(abi.encodePacked(h, witness));
            } else {
                h = sha256(abi.encodePacked(witness, h));
            }
            uint128 thisNodeIndex = getNodeIndex(uint8(i), insertedLeafPath[i]);
            if (newFrontier[i] - insertedLeafPath[i] == 1) {
                nodes[thisNodeIndex] = h;
                emit Stored();
            }
        }
    }
    
    function clearOldWitness(uint64 lastInserted) internal {
        if (lastInserted < HISTORY_SIZE) {
            return;
        }
        uint64 historicalFontierPointer = lastInserted - HISTORY_SIZE;
        uint64[TREE_DEPTH] memory currentFrontier = calculateFrontierPath(lastInserted);
        uint64[TREE_DEPTH] memory oldFrontier = calculateFrontierPath(historicalFontierPointer);
        for (uint256 i = 1; i < TREE_DEPTH; i++) {
            if (currentFrontier[i] - oldFrontier[i] > 1) {
                uint128 nodeIndex = getNodeIndex(uint8(i), oldFrontier[i]);
                if (nodes[nodeIndex] != bytes32(0)) {
                    delete nodes[nodeIndex];
                    emit Deleted();
                }
            }
        }
    }
    
    function calculateFrontierPath(uint64 frontierPointer) public pure returns (uint64[TREE_DEPTH] memory nodeIndexes) {
        nodeIndexes[0] = frontierPointer;
        uint64 path = frontierPointer;
        for (uint256 i = 1; i < TREE_DEPTH; i++) {
            path = path >> 1;
            nodeIndexes[i] = path;
        }
    }
    
    // function isNearFrontier(uint64[TREE_DEPTH] memory nodeIndexes, uint8 treeLevel, uint64 nodeIndex) public pure returns (bool isNear) {
    //     return nodeIndexes[uint256(treeLevel)] + 1 == nodeIndex;
    // }
    
    function getFrontier() public view returns (uint64[TREE_DEPTH] memory nodeIndexes, bytes32[TREE_DEPTH] memory shrubs) {
        uint64 frontierPointer = nextLeafToInsert - 1;
        nodeIndexes[0] = frontierPointer;
        shrubs[0] = getLeafHash(frontierPointer);
        for (uint256 i = 1; i < TREE_DEPTH; i++) {
            frontierPointer = frontierPointer >> 1;
            nodeIndexes[i] = frontierPointer;
            shrubs[i] = getNodeHash(uint8(i), frontierPointer);
        }
    }
}