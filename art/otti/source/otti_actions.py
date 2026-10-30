"""60-fps otter choreography. Analytical paw IK keeps quadruped contacts grounded."""
import bpy,math
from mathutils import Vector,Quaternion,Euler,Matrix

def build_actions(arm,scene):
    scene.render.fps=60;actions={}
    for act in list(bpy.data.actions):
        if act.name.startswith('Otti_'):bpy.data.actions.remove(act)
    def clear():
        for pb in arm.pose.bones:
            pb.rotation_mode='QUATERNION';pb.rotation_quaternion=Quaternion();pb.location=(0,0,0);pb.scale=(1,1,1)
    def pose(name,angles=(0,0,0),loc=None):
        pb=arm.pose.bones[name];rest=arm.data.bones[name].matrix_local.to_quaternion()
        pb.rotation_quaternion=rest.inverted()@Euler(tuple(math.radians(a) for a in angles),'XYZ').to_quaternion()@rest
        if loc is not None:pb.location=rest.inverted()@Vector(loc)
    def world_bone(name,start,end):
        pb=arm.pose.bones[name];rest=arm.data.bones[name].matrix_local.to_quaternion()
        old=rest@Vector((0,1,0));direction=(end-start).normalized()
        q=old.rotation_difference(direction)@rest
        pb.matrix=Matrix.Translation(start)@q.to_matrix().to_4x4()
        bpy.context.view_layer.update()
    def ik(upper,lower,tip,target,pole):
        bpy.context.view_layer.update();start=arm.pose.bones[upper].head.copy()
        a=arm.data.bones[upper].length;b=arm.data.bones[lower].length
        delta=Vector(target)-start;length=max(abs(a-b)+.001,min(delta.length,(a+b)*.985));direction=delta.normalized()
        along=(a*a-b*b+length*length)/(2*length);h=math.sqrt(max(0,a*a-along*along))
        side=Vector(pole)-start;side=(side-direction*side.dot(direction)).normalized()
        elbow=start+direction*along+side*h;end=start+direction*length
        world_bone(upper,start,elbow);world_bone(lower,elbow,end)
        # Orient all four webbed paws along the ground, with their tips toward -Y.
        q=arm.data.bones[tip].matrix_local.to_quaternion();old=q@Vector((0,1,0))
        q=old.rotation_difference(Vector((0,-1,-.12)).normalized())@q
        arm.pose.bones[tip].matrix=Matrix.Translation(end)@q.to_matrix().to_4x4();bpy.context.view_layer.update()
    def tail(t,amount=1,base=0):
        for i in range(6):pose('Tail%02d'%(i+1),(base if i==0 else math.sin(t*math.tau-i*.55)*2.5*amount,0,math.sin(t*math.tau-i*.48)*(3+i*.6)*amount))
    def biped(t):
        a=math.sin(t*math.tau);pose('Lumbar',(a*1.7,0,0));pose('Spine',(-a*.8,0,a*1.6));pose('Chest',(a*1.2,0,0))
        pose('Head',(a*.7,0,-a*1.4));pose('Forearm.R',(-12,0,0));pose('Forearm.L',(-23,0,0));tail(t,.7)
    def walk(t):
        biped(t);a=math.sin(t*math.tau);pose('Pelvis',(0,0,a*4),(0,0,abs(a)*.025))
        for s,side in ((1,'L'),(-1,'R')):
            pose('Thigh.'+side,(s*a*24,0,0));pose('Shin.'+side,(max(0,-s*a)*35,0,0));pose('Foot.'+side,(-max(0,-s*a)*15,0,0));pose('UpperArm.'+side,(-s*a*14,0,0))
        tail(t,1.3)
    def quad(t,running=False,moving=False):
        a=math.sin(t*math.tau) if moving else math.sin(t*math.tau)*.15
        tilt=67+(7*a if running else 2*a)
        pose('Pelvis',(tilt,0,0),(0,0,-.34+(max(0,a)*.07 if running else abs(a)*.012)))
        pose('Lumbar',(-9-a*6,0,a*2));pose('Spine',(a*8,0,0));pose('Chest',(-5-a*4,0,0));pose('Neck',(-46+a*2,0,0));pose('Head',(-7-a*2,0,0))
        tail(t,2 if running else .7,base=-tilt)
        bpy.context.view_layer.update()
        for s,side in ((1,'L'),(-1,'R')):
            # Paired bounding fore/hind contacts, with a small natural left/right offset.
            ph=(t+(0 if side=='L' else .075))%1
            hindph=(ph+.48)%1
            def foot_yz(phase,centre,stride,lift):
                if not moving:return centre,.16
                # Plant through 60% of the cycle; a smooth airborne return in the rest.
                if phase<.60:return centre+stride*(phase/.60-.5),.16
                u=(phase-.60)/.40
                return centre+stride*(.5-u),.16+lift*math.sin(u*math.pi)
            fy,fz=foot_yz(ph,-.67,.42 if running else .23,.16 if running else .07)
            hy,hz=foot_yz(hindph,.14,.32 if running else .20,.13 if running else .06)
            ik('UpperArm.'+side,'Forearm.'+side,'Hand.'+side,(s*.39,fy,fz),(s*.85,.1,.55))
            ik('Thigh.'+side,'Shin.'+side,'Foot.'+side,(s*.25,hy,hz),(s*.55,-.35,.4))
    def keys(t,points):
        for a,b in zip(points,points[1:]):
            if a[0]<=t<=b[0]:
                u=(t-a[0])/(b[0]-a[0]);u=u*u*(3-2*u)
                return [v*(1-u)+w*u for v,w in zip(a[1:],b[1:])]
        return list(points[-1][1:])
    def slash(t,reverse=False,thrust=False):
        biped(t*.4)
        arm_angle,elbow,twist,lean=keys(t,[(0,-12,-12,0,0),(.4,55,-65,-32,-7),(.56,-78,-8,40,12),(.7,-65,-8,32,5),(1,-12,-12,0,0)])
        if reverse:twist=-twist;arm_angle=arm_angle*.8
        if thrust:arm_angle,elbow,twist,lean=keys(t,[(0,-12,-12,0,0),(.4,-10,-95,-15,-6),(.56,-87,-4,12,14),(.7,-82,-8,9,8),(1,-12,-12,0,0)])
        pose('UpperArm.R',(arm_angle,0,-12));pose('Forearm.R',(elbow,0,0));pose('Lumbar',(lean*.35,0,twist*.20));pose('Spine',(lean*.35,0,twist*.45));pose('Chest',(lean*.30,0,twist*.35));pose('Head',(-lean*.45,0,-twist*.65))
        pose('UpperArm.L',(-25,0,18));pose('Forearm.L',(-55,0,0));tail(t,1.4)
    def bash(t):
        slash(t);a=keys(t,[(0,0),(.4,.55),(.56,1),(.75,.8),(1,0)])[0]
        pose('UpperArm.L',(-20-62*a,0,20));pose('Forearm.L',(-65*(1-a),0,0));pose('UpperArm.R',(-15,0,-10))
    def sweep(t,low=False):
        if low:quad(0)
        else:biped(0)
        twist,coil=keys(t,[(0,0,0),(.48,-40,1),(.7,45,-.8),(1,0,0)])
        pose('Lumbar',(0,0,twist*.25));pose('Spine',(0,0,twist*.45));pose('Chest',(0,0,twist*.30));pose('Head',(0,0,-twist*.5))
        for i in range(6):pose('Tail%02d'%(i+1),(-67 if low and i==0 else 3,0,coil*(10-i*.7)))
    def slam(t):
        biped(0);a=keys(t,[(0,0),(.48,1),(.6,-.5),(.8,-.3),(1,0)])[0]
        pose('Chest',(-a*15,0,0));pose('Head',(a*6,0,0))
        for i in range(6):pose('Tail%02d'%(i+1),(-a*(26-i*2),0,0))
    def bite(t):
        quad(0);a=keys(t,[(0,0),(.4,-.25),(.58,1),(.8,.3),(1,0)])[0]
        pose('Neck',(-44+a*9,0,0),(0,-a*.08,0));pose('Head',(-9-a*6,0,0));pose('Jaw',(max(0,1-abs(t-.40)*5)*24,0,0))
    def guard(t):
        biped(0);a=min(1,t/.5);pose('UpperArm.L',(-65*a,0,20*a));pose('Forearm.L',(-45*a,0,0));pose('Spine',(0,0,8*a));pose('Head',(0,0,-6*a))
    def grapple(t):
        biped(0);a,twist=keys(t,[(0,0,0),(.3,.5,0),(.45,1,-12),(.75,1,-22),(.88,.3,38),(1,0,0)])
        for side in ('L','R'):pose('UpperArm.'+side,(-70*a,0,0));pose('Forearm.'+side,(-30*a,0,0))
        pose('Lumbar',(0,0,twist*.3));pose('Chest',(8*a,0,twist*.7))
    def stagger(t):
        biped(0);a=math.sin(t*math.pi)*(1-t*.4);pose('Spine',(-16*a,0,8*a));pose('Chest',(-8*a,0,0));pose('Head',(-12*a,0,-9*a));tail(t,1.8)
    def sit(t):
        biped(t);pose('Pelvis',(-10,0,0),(0,0,-.32));pose('Thigh.L',(-75,0,-13));pose('Thigh.R',(-75,0,13));pose('Shin.L',(70,0,0));pose('Shin.R',(70,0,0));pose('UpperArm.L',(-20,0,20));pose('UpperArm.R',(-20,0,-20));tail(t,.7)
    def celebrate(t):
        sit(t);a=.5+.5*math.sin(t*math.tau*2);pose('UpperArm.L',(-65,0,25*a));pose('UpperArm.R',(-65,0,-25*a));pose('Forearm.L',(-65,0,0));pose('Forearm.R',(-65,0,0));pose('Head',(-7,0,math.sin(t*math.tau)*6))
    def leap(t):
        biped(0);a=math.sin(t*math.pi);pose('Pelvis',(25*a,0,0));pose('Thigh.L',(-65*a,0,0));pose('Thigh.R',(-50*a,0,0));pose('Shin.L',(70*a,0,0));pose('Shin.R',(55*a,0,0));pose('UpperArm.L',(-55*a,0,0));pose('UpperArm.R',(-70*a,0,0));tail(t,1.4)
    def land(t):
        biped(0);a=math.sin(t*math.pi);pose('Pelvis',(12*a,0,0),(0,0,-.17*a));pose('Thigh.L',(-40*a,0,0));pose('Thigh.R',(-40*a,0,0));pose('Shin.L',(65*a,0,0));pose('Shin.R',(65*a,0,0));pose('Chest',(10*a,0,0));tail(t,1.6)
    def surrender(t):
        sit(0);a=min(1,t*1.8);pose('UpperArm.L',(-100*a,0,25*a));pose('Forearm.L',(-10,0,0));pose('Head',(10*a,0,-10*a))
    def rise(t):
        # Matrix-space blend preserves the actual IK contact poses at the quad endpoint.
        quad(0);q={p.name:p.matrix_basis.copy() for p in arm.pose.bones};clear();biped(0)
        b={p.name:p.matrix_basis.copy() for p in arm.pose.bones};u=t*t*(3-2*t)
        for p in arm.pose.bones:p.matrix_basis=q[p.name].lerp(b[p.name],u)
    def feint(t):
        biped(0);a=math.sin(t*math.pi);pose('Spine',(0,0,-12*a));pose('Head',(0,0,8*a));pose('UpperArm.R',(18*a,0,0));pose('Forearm.R',(-40*a,0,0))
    def draw(t):
        biped(0);a=math.sin(t*math.pi);pose('UpperArm.R',(-20*a,0,-20*a));pose('Forearm.R',(-80*a,0,0));pose('Chest',(0,0,-12*a))
    def roar(t):
        biped(t);a=math.sin(t*math.pi);pose('Chest',(-12*a,0,0));pose('Head',(-18*a,0,0));pose('Jaw',(18*a,0,0));pose('UpperArm.R',(-30*a,0,-15*a))
    specs=[('BipedIdle',121,biped),('BipedWalk',49,walk),('QuadIdle',91,lambda t:quad(t)),('QuadWalk',61,lambda t:quad(t,False,True)),('QuadRun',37,lambda t:quad(t,True,True)),('Rise',31,rise),('Slash',43,slash),('Backslash',43,lambda t:slash(t,True)),('Thrust',43,lambda t:slash(t,False,True)),('Bash',49,bash),('Sweep',67,sweep),('Trip',61,lambda t:sweep(t,True)),('Slam',73,slam),('Bite',55,bite),('Grapple',73,grapple),('Guard',31,guard),('Stagger',49,stagger),('Sit',121,sit),('Celebrate',91,celebrate),('Leap',61,leap),('Land',37,land),('Surrender',85,surrender),('Roar',79,roar),('Feint',31,feint),('Draw',43,draw)]
    for name,length,sampler in specs:
        clear();arm.animation_data_create();arm.animation_data.action=None
        act=bpy.data.actions.new('Otti_'+name);act.use_fake_user=True;arm.animation_data.action=act
        for frame in range(1,length+1):
            clear();sampler((frame-1)/(length-1));bpy.context.view_layer.update()
            for pb in arm.pose.bones:
                pb.keyframe_insert(data_path='rotation_quaternion',frame=frame,group=pb.name);pb.keyframe_insert(data_path='location',frame=frame,group=pb.name)
        actions[act.name]=(act,length)
    clear();arm.animation_data.action=None
    return actions
