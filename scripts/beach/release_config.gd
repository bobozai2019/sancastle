extends RefCounted

# Fixed v1.60 configuration validated by T05/G4. Experimental CLI flags do not
# alter the default scene or its checkpoint signature.
const ARGUMENTS = ["--beach-staged-slope", "--compensated-capacity", "--packed-runs", "--cached-capacity", "--prefetch-velocity"]
const SHADERS = {"water_displace": "water_displace_compensated", "water_velocity_reduce": "water_velocity_prefetch", "water_full_wet": "water_packed_cached"}
