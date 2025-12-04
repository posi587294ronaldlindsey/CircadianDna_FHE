// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { FHE, euint32, ebool } from "@fhevm/solidity/lib/FHE.sol";
import { SepoliaConfig } from "@fhevm/solidity/config/ZamaConfig.sol";

contract CircadianDna_FHE is SepoliaConfig {
    struct EncryptedDna {
        euint32[] geneMarkers;      // Encrypted circadian gene markers
        euint32 sleepPattern;       // Encrypted sleep pattern data
        euint32 chronotype;         // Encrypted chronotype classification
    }
    
    struct Recommendation {
        string sleepSchedule;
        string mealTiming;
        string activityPlan;
        bool isRevealed;
    }

    uint256 public userCount;
    mapping(uint256 => EncryptedDna) public dnaProfiles;
    mapping(uint256 => Recommendation) public recommendations;
    
    event DnaSubmitted(uint256 indexed userId);
    event AnalysisRequested(uint256 indexed userId);
    event RecommendationReady(uint256 indexed userId);
    
    modifier onlyUser(uint256 userId) {
        _;
    }
    
    function submitEncryptedDna(
        euint32[] memory geneMarkers,
        euint32 sleepPattern,
        euint32 chronotype
    ) public {
        userCount += 1;
        uint256 newId = userCount;
        
        dnaProfiles[newId] = EncryptedDna({
            geneMarkers: geneMarkers,
            sleepPattern: sleepPattern,
            chronotype: chronotype
        });
        
        recommendations[newId] = Recommendation({
            sleepSchedule: "",
            mealTiming: "",
            activityPlan: "",
            isRevealed: false
        });
        
        emit DnaSubmitted(newId);
    }
    
    function requestRhythmAnalysis(uint256 userId) public onlyUser(userId) {
        EncryptedDna storage dna = dnaProfiles[userId];
        require(dna.geneMarkers.length > 0, "No DNA data");
        
        bytes32[] memory ciphertexts = new bytes32[](dna.geneMarkers.length + 2);
        
        for (uint i = 0; i < dna.geneMarkers.length; i++) {
            ciphertexts[i] = FHE.toBytes32(dna.geneMarkers[i]);
        }
        
        ciphertexts[ciphertexts.length-2] = FHE.toBytes32(dna.sleepPattern);
        ciphertexts[ciphertexts.length-1] = FHE.toBytes32(dna.chronotype);
        
        uint256 reqId = FHE.requestDecryption(ciphertexts, this.generateRecommendations.selector);
        
        emit AnalysisRequested(userId);
    }
    
    function generateRecommendations(
        uint256 requestId,
        bytes memory cleartexts,
        bytes memory proof
    ) public {
        FHE.checkSignatures(requestId, cleartexts, proof);
        
        (string memory sleep, string memory meals, string memory activities) = 
            abi.decode(cleartexts, (string, string, string));
        
        recommendations[requestId] = Recommendation({
            sleepSchedule: sleep,
            mealTiming: meals,
            activityPlan: activities,
            isRevealed: true
        });
        
        emit RecommendationReady(requestId);
    }
    
    function getRecommendations(uint256 userId) public view returns (
        string memory sleepSchedule,
        string memory mealTiming,
        string memory activityPlan,
        bool isRevealed
    ) {
        Recommendation storage rec = recommendations[userId];
        return (
            rec.sleepSchedule,
            rec.mealTiming,
            rec.activityPlan,
            rec.isRevealed
        );
    }
    
    function calculateChronotypeScore(
        euint32[] memory geneMarkers,
        euint32 sleepPattern
    ) public pure returns (euint32) {
        euint32 score = FHE.asEuint32(0);
        
        for (uint i = 0; i < geneMarkers.length; i++) {
            score = FHE.add(score, geneMarkers[i]);
        }
        
        return FHE.add(score, sleepPattern);
    }
    
    function determineSleepType(
        euint32 chronotypeScore
    ) public pure returns (euint32) {
        return FHE.select(
            FHE.gt(chronotypeScore, FHE.asEuint32(50)),
            FHE.asEuint32(1),  // Morning type
            FHE.select(
                FHE.lt(chronotypeScore, FHE.asEuint32(30)),
                FHE.asEuint32(3),  // Evening type
                FHE.asEuint32(2)   // Intermediate
            )
        );
    }
    
    function calculateOptimalWakeTime(
        euint32 sleepType,
        euint32 sleepPattern
    ) public pure returns (euint32) {
        return FHE.select(
            FHE.eq(sleepType, FHE.asEuint32(1)),
            FHE.sub(sleepPattern, FHE.asEuint32(2)),  // Early riser
            FHE.select(
                FHE.eq(sleepType, FHE.asEuint32(3)),
                FHE.add(sleepPattern, FHE.asEuint32(3)),  // Late riser
                sleepPattern  // Neutral
            )
        );
    }
}