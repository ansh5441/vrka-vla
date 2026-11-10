---- MODULE vrka_horizon_lease ----
EXTENDS Integers, Sequences, TLC

CONSTANTS
    MAX_CORRIDOR_POS, \* Discrete 1D spatial grid for the quadruped
    THREAT_POS,       \* Position of the dynamic/static threat boundary
    MAX_HORIZON_TTL,  \* Number of 500 Hz ticks a 20 Hz VLA action chunk remains valid
    MAX_VEL           \* Maximum discrete velocity command

(*--algorithm VrkaHorizonLease

variables
    \* Shared-memory Seqlock slot
    shm_seq = 0,
    shm_cmd_vel = 0,
    shm_chunk_ttl = 0,
    shm_threat_epoch = 0,

    \* 500 Hz controller state
    ctrl_mode = "NOMINAL",
    ctrl_vel = 0,
    ctrl_ttl = 0,
    robot_pos = 0,

    \* Peer_Wolf_Pack lease state
    peer_pos = THREAT_POS,
    peer_lease_ttl = 0;

define
    BrakingDistance(v) == (v * (v + 1)) \div 2
    EffectiveObstaclePos ==
        IF peer_lease_ttl > 0 /\ peer_pos < THREAT_POS
        THEN peer_pos
        ELSE THREAT_POS
    SafetyNoCollision == robot_pos <= EffectiveObstaclePos
    CBFBarrierInvariant == (robot_pos + BrakingDistance(ctrl_vel)) <= EffectiveObstaclePos
    SeqlockNoTornRead ==
        /\ ctrl_vel \in 0..MAX_VEL
        /\ ctrl_ttl \in 0..MAX_HORIZON_TTL
        /\ ((shm_seq % 2 = 0) => (shm_cmd_vel \in 0..MAX_VEL))
end define;

process VLA_Proposer_20Hz = "VLA_Proposer_20Hz"
begin
    ProposerLoop:
        while TRUE do
            WriteBegin:
                shm_seq := (shm_seq + 1) % 4;
                shm_cmd_vel := -1;
            WriteCommit:
                with v \in 0..MAX_VEL, ttl \in 1..MAX_HORIZON_TTL do
                    shm_cmd_vel := v;
                    shm_chunk_ttl := ttl;
                    shm_threat_epoch := (shm_seq + 1) \div 2;
                    shm_seq := (shm_seq + 1) % 4;
                end with;
        end while;
end process;

process Vrka_RT_Spine_500Hz = "Vrka_RT_Spine_500Hz"
begin
    SpineLoop:
        while TRUE do
            SpineTick:
                if shm_seq % 2 = 0 /\ shm_chunk_ttl > 0 then
                    ctrl_ttl := shm_chunk_ttl;
                    if shm_chunk_ttl > 1 then
                        ctrl_mode := "NOMINAL";
                    else
                        ctrl_mode := "DECEL_FALLBACK";
                    end if;
                    with v_cand = IF shm_chunk_ttl > 1
                                  THEN shm_cmd_vel
                                  ELSE IF shm_cmd_vel > 0 THEN shm_cmd_vel - 1 ELSE 0,
                         SafeVels = {v \in 0..v_cand :
                             robot_pos + v + BrakingDistance(v) <= EffectiveObstaclePos},
                         v_safe \in {v \in SafeVels : \A u \in SafeVels : v >= u} do
                        ctrl_vel := v_safe;
                        robot_pos := robot_pos + v_safe;
                    end with;
                else
                    if ctrl_ttl > 2 then
                        ctrl_ttl := ctrl_ttl - 1;
                        ctrl_mode := "NOMINAL";
                        with SafeVels = {v \in 0..ctrl_vel :
                                 robot_pos + v + BrakingDistance(v) <= EffectiveObstaclePos},
                             v_safe \in {v \in SafeVels : \A u \in SafeVels : v >= u} do
                            ctrl_vel := v_safe;
                            robot_pos := robot_pos + v_safe;
                        end with;
                    elsif ctrl_ttl = 2 then
                        ctrl_ttl := 1;
                        ctrl_mode := "DECEL_FALLBACK";
                        with v_dec = IF ctrl_vel > 0 THEN ctrl_vel - 1 ELSE 0,
                             SafeVels = {v \in 0..v_dec :
                                 robot_pos + v + BrakingDistance(v) <= EffectiveObstaclePos},
                             v_safe \in {v \in SafeVels : \A u \in SafeVels : v >= u} do
                            ctrl_vel := v_safe;
                            robot_pos := robot_pos + v_safe;
                        end with;
                    else
                        ctrl_ttl := 0;
                        ctrl_mode := "STANCE_LOCK";
                        ctrl_vel := 0;
                    end if;
                end if;
        end while;
end process;

process Peer_Wolf_UDP = "Peer_Wolf_UDP"
begin
    PeerLoop:
        while TRUE do
            PeerStep:
                either
                    with p \in (robot_pos + BrakingDistance(ctrl_vel))..MAX_CORRIDOR_POS,
                         ttl \in 1..MAX_HORIZON_TTL do
                        peer_pos := p;
                        peer_lease_ttl := ttl;
                    end with;
                or
                    if peer_lease_ttl > 0 then
                        peer_lease_ttl := peer_lease_ttl - 1;
                    end if;
                end either;
        end while;
end process;

end algorithm; *)
\* BEGIN TRANSLATION (chksum(pcal) = "d98e7ebb" /\ chksum(tla) = "8cad2597")
VARIABLES shm_seq, shm_cmd_vel, shm_chunk_ttl, shm_threat_epoch, ctrl_mode, 
          ctrl_vel, ctrl_ttl, robot_pos, peer_pos, peer_lease_ttl, pc

(* define statement *)
BrakingDistance(v) == (v * (v + 1)) \div 2
EffectiveObstaclePos ==
    IF peer_lease_ttl > 0 /\ peer_pos < THREAT_POS
    THEN peer_pos
    ELSE THREAT_POS
SafetyNoCollision == robot_pos <= EffectiveObstaclePos
CBFBarrierInvariant == (robot_pos + BrakingDistance(ctrl_vel)) <= EffectiveObstaclePos
SeqlockNoTornRead ==
    /\ ctrl_vel \in 0..MAX_VEL
    /\ ctrl_ttl \in 0..MAX_HORIZON_TTL
    /\ ((shm_seq % 2 = 0) => (shm_cmd_vel \in 0..MAX_VEL))


vars == << shm_seq, shm_cmd_vel, shm_chunk_ttl, shm_threat_epoch, ctrl_mode, 
           ctrl_vel, ctrl_ttl, robot_pos, peer_pos, peer_lease_ttl, pc >>

ProcSet == {"VLA_Proposer_20Hz"} \cup {"Vrka_RT_Spine_500Hz"} \cup {"Peer_Wolf_UDP"}

Init == (* Global variables *)
        /\ shm_seq = 0
        /\ shm_cmd_vel = 0
        /\ shm_chunk_ttl = 0
        /\ shm_threat_epoch = 0
        /\ ctrl_mode = "NOMINAL"
        /\ ctrl_vel = 0
        /\ ctrl_ttl = 0
        /\ robot_pos = 0
        /\ peer_pos = THREAT_POS
        /\ peer_lease_ttl = 0
        /\ pc = [self \in ProcSet |-> CASE self = "VLA_Proposer_20Hz" -> "ProposerLoop"
                                        [] self = "Vrka_RT_Spine_500Hz" -> "SpineLoop"
                                        [] self = "Peer_Wolf_UDP" -> "PeerLoop"]

ProposerLoop == /\ pc["VLA_Proposer_20Hz"] = "ProposerLoop"
                /\ pc' = [pc EXCEPT !["VLA_Proposer_20Hz"] = "WriteBegin"]
                /\ UNCHANGED << shm_seq, shm_cmd_vel, shm_chunk_ttl, 
                                shm_threat_epoch, ctrl_mode, ctrl_vel, 
                                ctrl_ttl, robot_pos, peer_pos, peer_lease_ttl >>

WriteBegin == /\ pc["VLA_Proposer_20Hz"] = "WriteBegin"
              /\ shm_seq' = (shm_seq + 1) % 4
              /\ shm_cmd_vel' = -1
              /\ pc' = [pc EXCEPT !["VLA_Proposer_20Hz"] = "WriteCommit"]
              /\ UNCHANGED << shm_chunk_ttl, shm_threat_epoch, ctrl_mode, 
                              ctrl_vel, ctrl_ttl, robot_pos, peer_pos, 
                              peer_lease_ttl >>

WriteCommit == /\ pc["VLA_Proposer_20Hz"] = "WriteCommit"
               /\ \E v \in 0..MAX_VEL:
                    \E ttl \in 1..MAX_HORIZON_TTL:
                      /\ shm_cmd_vel' = v
                      /\ shm_chunk_ttl' = ttl
                      /\ shm_threat_epoch' = ((shm_seq + 1) \div 2)
                      /\ shm_seq' = (shm_seq + 1) % 4
               /\ pc' = [pc EXCEPT !["VLA_Proposer_20Hz"] = "ProposerLoop"]
               /\ UNCHANGED << ctrl_mode, ctrl_vel, ctrl_ttl, robot_pos, 
                               peer_pos, peer_lease_ttl >>

VLA_Proposer_20Hz == ProposerLoop \/ WriteBegin \/ WriteCommit

SpineLoop == /\ pc["Vrka_RT_Spine_500Hz"] = "SpineLoop"
             /\ pc' = [pc EXCEPT !["Vrka_RT_Spine_500Hz"] = "SpineTick"]
             /\ UNCHANGED << shm_seq, shm_cmd_vel, shm_chunk_ttl, 
                             shm_threat_epoch, ctrl_mode, ctrl_vel, ctrl_ttl, 
                             robot_pos, peer_pos, peer_lease_ttl >>

SpineTick == /\ pc["Vrka_RT_Spine_500Hz"] = "SpineTick"
             /\ IF shm_seq % 2 = 0 /\ shm_chunk_ttl > 0
                   THEN /\ ctrl_ttl' = shm_chunk_ttl
                        /\ IF shm_chunk_ttl > 1
                              THEN /\ ctrl_mode' = "NOMINAL"
                              ELSE /\ ctrl_mode' = "DECEL_FALLBACK"
                        /\ LET v_cand == IF shm_chunk_ttl > 1
                                         THEN shm_cmd_vel
                                         ELSE IF shm_cmd_vel > 0 THEN shm_cmd_vel - 1 ELSE 0 IN
                             LET SafeVels ==        {v \in 0..v_cand :
                                             robot_pos + v + BrakingDistance(v) <= EffectiveObstaclePos} IN
                               \E v_safe \in {v \in SafeVels : \A u \in SafeVels : v >= u}:
                                 /\ ctrl_vel' = v_safe
                                 /\ robot_pos' = robot_pos + v_safe
                   ELSE /\ IF ctrl_ttl > 2
                              THEN /\ ctrl_ttl' = ctrl_ttl - 1
                                   /\ ctrl_mode' = "NOMINAL"
                                   /\ LET SafeVels ==        {v \in 0..ctrl_vel :
                                                      robot_pos + v + BrakingDistance(v) <= EffectiveObstaclePos} IN
                                        \E v_safe \in {v \in SafeVels : \A u \in SafeVels : v >= u}:
                                          /\ ctrl_vel' = v_safe
                                          /\ robot_pos' = robot_pos + v_safe
                              ELSE /\ IF ctrl_ttl = 2
                                         THEN /\ ctrl_ttl' = 1
                                              /\ ctrl_mode' = "DECEL_FALLBACK"
                                              /\ LET v_dec == IF ctrl_vel > 0 THEN ctrl_vel - 1 ELSE 0 IN
                                                   LET SafeVels ==        {v \in 0..v_dec :
                                                                   robot_pos + v + BrakingDistance(v) <= EffectiveObstaclePos} IN
                                                     \E v_safe \in {v \in SafeVels : \A u \in SafeVels : v >= u}:
                                                       /\ ctrl_vel' = v_safe
                                                       /\ robot_pos' = robot_pos + v_safe
                                         ELSE /\ ctrl_ttl' = 0
                                              /\ ctrl_mode' = "STANCE_LOCK"
                                              /\ ctrl_vel' = 0
                                              /\ UNCHANGED robot_pos
             /\ pc' = [pc EXCEPT !["Vrka_RT_Spine_500Hz"] = "SpineLoop"]
             /\ UNCHANGED << shm_seq, shm_cmd_vel, shm_chunk_ttl, 
                             shm_threat_epoch, peer_pos, peer_lease_ttl >>

Vrka_RT_Spine_500Hz == SpineLoop \/ SpineTick

PeerLoop == /\ pc["Peer_Wolf_UDP"] = "PeerLoop"
            /\ pc' = [pc EXCEPT !["Peer_Wolf_UDP"] = "PeerStep"]
            /\ UNCHANGED << shm_seq, shm_cmd_vel, shm_chunk_ttl, 
                            shm_threat_epoch, ctrl_mode, ctrl_vel, ctrl_ttl, 
                            robot_pos, peer_pos, peer_lease_ttl >>

PeerStep == /\ pc["Peer_Wolf_UDP"] = "PeerStep"
            /\ \/ /\ \E p \in (robot_pos + BrakingDistance(ctrl_vel))..MAX_CORRIDOR_POS:
                       \E ttl \in 1..MAX_HORIZON_TTL:
                         /\ peer_pos' = p
                         /\ peer_lease_ttl' = ttl
               \/ /\ IF peer_lease_ttl > 0
                        THEN /\ peer_lease_ttl' = peer_lease_ttl - 1
                        ELSE /\ TRUE
                             /\ UNCHANGED peer_lease_ttl
                  /\ UNCHANGED peer_pos
            /\ pc' = [pc EXCEPT !["Peer_Wolf_UDP"] = "PeerLoop"]
            /\ UNCHANGED << shm_seq, shm_cmd_vel, shm_chunk_ttl, 
                            shm_threat_epoch, ctrl_mode, ctrl_vel, ctrl_ttl, 
                            robot_pos >>

Peer_Wolf_UDP == PeerLoop \/ PeerStep

Next == VLA_Proposer_20Hz \/ Vrka_RT_Spine_500Hz \/ Peer_Wolf_UDP

Spec == Init /\ [][Next]_vars

\* END TRANSLATION 
====
