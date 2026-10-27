-- Behaviour tuning. Sandbox rates still come from each world's options.
return {
    axes = { "caution", "compassion", "independence", "sociability", "conscientiousness", "aggression" },
    plans = {
        waitStrain = 40,
        restStrain = 45,
        restStress = 60,
        familyCompassion = 50,
        companySociability = 45,
        watchConscientiousness = 55,
    },
    refusal = {
        strain = 80,
        stress = 85,
        familyHours = 2,
        familyCompassion = 60,
        lowMorale = 20,
        encouragementTrust = 20,
        riskCaution = 65,
        riskConfidence = 70,
    },
    conversation = {
        cooldownHours = 1,
        reassuranceTrust = 20,
        lonelinessRelief = 8,
        trustedStressRelief = 8,
        strangerStressRelief = 2,
        listeningMorale = 2,
    },
}
