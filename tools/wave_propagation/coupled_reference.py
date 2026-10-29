"""2D RK transport plus the existing exchange/material rules for flat fixtures.

This reference deliberately refuses above-repose bed states: molded/steep
geometry is verified through native material invariants and stock accounting.
It does not claim to replace the existing full slope reference.
"""
import numpy as np
from reference import Reference

EROSION_RATE=.7295628483661365
DEPOSITION_RATE=.2419645313921744
CAPACITY=.003


class CoupledReference:
    def __init__(self, rock, sand, wetness, compaction, support, obstacle, *, enabled=True, boundary=False, dx=.125):
        self.rock=np.array(rock,dtype=float,copy=True)
        self.sand=np.array(sand,dtype=float,copy=True)
        self.wetness=np.array(wetness,dtype=float,copy=True)
        self.compaction=np.array(compaction,dtype=float,copy=True)
        self.support=np.array(support,dtype=float,copy=True)
        self.obstacle=np.asarray(obstacle,dtype=bool)
        self.enabled=enabled;self.boundary=boundary;self.dx=dx
        self.water=Reference(self.rock+self.sand,dx,obstacle=self.obstacle)
        self.wetness_bound=0.;self.compaction_bound=0.

    @staticmethod
    def half_store(a):
        return np.asarray(a,dtype=np.float16).astype(float)

    @staticmethod
    def half_ulp(a):
        return float(np.spacing(np.float16(np.max(a))))

    def apply_boundary(self,state,level=.52):
        if not self.boundary:return state
        state=state.copy()
        # Same actual f32 configuration values and bed storage as GPU reservoir.
        bed=(self.rock[:,0]+self.sand[:,0]).astype(np.float32)
        state[0,:,0]=np.maximum(np.float32(level)-bed,0).astype(float)
        state[1:3,:,0]=0.
        return state

    def step(self,state,dt):
        self.water.bed=self.rock+self.sand
        a=self.water.euler(state,dt)
        if self.boundary:a.state[1:3,:,0]=0
        b=self.water.euler(a.state,dt)
        if self.boundary:b.state[1:3,:,0]=0
        result=.5*(state+b.state);self.water.limit_momentum(result)
        if self.boundary:result[1:3,:,0]=0
        transported=result.copy();exchange={'eroded_m3':0.,'deposited_m3':0.}
        if not self.enabled:return result,transported,exchange
        h=result[0]
        speed=np.hypot(result[1],result[2])/np.maximum(h,.005)
        capacity=np.where(h>.001,np.minimum(h/(1./30.),1.)*CAPACITY*speed,0.)
        weight=(~self.obstacle).astype(float)
        if self.boundary:weight[:,0]=0
        suspended=result[3]
        eroded=np.minimum(self.sand,np.maximum(capacity-suspended,0)*(-np.expm1(-EROSION_RATE*dt))*weight)
        deposited=np.minimum(suspended,np.maximum(suspended-capacity,0)*(-np.expm1(-DEPOSITION_RATE*dt))*weight)
        self.sand=(self.sand-eroded+deposited).astype(np.float32).astype(float)
        result[3]=suspended+eroded-deposited
        exchange={'eroded_m3':float(eroded.sum()*self.dx**2),'deposited_m3':float(deposited.sum()*self.dx**2)}
        tag=np.clip(self.support[:,:,0]-np.maximum(self.support[:,:,1]-self.sand,0),0,self.sand)
        # All these fixtures stay strictly below the smallest repose drop.
        bed=self.rock+self.sand
        drop=max(float(abs(np.diff(bed,axis=axis)).max()) for axis in (0,1))
        if drop>=.674*self.dx:
            raise ValueError('fixture outside no-slope reference; use full slope/invariant evidence')
        next_wet=self.wetness.copy();next_compact=self.compaction.copy()
        target=np.clip(h/.06,0,1)
        wet=np.where(h>.001,np.minimum(np.maximum(self.wetness,target),self.wetness+1.5*dt*target),np.maximum(.05,self.wetness-.07*dt))
        padded=np.pad(self.wetness,1,mode='edge')
        neighbours=padded[1:-1,:-2]+padded[1:-1,2:]+padded[:-2,1:-1]+padded[2:,1:-1]
        wet+=np.clip(4*dt,0,.5)*(neighbours-4*self.wetness)*.25
        compact=self.compaction+np.maximum(wet-.05,0)*.05*dt*(1-self.compaction)
        free=~self.obstacle
        next_wet[free]=np.clip(wet[free],0,1);next_compact[free]=np.clip(compact[free],0,1)
        # A priori FP16-store bounds, not fitted to material output. One ulp
        # covers either nearest or directed conversion; recurrence is bounded.
        self.wetness_bound+=self.half_ulp(next_wet)+8*np.finfo(np.float32).eps
        self.compaction_bound+=.05*dt*self.wetness_bound+self.half_ulp(next_compact)+8*np.finfo(np.float32).eps*max(float(next_compact.max()),1e-6)
        self.wetness=self.half_store(next_wet);self.compaction=self.half_store(next_compact)
        self.support=np.stack((tag,np.where(tag>0,self.sand,0)),axis=-1).astype(np.float32).astype(float)
        return result,transported,exchange
