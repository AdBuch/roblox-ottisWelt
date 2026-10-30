--!strict
-- Decode authored seven-component bone transforms once; sample without loading online clips.
local BakedBoneClips = {}
function BakedBoneClips.decode(source: any): any
	local clips = {}
	for name, raw in source do
		if name == "bones" then continue end
		local frames = {}
		for _, frame in raw.frames do
			local poses = {}
			for i=1,#source.bones do
				local offset=2+(i-1)*7
				poses[i]=CFrame.new(table.unpack(frame,offset,offset+6))
			end
			table.insert(frames,{time=frame[1],poses=poses})
		end
		clips[name]={duration=raw.duration,frames=frames}
	end
	return clips
end
function BakedBoneClips.sample(clip: any,t: number): {CFrame}
	local frames=clip.frames
	for i=2,#frames do
		local b=frames[i]
		if t<=b.time then
			local a=frames[i-1]
			local alpha=math.clamp((t-a.time)/(b.time-a.time),0,1)
			local poses={}
			for j,cf in a.poses do poses[j]=cf:Lerp(b.poses[j],alpha) end
			return poses
		end
	end
	return frames[#frames].poses
end
return BakedBoneClips
