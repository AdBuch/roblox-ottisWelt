--!strict
-- Shared adapter contract without model-builder dependencies.
export type OttiRig = {
	model: Model, humanoid: Humanoid, root: BasePart,
	pelvis: BasePart, chest: BasePart, head: BasePart, rightArm: BasePart, leftArm: BasePart,
	swordParts: {BasePart}, sheathedParts: {BasePart}, shieldFace: BasePart, guardLight: PointLight,
	tail: {segments: {BasePart}, motors: {Motor6D}}, motors: {[string]: Motor6D}, bodyParts: {BasePart},
}
return {}
